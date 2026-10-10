#!/usr/bin/env bash
# Builds the patched cosmic-comp for the cosmic-comp version Fedora has installed.
# Usage: rebuild.sh [--force]. See local-patch/README.md.
set -euo pipefail

share="$HOME/.local/share/cosmic-comp-patched"
repo="${COSMIC_COMP_REPO:-$HOME/repos/cosmic-comp}"
builds="$HOME/.local/lib/cosmic-comp-patched"
work="$HOME/.cache/cosmic-comp-patched"

version=$(rpm -q --qf '%{VERSION}' cosmic-comp)
installed=$(rpm -q --qf '%{VERSION}-%{RELEASE}' cosmic-comp)
tag="epoch-$version"
out="$builds/$installed"

notify() {
    logger -t cosmic-comp-patched "$1: $2"
    notify-send -a "Patched cosmic-comp" "$1" "$2" 2>/dev/null || true
}

if [[ -x "$out/cosmic-comp" && "${1:-}" != "--force" ]]; then
    echo "Already built for cosmic-comp $installed: $out/cosmic-comp"
    exit 0
fi

git -C "$repo" fetch -q upstream --tags
if ! git -C "$repo" rev-parse -q --verify "refs/tags/$tag" >/dev/null; then
    notify "No upstream tag $tag" "Running stock cosmic-comp $installed until the patch is ported."
    exit 1
fi

worktree="$work/src"
cleanup() {
    git -C "$repo" worktree remove --force "$worktree" 2>/dev/null || true
    rm -rf "$work/target"
}
trap cleanup EXIT
cleanup
mkdir -p "$work"
git -C "$repo" worktree add -q --detach "$worktree" "$tag"

# No `-3`: a 3-way merge resolves overlaps silently, so a patch whose context moved is ported by
# hand instead of shipping an unreviewed merge.
if ! git -C "$worktree" am -q "$share"/patches/*.patch; then
    git -C "$worktree" am --abort 2>/dev/null || true
    notify "Patch no longer applies cleanly to $tag" "Running stock cosmic-comp $installed until the patch is ported."
    exit 1
fi

if ! (cd "$worktree" && CARGO_TARGET_DIR="$work/target" cargo build --release --locked); then
    notify "Patched cosmic-comp failed to build for $installed" "Running stock until fixed; see: journalctl --user -u cosmic-comp-patched-rebuild"
    exit 1
fi

install -D -m755 "$work/target/release/cosmic-comp" "$out/cosmic-comp"
# Keep the new build and the previous one; the running compositor may still be the previous one.
ls -1dt "$builds"/*/ | tail -n +3 | xargs -r rm -rf
notify "Patched cosmic-comp ready for $installed" "Log out and back in to use it."

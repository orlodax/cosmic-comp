#!/usr/bin/env bash
# Installs the local cosmic-comp patch tooling and builds it for the installed version. See README.md.
set -euo pipefail

src="$(cd "$(dirname "$0")" && pwd)"
share="$HOME/.local/share/cosmic-comp-patched"

mkdir -p "$share/patches" "$HOME/.config/systemd/user" "$HOME/.local/bin"
rm -f "$share"/patches/*.patch
install -m644 "$src"/patches/*.patch "$share/patches/"
install -m755 "$src/rebuild.sh" "$share/rebuild.sh"
install -m644 "$src"/systemd/cosmic-comp-patched-rebuild.* "$HOME/.config/systemd/user/"

# Build before swapping in the wrapper, so the next login already has a matching patched build.
"$share/rebuild.sh"
install -m755 "$src/cosmic-comp-wrapper" "$HOME/.local/bin/cosmic-comp"

systemctl --user daemon-reload
systemctl --user enable --now cosmic-comp-patched-rebuild.path cosmic-comp-patched-rebuild.timer
echo "Installed. Log out and back in to start the patched cosmic-comp."

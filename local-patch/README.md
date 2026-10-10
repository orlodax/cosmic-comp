# Local cosmic-comp patch: redraw failure back-off

A local-only build of Fedora's `cosmic-comp` with two fixes for an output that the kernel refuses to
bring back after the screens sleep (NVIDIA GTX 1060, three monitors):

- `0001`: retry a failed frame with a back-off (one frame time, doubling, capped at 4 s) instead of
  thousands of times per second; after 12 consecutive KMS rejections, give the output up so display
  changes work again (the first `cosmic-randr disable` is accepted).
- `0002`: on the next screen wake, re-apply the output config once, so a given-up output can come back.
- `0003`: while an output is given up, fail its screen captures at once instead of leaving them
  queued forever (the screenshot portal waited on them, so Flameshot hung).

It stays local. pop-os does not accept LLM-generated contributions in issues or PRs (see the PR
template and https://github.com/pop-os/pop/blob/master/CONTRIBUTING.md); upstream PR #2917 was closed
for that reason. Upstream issues: pop-os/cosmic-comp#2688 (retry loop), #1980 (NVIDIA bring-up).

## How it survives COSMIC updates

| Piece | Where | What it does |
|---|---|---|
| wrapper | `~/.local/bin/cosmic-comp` | At login, starts the patched build only if one exists for the installed `cosmic-comp` package version; otherwise starts `/usr/bin/cosmic-comp`. A mismatched compositor never runs. |
| builds | `~/.local/lib/cosmic-comp-patched/<version-release>/` | One patched binary per Fedora package version (the newest two are kept). |
| patches + `rebuild.sh` | `~/.local/share/cosmic-comp-patched/` | Applies the patches on the upstream tag `epoch-<version>` and builds it. |
| `.path` + `.timer` units | `~/.config/systemd/user/` | Run the rebuild when dnf replaces `/usr/bin/cosmic-comp`, and daily as a backstop. |

After a COSMIC update you get a notification when the new patched build is ready; log out and back in
to use it. Until then (or if the patch no longer applies) the wrapper runs stock, so the worst case is
the stock behaviour, never a broken session.

The session finds `~/.local/bin` before `/usr/bin` in its PATH. The login screen (cosmic-greeter) always
uses `/usr/bin/cosmic-comp`.

## Commands

Needs the build deps once: `sudo dnf builddep cosmic-comp`, and this repo at `~/repos/cosmic-comp`
with the `upstream` remote (`https://github.com/pop-os/cosmic-comp`).

```bash
local-patch/install.sh                                          # install, build, enable (then log out/in)
systemctl --user start cosmic-comp-patched-rebuild.service       # rebuild now
~/.local/share/cosmic-comp-patched/rebuild.sh --force            # rebuild even if a build exists
journalctl --user -u cosmic-comp-patched-rebuild                 # rebuild log
journalctl -t cosmic-comp-patched                                # notifications and wrapper fallbacks
readlink /proc/$(pgrep -xo -u "$USER" cosmic-comp)/exe           # which binary is running
```

Uninstall (then log out/in):

```bash
systemctl --user disable --now cosmic-comp-patched-rebuild.path cosmic-comp-patched-rebuild.timer
rm ~/.config/systemd/user/cosmic-comp-patched-rebuild.* ~/.local/bin/cosmic-comp
rm -r ~/.local/share/cosmic-comp-patched ~/.local/lib/cosmic-comp-patched ~/.cache/cosmic-comp-patched
```

If the session does not come up: Ctrl+Alt+F3, log in, `mv ~/.local/bin/cosmic-comp ~/.local/bin/cosmic-comp.off`,
Ctrl+Alt+F1, log in.

## When the patch stops applying

The notification says "Patch no longer applies cleanly to epoch-X". `rebuild.sh` applies the patches
without `-3`, so any hunk whose context moved stops the build; port it by hand and read the result. Port it in a worktree on that tag, then
regenerate the patch files on this branch (`fix/redraw-failure-backoff`, where `local-patch/` lives)
and reinstall:

```bash
cd ~/repos/cosmic-comp && git fetch upstream --tags
git worktree add ../cosmic-comp-port epoch-X
git -C ../cosmic-comp-port am -3 "$PWD"/local-patch/patches/*.patch   # resolve, then `git am --continue`
rm local-patch/patches/*.patch
git -C ../cosmic-comp-port format-patch -o "$PWD/local-patch/patches" epoch-X..HEAD
git worktree remove ../cosmic-comp-port
git add local-patch/patches && git commit -m "local-patch: port to epoch-X"
local-patch/install.sh
```

Verified 2026-10-05: both patches apply cleanly to `epoch-1.8.0` (Fedora `cosmic-comp-1.8.0-1.fc44`)
and to upstream master `3d55cba0`; unit tests pass on both. Verified 2026-10-10: all three apply
without `-3` to `epoch-1.10.0`.

## What to expect when a screen fails at wake

The log shows one `retrying with back-off` warning, then about 14 s later one `giving up` error, and
nothing more. To bring the screen back: blank the screens briefly
(`wlopm --off '*'; sleep 5; wlopm --on '*'`), or `cosmic-randr disable <output>` followed by
`~/.local/bin/fix-hdmi`. While the dead output is still enabled, display-settings changes that keep it
enabled are rejected; disabling it works.

Screenshots fail while an output is given up (Flameshot reports an error, the portal answers
`Response 2`; read from the code, not yet seen live), as stock does when KMS rejects the frame;
they work again once the output is back.
Before `0003` they hung instead.

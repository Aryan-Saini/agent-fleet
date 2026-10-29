# vorssaint

[Vorssaint](https://github.com/vorssaint/vorssaint-utils) is a free, open source macOS menu bar
toolkit that replaces a dozen paid utilities: window snapping, an app switcher, clipboard
history, screenshots and recording with text recognition, a Dynamic Island in the notch, fan
control, and more. It is the app I run all day on the controller. GPL-3.0, local-first, Apple
Silicon, macOS 14 or newer.

For controllers. Workers are headless and have no menu bar.

## Install

```bash
brew install --cask vorssaint
open -a Vorssaint
```

Setup asks only for the permissions the features you pick need. Install only the features you
use from Settings → Features; uninstalled features stop loading entirely.

Release builds are signed, notarized and check for updates themselves, so `/fleet-update` only
needs `brew upgrade --cask vorssaint` if the app fell behind.

## Run your own build (optional)

I run a build from my fork instead of the release, so fixes I send upstream reach me before they
merge. Do this only if you plan to change the code. The release is the better default.

The pattern, which also works for any other app you patch:

| branch | what it is |
| --- | --- |
| `main` | a pure mirror of upstream. Never commit to it |
| `my-changes` | your patches, rebased onto `main` on every update |

```bash
git clone https://github.com/vorssaint/vorssaint-utils.git ~/tools/vorssaint
cd ~/tools/vorssaint
gh repo fork --remote --remote-name fork    # origin stays upstream, your fork is "fork"
git switch -c my-changes
./build.sh --dev --install          # installs /Applications/Vorssaint DEV.app
```

`--dev` builds a separate app, `Vorssaint DEV` (bundle id `com.vorssaint.utils.dev`), which
installs next to the release and never updates itself. Quit the release app so the two don't
fight over the menu bar and hotkeys.

Updating is one sequence. Put it in a script and run it from `/fleet-update`:

```bash
cd ~/tools/vorssaint
git fetch origin
git switch main && git merge --ff-only origin/main
git switch my-changes && git rebase main     # resolve conflicts, or have an agent do it
./build.sh --dev --install
git push --force-with-lease fork my-changes  # back up your patches
```

- **Sign with a stable identity.** macOS ties Accessibility and Screen Recording grants to the
  signature. An ad hoc signature changes on every build, so every rebuild silently drops the
  grants. Set `VORSSAINT_SIGN_IDENTITY` to your Apple Development certificate's SHA-1
  (`security find-identity -v -p codesigning`).
- **Keep upstream changes manual.** Have a nightly job only report when upstream is ahead
  (`git rev-list --count main..origin/main`) and run the update yourself. Then an upstream change
  can never break the app you use all day without you noticing.
- **Trademarks.** The GPL covers the code. The Vorssaint name, icon and look are covered by
  upstream's `TRADEMARKS.md`, so keep the DEV build for yourself and don't redistribute it.

## Verify

```bash
packages/vorssaint/check.sh && echo ok
```

## Gotchas

- It is a menu bar app with no Dock icon. "Is it running" means checking the menu bar or
  `pgrep -x Vorssaint`.
- An app quit by an update stays quit. `check.sh --heal` relaunches it, and `fleet health` runs
  that for you on the controller.

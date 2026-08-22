# MPC-HC AutoSkip

A deliberately thin fork of `clsid2/mpc-hc` that adds native automatic chapter skipping without modifying media files.

## What the patch does

MPC-HC already exposes the current chapter through its internal chapter bag and already has a built-in **Next Chapter** command. AutoSkip adds a tiny policy layer to the existing stream-position timer:

1. Read the current chapter title.
2. Compare it case-insensitively against a configurable semicolon-separated list.
3. If it matches, post MPC-HC's existing `ID_NAVIGATE_SKIPFORWARD` command.
4. Debounce the current chapter index so one timer interval cannot spam the command.

The normal MPC-HC behavior is preserved: if the skipped chapter is the final chapter, the existing Next Chapter command can continue to the next file/playlist item exactly as it normally would.

## UI

Open:

**Options > Advanced > Playback**

Defaults in this fork:

- `AutoSkipChapters` = `True`
- `AutoSkipChapterPatterns` = `opening;ending;yokoku;preview`

Matching is a case-insensitive substring match. `Avant` is intentionally not in the default list.

## Automatic upstream maintenance

`.github/workflows/autosync-build.yml` runs daily and can also be triggered manually.

It:

- fetches `clsid2/mpc-hc:develop`;
- merges upstream only in the temporary Actions workspace;
- verifies the AutoSkip source markers;
- builds MPC-HC x64 against an explicitly detected installed Windows SDK;
- pushes the merge **only after the build succeeds**;
- publishes a ZIP release;
- leaves the last working release untouched on failure;
- opens a GitHub issue containing the failing upstream SHA and Actions link if a merge or build breaks.

That means an upstream break cannot automatically replace your working player. Pull requests to `autoskip` also run the same real x64 build before they can be treated as validated.

## VS Code + local helper scripts

The bootstrap opens this repository in VS Code and installs three ready-made **Terminal > Run Task** entries for sync/build, install-latest, and watch-build.


- `scripts/Update-Now.ps1` — trigger the upstream sync/build immediately and watch it.
- `scripts/Install-Latest.ps1` — download the newest successful release and install/overlay it in `%LOCALAPPDATA%\Programs\MPC-HC-AutoSkip` by default.
- `scripts/Watch-Build.ps1` — watch the most recent build.
- `.autoskip/Build-X64.ps1` — shared Windows build harness used by both upstream-sync CI and pull-request CI.

## License

MPC-HC is GPLv3. This fork and its modifications remain under the same license. See the upstream `COPYING.txt` included in the source tree.

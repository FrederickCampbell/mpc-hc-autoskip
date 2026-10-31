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
- resolves the known two-setting conflict only when it can prove no other fork changes would be discarded, and aborts unfamiliar conflicts cleanly;
- verifies AutoSkip's implementation, timer hook, saved settings, and both UI entries;
- builds MPC-HC x64 against an explicitly detected installed Windows SDK;
- validates the x64 player, codecs, renderer, translations, shaders, and license before producing the ZIP and its SHA-256 checksum;
- pushes the merge **only after building and packaging succeed**, and refuses publication if the branch changed meanwhile;
- uploads and verifies candidate assets before replacing the rolling downloads, retaining the prior assets until the tag and metadata updates succeed;
- rolls back failed publication changes and reports any recovery failure explicitly;
- reports the upstream/candidate revisions and first build error in the Actions summary;
- retries a build on the next scheduled run when the rolling release is behind, even if the upstream merge was already pushed.

Publication runs are serialized rather than cancelled halfway through. Unknown source/API changes still require a reviewed fix; the automation does not choose an entire side of an unfamiliar conflict. Pull requests test real conflict/rollback cases and run the same sync, x64 build, and package validation as production.

The build selects Visual Studio 2022/v143 and a complete installed Windows SDK. The MinGW archive, NASM installation version, checkout action, translation dependency, and renderer component are pinned; downloads have bounded retries and PATH refreshes remove duplicate entries. Change pinned tool versions deliberately and let the PR checks validate the update.

## VS Code + local helper scripts

The bootstrap opens this repository in VS Code and installs three ready-made **Terminal > Run Task** entries for sync/build, install-latest, and watch-build.


- `scripts/Update-Now.ps1` — trigger the upstream sync/build immediately and watch it.
- `scripts/Install-Latest.ps1` — download `autoskip-latest`, verify the ZIP digest and package before replacing files, and install/overlay it in `%LOCALAPPDATA%\Programs\MPC-HC-AutoSkip` while preserving portable settings.
- `scripts/Watch-Build.ps1` — watch the most recent build.
- `.autoskip/Build-X64.ps1` — shared Windows build harness used by both upstream-sync CI and pull-request CI.

## License

MPC-HC is GPLv3. This fork and its modifications remain under the same license. See the upstream `COPYING.txt` included in the source tree.

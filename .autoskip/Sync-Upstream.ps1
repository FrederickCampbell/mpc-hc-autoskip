# Copyright (C) 2026 MPC-HC AutoSkip contributors. GPL-3.0-or-later.
[CmdletBinding()]
param(
    [string]$RepoRoot = ([IO.Directory]::GetParent($PSScriptRoot).FullName),
    [string]$UpstreamUrl = 'https://github.com/clsid2/mpc-hc.git',
    [string]$UpstreamBranch = 'develop',
    [switch]$ForceBuild,
    [switch]$EnsureReleaseCurrent,
    [string]$OutputPath = $env:GITHUB_OUTPUT
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

function Invoke-Git {
    param([Parameter(ValueFromRemainingArguments)] [string[]]$Arguments, [switch]$AllowFailure)
    $lines = @(& git -C $RepoRoot @Arguments 2>&1)
    $code = $LASTEXITCODE
    $result = ($lines | ForEach-Object { "$_" }) -join "`n"
    if ($code -ne 0 -and -not $AllowFailure) {
        throw "git $($Arguments -join ' ') failed (exit $code):`n$result"
    }
    [pscustomobject]@{ Code = $code; Text = $result }
}

function Set-SyncOutput {
    param([string]$Name, [string]$Value)
    if ($OutputPath) { [IO.File]::AppendAllText($OutputPath, "$Name=$Value`n", [Text.UTF8Encoding]::new($false)) }
}

function Get-SettingLines {
    param([string]$Text)
    $patterns = @(
        '(?m)^[\t ]*addBoolItem\s*\(\s*AUTOSKIP_CHAPTERS\s*,[^\r\n]*\);[\t ]*(?:\r?\n|$)',
        '(?m)^[\t ]*addCStringItem\s*\(\s*AUTOSKIP_CHAPTER_PATTERNS\s*,[^\r\n]*\);[\t ]*(?:\r?\n|$)'
    )
    $remaining = $Text -replace "`r`n", "`n"
    $settings = @()
    foreach ($pattern in $patterns) {
        $matches = [regex]::Matches($remaining, $pattern)
        if ($matches.Count -ne 1) { throw 'Expected exactly one of each AutoSkip settings entry; refusing automatic conflict resolution.' }
        $settings += $matches[0].Value.Trim()
        $remaining = [regex]::Replace($remaining, $pattern, '')
    }
    [pscustomobject]@{ Remaining = $remaining.TrimEnd("`n"); Settings = $settings }
}

function Resolve-AutoSkipSettings {
    $path = 'src/mpc-hc/PPageAdvanced.cpp'
    $baseText = (Invoke-Git @('show', ":1:$path")).Text -replace "`r`n", "`n"
    $ours = Get-SettingLines (Invoke-Git @('show', ":2:$path")).Text
    $theirs = (Invoke-Git @('show', ":3:$path")).Text
    # Checking the entire fork/base difference prevents --theirs from discarding
    # unrelated local changes merely because they happen to be in this file.
    if ($ours.Remaining -cne $baseText.TrimEnd("`n")) {
        throw 'The settings conflict includes fork changes beyond the two AutoSkip entries; manual resolution is required.'
    }
    if ($theirs -match 'AUTOSKIP_CHAPTERS|AUTOSKIP_CHAPTER_PATTERNS') {
        throw 'Upstream now has AutoSkip entries; review them instead of inserting duplicates.'
    }
    $anchorPattern = '(?m)^(?<indent>[\t ]*)addBoolItem\s*\(\s*LOOP_FOLDER_NEXT_FILE\s*,[^\r\n]*\);[\t ]*\r?$'
    $anchors = [regex]::Matches($theirs, $anchorPattern)
    if ($anchors.Count -ne 1) { throw 'The upstream playback settings anchor changed; manual resolution is required.' }
    $anchor = $anchors[0]
    $newline = if ([IO.File]::ReadAllText((Join-Path $RepoRoot $path)).Contains("`r`n")) { "`r`n" } else { "`n" }
    $text = $theirs -replace "`r`n", "`n"
    $insertion = "`n" + (($ours.Settings | ForEach-Object { $anchor.Groups['indent'].Value + $_ }) -join "`n")
    $text = $text.Insert($anchor.Index + $anchor.Value.TrimEnd("`r").Length, $insertion)
    [IO.File]::WriteAllText((Join-Path $RepoRoot $path), ($text.TrimEnd("`n") + "`n").Replace("`n", $newline), [Text.UTF8Encoding]::new($false))
    $null = Invoke-Git @('add', '--', $path)
    $null = Invoke-Git @('diff', '--cached', '--check', '--', $path)
    Write-Host 'Preserved upstream settings changes and restored the two AutoSkip entries.'
}

Set-SyncOutput build_needed false
Set-SyncOutput had_merge false
$mergeStarted = $false
try {
    $initial = (Invoke-Git @('rev-parse', '--verify', 'HEAD')).Text.Trim()
    Set-SyncOutput initial_sha $initial
    if ((Invoke-Git @('status', '--porcelain', '--untracked-files=no')).Text) {
        throw 'Tracked files are modified; commit or stash them before syncing upstream.'
    }
    $remotes = (Invoke-Git @('remote')).Text -split "`n"
    if ('upstream' -notin $remotes) { $null = Invoke-Git @('remote', 'add', 'upstream', $UpstreamUrl) }
    else { $null = Invoke-Git @('remote', 'set-url', 'upstream', $UpstreamUrl) }
    $fetch = Invoke-Git @('fetch', '--tags', 'upstream', "+refs/heads/${UpstreamBranch}:refs/remotes/upstream/$UpstreamBranch")
    Write-Host $fetch.Text
    $upstream = (Invoke-Git @('rev-parse', '--verify', "refs/remotes/upstream/${UpstreamBranch}^{commit}")).Text.Trim()
    Set-SyncOutput upstream_sha $upstream
    Set-SyncOutput upstream_short $upstream.Substring(0, 8)
    $ancestor = Invoke-Git @('merge-base', '--is-ancestor', $upstream, 'HEAD') -AllowFailure
    if ($ancestor.Code -notin @(0, 1)) { throw "Could not determine upstream ancestry: $($ancestor.Text)" }
    if ($ancestor.Code -eq 0) {
        $build = $ForceBuild.IsPresent
        if ($EnsureReleaseCurrent -and -not $build) {
            $tags = (Invoke-Git @('ls-remote', 'origin', 'refs/tags/autoskip-latest', 'refs/tags/autoskip-latest^{}')).Text -split "`n"
            $published = ''
            foreach ($line in $tags) {
                if ($line -match '^([0-9a-f]+)\s+refs/tags/autoskip-latest(?:\^\{\})?$') { $published = $Matches[1] }
            }
            $build = $published -ne $initial
            if ($build) { Write-Host 'The rolling release is behind this checkout; retrying the build/publication.' }
        }
        Set-SyncOutput candidate_sha $initial
        Set-SyncOutput build_needed $build.ToString().ToLowerInvariant()
        Write-Host 'Upstream is already included in this checkout.'
        return
    }

    $mergeStarted = $true
    $merge = Invoke-Git @('merge', '--no-commit', '--no-ff', $upstream) -AllowFailure
    if ($merge.Code -ne 0) {
        $unmergedText = (Invoke-Git @('diff', '--name-only', '--diff-filter=U')).Text
        $unmerged = @($unmergedText -split "`n" | Where-Object { $_ })
        if ($unmerged.Count -ne 1 -or $unmerged[0] -ne 'src/mpc-hc/PPageAdvanced.cpp') {
            throw "Unexpected upstream merge conflict or merge failure: $($unmerged -join ', ')`n$($merge.Text)"
        }
        Resolve-AutoSkipSettings
    }
    if ((Invoke-Git @('diff', '--name-only', '--diff-filter=U')).Text) { throw 'Unresolved merge conflicts remain.' }
    $null = Invoke-Git @('commit', '--no-edit')
    $mergeStarted = $false
    $candidate = (Invoke-Git @('rev-parse', '--verify', 'HEAD')).Text.Trim()
    Set-SyncOutput candidate_sha $candidate
    Set-SyncOutput had_merge true
    Set-SyncOutput build_needed true
    Write-Host "Prepared upstream $upstream in candidate $candidate; nothing has been pushed."
}
catch {
    $reason = $_
    Set-SyncOutput sync_failed true
    if ($mergeStarted) {
        $abort = Invoke-Git @('merge', '--abort') -AllowFailure
        if ($abort.Code -ne 0) { Write-Warning "Could not abort the failed merge: $($abort.Text)" }
    }
    throw $reason
}

# Copyright (C) 2026 MPC-HC AutoSkip contributors. GPL-3.0-or-later.
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string]$Repository,
    [Parameter(Mandatory)] [string]$CandidateSha,
    [Parameter(Mandatory)] [string]$UpstreamSha,
    [Parameter(Mandatory)] [string]$Zip,
    [Parameter(Mandatory)] [string]$Checksum,
    [string]$Version = '',
    [string]$RunUrl = '',
    [string]$RepoRoot = ([IO.Directory]::GetParent($PSScriptRoot).FullName)
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false
$tag = 'autoskip-latest'
$api = "repos/$Repository/releases"
$token = [guid]::NewGuid().ToString('N')
$temp = Join-Path ([IO.Path]::GetTempPath()) "autoskip-publish-$token"
$newAssets = [Collections.Generic.List[object]]::new()
$backups = [Collections.Generic.List[object]]::new()
$createdRelease = $false
$metadataTouched = $false
$tagTouched = $false
$oldTag = ''
$snapshot = $null

function Invoke-Native {
    param([string]$Command, [string[]]$Arguments, [switch]$AllowFailure)
    $output = @(& $Command @Arguments 2>&1)
    $code = $LASTEXITCODE
    $text = ($output | ForEach-Object { "$_" }) -join "`n"
    if ($code -ne 0 -and -not $AllowFailure) { throw "$Command $($Arguments -join ' ') failed (exit $code): $text" }
    [pscustomobject]@{ Code = $code; Text = $text }
}
function Invoke-Gh {
    param([Parameter(ValueFromRemainingArguments)] [string[]]$Arguments)
    (Invoke-Native gh $Arguments).Text
}
function Invoke-RepoGit {
    param([Parameter(ValueFromRemainingArguments)] [string[]]$Arguments)
    (Invoke-Native git (@('-C', $RepoRoot) + $Arguments)).Text
}
function Rename-Asset { param($Asset, [string]$Name); $null = Invoke-Gh api "$api/assets/$($Asset.id)" --method PATCH -f "name=$Name" }
function Assert-CandidateCurrent {
    $branch = Invoke-RepoGit ls-remote --exit-code origin refs/heads/autoskip
    if (($branch -split '\s+')[0] -ne $CandidateSha) { throw 'autoskip advanced after the tested candidate was pushed; refusing stale publication.' }
}

try {
    Assert-CandidateCurrent
    $tagLine = Invoke-RepoGit ls-remote --refs origin "refs/tags/$tag"
    if ($tagLine) { $oldTag = ($tagLine -split '\s+')[0] }
    $response = Invoke-Native -Command gh -Arguments @('api', "$api/tags/$tag") -AllowFailure
    if ($response.Code -ne 0 -and $response.Text -notmatch 'HTTP 404') { throw "Could not inspect the existing release: $($response.Text)" }
    New-Item $temp -ItemType Directory | Out-Null
    if ($response.Code -eq 0) { $snapshot = $response.Text | ConvertFrom-Json }
    else {
        $snapshot = (Invoke-Gh api $api --method POST -f "tag_name=$tag" -f "target_commitish=$CandidateSha" -f 'name=MPC-HC AutoSkip (Latest)' -F draft=true) | ConvertFrom-Json
        $createdRelease = $true
    }
    $assets = @(@{ Source = $Zip; Name = [IO.Path]::GetFileName($Zip) }, @{ Source = $Checksum; Name = [IO.Path]::GetFileName($Checksum) })
    foreach ($asset in $assets) {
        $stagedName = "candidate-$token-$($asset.Name).pending"
        $stagedPath = Join-Path $temp $stagedName
        Copy-Item -LiteralPath $asset.Source -Destination $stagedPath
        $null = Invoke-Gh release upload $tag $stagedPath --repo $Repository
        $release = (Invoke-Gh api "$api/tags/$tag") | ConvertFrom-Json
        $uploaded = @($release.assets | Where-Object name -eq $stagedName)
        if ($uploaded.Count -ne 1) { throw "Could not locate uploaded candidate: $stagedName" }
        $newAssets.Add($uploaded[0])
        $digest = 'sha256:' + (Get-FileHash -LiteralPath $stagedPath -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($uploaded[0].size -ne (Get-Item -LiteralPath $stagedPath).Length -or $uploaded[0].digest -ne $digest) {
            throw "GitHub candidate size/digest verification failed: $stagedName"
        }
    }

    # Upload and verify both candidates before touching the working downloads.
    # Keep the prior assets by ID until the names, tag, and metadata all commit.
    Assert-CandidateCurrent
    for ($i = 0; $i -lt $assets.Count; $i++) {
        $name = $assets[$i].Name
        $old = @($snapshot.assets | Where-Object name -eq $name)
        foreach ($asset in $old) {
            $backups.Add([pscustomobject]@{ id = $asset.id; name = $name })
            Rename-Asset $asset "previous-$token-$name.pending"
        }
        Rename-Asset $newAssets[$i] $name
    }
    Assert-CandidateCurrent
    $tagTouched = $true
    $null = Invoke-RepoGit push "--force-with-lease=refs/tags/${tag}:$oldTag" origin "${CandidateSha}:refs/tags/$tag"
    $notes = Join-Path $temp 'notes.md'
    @"
Latest automatic x64 build of MPC-HC with native chapter AutoSkip.

- AutoSkip version: $Version
- Upstream: clsid2/mpc-hc@$UpstreamSha
- Fork commit: $CandidateSha
- Workflow: $RunUrl

Configure **Options > Advanced > Playback**: AutoSkipChapters and AutoSkipChapterPatterns.
The .sha256 file verifies the ZIP download.
"@ | Set-Content -LiteralPath $notes -Encoding utf8
    $metadataTouched = $true
    $null = Invoke-Gh release edit $tag --repo $Repository --title 'MPC-HC AutoSkip (Latest)' --notes-file $notes --draft=false --latest
    Write-Host "Published and verified $tag for $CandidateSha."
}
catch {
    $reason = $_
    $recoveryErrors = [Collections.Generic.List[string]]::new()
    foreach ($asset in $newAssets) {
        try { $null = Invoke-Gh api "$api/assets/$($asset.id)" --method DELETE } catch { $recoveryErrors.Add("$_") }
    }
    foreach ($asset in $backups) {
        try { Rename-Asset $asset $asset.name } catch { $recoveryErrors.Add("$_") }
    }
    if ($tagTouched) {
        try {
            $current = Invoke-RepoGit ls-remote --refs origin "refs/tags/$tag"
            if ($current -and ($current -split '\s+')[0] -eq $CandidateSha) {
                $ref = if ($oldTag) { "${oldTag}:refs/tags/$tag" } else { ":refs/tags/$tag" }
                $null = Invoke-RepoGit push "--force-with-lease=refs/tags/${tag}:$CandidateSha" origin $ref
            }
        } catch { $recoveryErrors.Add("$_") }
    }
    if ($metadataTouched -and -not $createdRelease) {
        try { $null = Invoke-Gh api "$api/$($snapshot.id)" --method PATCH -f "name=$($snapshot.name)" -f "body=$($snapshot.body)" -F "draft=$($snapshot.draft.ToString().ToLowerInvariant())" } catch { $recoveryErrors.Add("$_") }
    }
    if ($createdRelease) {
        try { $null = Invoke-Gh api "$api/$($snapshot.id)" --method DELETE } catch { $recoveryErrors.Add("$_") }
    }
    if ($recoveryErrors.Count) { throw "$reason`nPublication rollback needs attention:`n$($recoveryErrors -join "`n")" }
    throw $reason
}
finally { Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue }

# Cleanup cannot turn a successful publication into a misleading failed build.
foreach ($asset in $backups) {
    try { $null = Invoke-Gh api "$api/assets/$($asset.id)" --method DELETE } catch { Write-Warning "Published successfully, but could not remove previous asset $($asset.id): $_" }
}

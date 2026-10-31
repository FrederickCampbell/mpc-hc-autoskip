# Copyright (C) 2026 MPC-HC AutoSkip contributors. GPL-3.0-or-later.
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string]$InitialSha,
    [Parameter(Mandatory)] [string]$CandidateSha,
    [switch]$HadMerge,
    [string]$Branch = 'autoskip',
    [string]$RepoRoot = ([IO.Directory]::GetParent($PSScriptRoot).FullName)
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false
$head = @(& git -C $RepoRoot rev-parse --verify HEAD)
if ($LASTEXITCODE -ne 0 -or ($head -join '').Trim() -ne $CandidateSha) { throw 'The checkout no longer matches the tested candidate.' }
$remote = @(& git -C $RepoRoot ls-remote --exit-code origin "refs/heads/$Branch")
if ($LASTEXITCODE -ne 0) { throw 'Could not verify the current publication branch.' }
$remoteSha = (($remote -join "`n") -split '\s+')[0]
if ($remoteSha -ne $InitialSha) { throw 'The publication branch advanced during this build. A fresh run must test that revision before publishing.' }
if ($HadMerge) {
    & git -C $RepoRoot push origin "${CandidateSha}:refs/heads/$Branch"
    if ($LASTEXITCODE -ne 0) { throw 'The tested merge was not pushed; refusing to publish a stale release.' }
} elseif ($CandidateSha -ne $InitialSha) { throw 'A non-merge rebuild unexpectedly changed the candidate commit.' }

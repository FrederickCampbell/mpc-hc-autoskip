# Copyright (C) 2026 MPC-HC AutoSkip contributors. GPL-3.0-or-later.
[CmdletBinding()]
param(
    [string]$RepoRoot = ([IO.Directory]::GetParent($PSScriptRoot).FullName)
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

$generator = Join-Path $RepoRoot 'src\thirdparty\LAVFilters\genversion.cmd'
# Older upstream revisions still use LAV's bash version generator.
if (-not (Test-Path -LiteralPath $generator)) { return }

# Upstream may eventually fix this itself; only patch the unsafe PATH fallback.
if (-not (Select-String -LiteralPath $generator -SimpleMatch 'SET "PATH=' -Quiet)) { return }

$patch = Join-Path $PSScriptRoot 'patches\lav-version-command-length.patch'
git -C $RepoRoot apply --check --ignore-space-change $patch
if ($LASTEXITCODE -ne 0) {
    throw 'The upstream LAV version generator changed; review the command-length compatibility patch.'
}
git -C $RepoRoot apply --ignore-space-change $patch
if ($LASTEXITCODE -ne 0) { throw 'Could not apply the LAV version command-length compatibility patch.' }
Write-Host 'Applied LAV version command-length compatibility patch.'

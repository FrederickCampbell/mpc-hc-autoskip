# Copyright (C) 2026 MPC-HC AutoSkip contributors. GPL-3.0-or-later.
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string]$Generator
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

$gitExe = (Get-Command git.exe -ErrorAction Stop).Source
$gitDir = Split-Path $gitExe -Parent
$gitRoot = Split-Path $gitDir -Parent
$originalPath = $env:Path
$originalGit = $env:MPCHC_GIT
$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ('lav-version-' + [guid]::NewGuid())
$fixture = Join-Path $tempRoot 'LAV Filters'
$lavRoot = Join-Path $fixture 'src\thirdparty\LAVFilters'
$fixtureGenerator = Join-Path $lavRoot 'genversion.cmd'
$common = Join-Path $lavRoot 'src\common'
$header = Join-Path $common 'includes\version_rev.h'

function Invoke-FixtureGit {
    & $gitExe -C $fixture @args
    if ($LASTEXITCODE -ne 0) { throw "Fixture git failed: $args (exit $LASTEXITCODE)" }
}

function Invoke-Generator {
    param([string]$Expected)
    $output = @(& $env:ComSpec /d /c ('call "{0}"' -f $fixtureGenerator) 2>&1)
    if ($LASTEXITCODE -ne 0) { throw "Generator exited $LASTEXITCODE`n$($output -join "`n")" }
    if ((Get-Content -LiteralPath $header -Raw).Trim() -ne $Expected) {
        throw "Incorrect LAV version header`n$($output -join "`n")"
    }
    $output | ForEach-Object { Write-Host $_ }
}

function Get-LongPath {
    param([string]$Prefix)
    # Stay below cmd's inherited-variable limit, but make the original fallback
    # SET PATH line exceed 8191 characters after percent expansion.
    ($Prefix + ('C:\unused;' * 820)).Substring(0, 8090)
}

try {
    New-Item (Join-Path $common 'includes') -ItemType Directory -Force | Out-Null
    Copy-Item -LiteralPath $Generator -Destination $fixtureGenerator
    Set-Content -LiteralPath (Join-Path $fixture '.gitignore') -Value 'src/thirdparty/LAVFilters/src/common/includes/version_rev.h' -Encoding ascii
    & $gitExe init --quiet $fixture
    if ($LASTEXITCODE -ne 0) { throw 'Could not initialize fixture repository.' }
    Invoke-FixtureGit config user.name 'LAV version test'
    Invoke-FixtureGit config user.email 'lav-version-test@example.invalid'
    Invoke-FixtureGit add .
    Invoke-FixtureGit commit --quiet -m 'Tagged baseline'
    Invoke-FixtureGit tag -a 0.83 -m 'Tagged baseline'
    Invoke-FixtureGit commit --quiet --allow-empty -m 'One upstream change'
    Invoke-FixtureGit commit --quiet --allow-empty -m '[MPC-HC] Use our own ffmpeg clone repository.'

    Write-Host 'Reproducing the original overflow with an 8090-character PATH...'
    $env:Path = Get-LongPath "$gitDir;$env:SystemRoot\System32;"
    $env:MPCHC_GIT = $gitRoot
    $originalOutput = @(& $env:ComSpec /d /c ('call "{0}"' -f $fixtureGenerator) 2>&1)
    if ($LASTEXITCODE -eq 0 -or ($originalOutput -join "`n") -notmatch 'The input line is too long') {
        throw "The original command-length failure was not reproduced.`n$($originalOutput -join "`n")"
    }
    Write-Host 'Original overflow reproduced.'

    $env:Path = $originalPath
    & (Join-Path $PSScriptRoot 'Apply-LavVersionFix.ps1') -RepoRoot $fixture
    $patchedText = [IO.File]::ReadAllText($fixtureGenerator)
    & (Join-Path $PSScriptRoot 'Apply-LavVersionFix.ps1') -RepoRoot $fixture
    if ([IO.File]::ReadAllText($fixtureGenerator) -ne $patchedText) {
        throw 'Applying the compatibility patch twice changed the generator.'
    }

    Write-Host 'Checking patched Git on an 8090-character PATH...'
    $env:Path = Get-LongPath "$gitDir;$env:SystemRoot\System32;"
    # An invalid fallback must not override the executable already found on PATH.
    $env:MPCHC_GIT = 'C:\missing-git'
    Invoke-Generator '#define LAV_VERSION_BUILD 1'

    $timestamp = (Get-Item -LiteralPath $header).LastWriteTimeUtc
    Invoke-Generator '#define LAV_VERSION_BUILD 1'
    if ((Get-Item -LiteralPath $header).LastWriteTimeUtc -ne $timestamp) {
        throw 'Unchanged version header was rewritten.'
    }

    Write-Host 'Checking MPCHC_GIT fallback with Git absent from PATH...'
    $env:Path = Get-LongPath "$env:SystemRoot\System32;"
    $env:MPCHC_GIT = $gitRoot
    if (-not (Test-Path -LiteralPath (Join-Path $gitRoot 'cmd\git.exe'))) {
        throw "Git for Windows cmd executable was not found under $gitRoot"
    }
    Remove-Item -LiteralPath $header
    Invoke-Generator '#define LAV_VERSION_BUILD 1'

    Write-Host 'Checking the source-archive fallback outside a Git repository...'
    Remove-Item -LiteralPath (Join-Path $fixture '.git') -Recurse -Force
    Invoke-Generator '#define LAV_VERSION_BUILD 0'
    Write-Host 'LAV version regression checks passed.'
}
finally {
    $env:Path = $originalPath
    $env:MPCHC_GIT = $originalGit
    Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}

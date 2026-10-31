# Copyright (C) 2026 MPC-HC AutoSkip contributors. GPL-3.0-or-later.
[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false
$temp = Join-Path ([IO.Path]::GetTempPath()) ('autoskip-tests-' + [guid]::NewGuid())
$sourceRoot = [IO.Directory]::GetParent($PSScriptRoot).FullName
$settingsPath = 'src/mpc-hc/PPageAdvanced.cpp'
$baseText = "void InitSettings()`n{`n    addBoolItem(LOOP_FOLDER_NEXT_FILE, old_label, false, old_value, old_help);`n    addBoolItem(NEXT_FILE_SORT_BY_DATE, next_label, false, next_value, next_help);`n}`n"
$ownLines = "    addBoolItem(AUTOSKIP_CHAPTERS, L`"AutoSkipChapters`", true, s.bAutoSkipChapters, L`"help`" );`n    addCStringItem(AUTOSKIP_CHAPTER_PATTERNS, L`"AutoSkipChapterPatterns`", L`"opening;ending`", s.sAutoSkipChapterPatterns, L`"help`" );`n"

function Invoke-TestGit {
    param([Parameter(ValueFromRemainingArguments)] [string[]]$Arguments)
    $text = @(& git @Arguments 2>&1)
    if ($LASTEXITCODE -ne 0) { throw "git $Arguments failed: $($text -join "`n")" }
    ($text | ForEach-Object { "$_" }) -join "`n"
}
function Assert-True { param([bool]$Condition, [string]$Message); if (-not $Condition) { throw $Message } }
function Assert-Throws {
    param([scriptblock]$Action, [string]$Pattern)
    $failed = $false
    try { & $Action } catch { $failed = $true; if ("$_" -notmatch $Pattern) { throw } }
    if (-not $failed) { throw "Expected failure matching: $Pattern" }
}
function Write-Text { param([string]$Path, [string]$Text); [IO.File]::WriteAllText($Path, $Text, [Text.UTF8Encoding]::new($false)) }
function New-Fixture {
    param([switch]$ExtraForkChange, [switch]$OtherConflict)
    $dir = Join-Path $temp ([guid]::NewGuid().ToString())
    $seed = Join-Path $dir 'seed'
    $upstream = Join-Path $dir 'upstream.git'
    $fork = Join-Path $dir 'fork'
    New-Item (Join-Path $seed 'src/mpc-hc') -ItemType Directory -Force | Out-Null
    $null = Invoke-TestGit init --quiet --initial-branch=develop $seed
    $null = Invoke-TestGit init --quiet --bare $upstream
    $null = Invoke-TestGit -C $seed config user.name 'AutoSkip tests'
    $null = Invoke-TestGit -C $seed config user.email 'tests@example.invalid'
    Write-Text (Join-Path $seed $settingsPath) $baseText
    Write-Text (Join-Path $seed 'other.txt') "base`n"
    $null = Invoke-TestGit -C $seed add .
    $null = Invoke-TestGit -C $seed commit --quiet -m baseline
    $null = Invoke-TestGit -C $seed remote add origin $upstream
    $null = Invoke-TestGit -C $seed push --quiet origin develop
    $null = Invoke-TestGit clone --quiet --branch develop $upstream $fork
    $null = Invoke-TestGit -C $fork config user.name 'AutoSkip tests'
    $null = Invoke-TestGit -C $fork config user.email 'tests@example.invalid'
    $null = Invoke-TestGit -C $fork checkout --quiet -b autoskip
    $ours = $baseText.Replace('    addBoolItem(NEXT_FILE_SORT_BY_DATE', $ownLines + '    addBoolItem(NEXT_FILE_SORT_BY_DATE')
    if ($ExtraForkChange) { $ours += "// Additional fork customization must survive.`n" }
    Write-Text (Join-Path $fork $settingsPath) $ours
    if ($OtherConflict) { Write-Text (Join-Path $fork 'other.txt') "fork`n" }
    $null = Invoke-TestGit -C $fork add .
    $null = Invoke-TestGit -C $fork commit --quiet -m autoskip
    $theirs = $baseText.Replace('old_label', 'upstream_label').Replace('    addBoolItem(NEXT_FILE_SORT_BY_DATE', "    addBoolItem(UPSTREAM_NEW_SETTING, new_label, false, new_value, new_help);`n    addBoolItem(NEXT_FILE_SORT_BY_DATE")
    Write-Text (Join-Path $seed $settingsPath) $theirs
    if ($OtherConflict) { Write-Text (Join-Path $seed 'other.txt') "upstream`n" }
    $null = Invoke-TestGit -C $seed add .
    $null = Invoke-TestGit -C $seed commit --quiet -m upstream
    $null = Invoke-TestGit -C $seed push --quiet origin develop
    [pscustomobject]@{ Root = $fork; Upstream = $upstream; Output = (Join-Path $dir 'output.txt') }
}
function Sync-Fixture {
    param($Fixture, [switch]$ForceBuild, [switch]$EnsureReleaseCurrent)
    & (Join-Path $PSScriptRoot 'Sync-Upstream.ps1') -RepoRoot $Fixture.Root -UpstreamUrl $Fixture.Upstream -ForceBuild:$ForceBuild -EnsureReleaseCurrent:$EnsureReleaseCurrent -OutputPath $Fixture.Output
}
function Read-Outputs {
    param($Fixture)
    $result = @{}
    foreach ($line in (Get-Content -LiteralPath $Fixture.Output)) { $pair = $line -split '=', 2; $result[$pair[0]] = $pair[1] }
    $result
}

try {
    New-Item $temp -ItemType Directory -Force | Out-Null
    Write-Host 'Testing conflict recovery with an upstream anchor change...'
    $case = New-Fixture
    $initial = Invoke-TestGit -C $case.Root rev-parse HEAD
    $null = Invoke-TestGit -C $case.Root push --quiet origin HEAD:refs/heads/autoskip
    Sync-Fixture $case
    $merged = [IO.File]::ReadAllText((Join-Path $case.Root $settingsPath))
    Assert-True ($merged.Contains('upstream_label') -and $merged.Contains('UPSTREAM_NEW_SETTING') -and $merged.Contains('AUTOSKIP_CHAPTERS') -and $merged.Contains('AUTOSKIP_CHAPTER_PATTERNS')) 'Conflict resolution lost an upstream or AutoSkip setting.'
    $head = Invoke-TestGit -C $case.Root rev-parse HEAD
    & (Join-Path $PSScriptRoot 'Push-TestedCandidate.ps1') -RepoRoot $case.Root -InitialSha $initial -CandidateSha $head -HadMerge
    Sync-Fixture $case
    Assert-True ((Read-Outputs $case).build_needed -eq 'false') 'Scheduled no-op rebuilt unnecessarily.'
    Sync-Fixture $case -ForceBuild
    Assert-True ((Read-Outputs $case).build_needed -eq 'true' -and (Read-Outputs $case).had_merge -eq 'false') 'Explicit rebuild was lost.'
    Assert-True ((Invoke-TestGit -C $case.Root rev-parse HEAD) -eq $head) 'Repeated sync created another commit.'
    Write-Host 'Testing retry after publication failed despite an already-pushed merge...'
    Sync-Fixture $case -EnsureReleaseCurrent
    Assert-True ((Read-Outputs $case).build_needed -eq 'true') 'Missing release was not retried.'
    $null = Invoke-TestGit -C $case.Upstream update-ref refs/tags/autoskip-latest $head
    Sync-Fixture $case -EnsureReleaseCurrent
    Assert-True ((Read-Outputs $case).build_needed -eq 'false') 'Current release triggered a redundant scheduled build.'
    $null = Invoke-TestGit -C $case.Upstream update-ref refs/heads/autoskip $initial
    Assert-Throws { & (Join-Path $PSScriptRoot 'Push-TestedCandidate.ps1') -RepoRoot $case.Root -InitialSha $head -CandidateSha $head } 'publication branch advanced'
    Write-Host 'Testing failed fetch does not use a stale upstream ref...'
    Assert-Throws { & (Join-Path $PSScriptRoot 'Sync-Upstream.ps1') -RepoRoot $case.Root -UpstreamUrl (Join-Path $temp 'missing.git') -OutputPath $case.Output } 'fetch.*failed'
    Assert-True ((Invoke-TestGit -C $case.Root rev-parse HEAD) -eq $head -and (Read-Outputs $case).build_needed -eq 'false') 'Failed fetch changed the candidate.'

    foreach ($mode in @('ExtraForkChange', 'OtherConflict')) {
        Write-Host "Testing rollback for $mode..."
        $options = @{}; $options[$mode] = $true
        $case = New-Fixture @options
        $head = Invoke-TestGit -C $case.Root rev-parse HEAD
        Assert-Throws { Sync-Fixture $case } 'manual resolution|Unexpected upstream merge'
        Assert-True ((Invoke-TestGit -C $case.Root rev-parse HEAD) -eq $head) 'Failed sync advanced HEAD.'
        Assert-True (-not (Invoke-TestGit -C $case.Root status --porcelain)) 'Failed sync left a dirty/conflicted tree.'
        Assert-True ((Read-Outputs $case).build_needed -eq 'false') 'Failed sync allowed a build.'
    }
    Write-Host 'Testing PATH refresh preserves order and removes duplicates...'
    . (Join-Path $PSScriptRoot 'Build-Path.ps1')
    Assert-True ((Get-UniqueBuildPath @('C:\Tools;C:\Windows;C:\TOOLS\', 'C:\Python;C:\Windows')) -eq 'C:\Tools;C:\Windows;C:\Python') 'PATH normalization changed lookup order or kept duplicate entries.'

    Write-Host 'Testing package completeness and x64 architecture checks...'
    $stage = Join-Path $temp 'package'
    $binaries = @('mpc-hc64.exe', 'mpciconlib.dll', 'D3DCompiler_47.dll', 'D3DX9_43.dll', 'LAVFilters64/LAVAudio.ax', 'LAVFilters64/LAVSplitter.ax', 'LAVFilters64/LAVVideo.ax', 'MPCVR/MpcVideoRenderer64.ax')
    [byte[]]$pe = New-Object byte[] 128
    $pe[0] = 0x4d; $pe[1] = 0x5a; $pe[0x3c] = 0x40; $pe[0x40] = 0x50; $pe[0x41] = 0x45; $pe[0x44] = 0x64; $pe[0x45] = 0x86
    foreach ($file in $binaries) {
        $path = Join-Path $stage $file
        New-Item (Split-Path $path -Parent) -ItemType Directory -Force | Out-Null
        [IO.File]::WriteAllBytes($path, $pe)
    }
    foreach ($file in @('COPYING.txt', 'AUTOSKIP-BUILD.txt', 'Shaders/test.hlsl', 'Shaders11/test.hlsl', 'Lang/mpcresources.en.dll')) {
        $path = Join-Path $stage $file
        New-Item (Split-Path $path -Parent) -ItemType Directory -Force | Out-Null
        Write-Text $path 'test resource'
    }
    & (Join-Path $PSScriptRoot 'Verify-Package.ps1') -Path $stage
    Write-Host 'Testing complete ZIP creation, archive entries, and the download checksum...'
    $packageRepo = Join-Path $temp 'package repo'
    New-Item (Join-Path $packageRepo 'bin') -ItemType Directory -Force | Out-Null
    Copy-Item $stage (Join-Path $packageRepo 'bin/mpc-hc_x64') -Recurse
    Copy-Item (Join-Path $stage 'COPYING.txt') $packageRepo
    foreach ($kind in @('dx9', 'dx11')) {
        $shaderDir = Join-Path $packageRepo "src/mpc-hc/res/shaders/$kind"
        New-Item $shaderDir -ItemType Directory -Force | Out-Null
        Write-Text (Join-Path $shaderDir 'test.hlsl') 'test shader'
    }
    & (Join-Path $PSScriptRoot 'Package-X64.ps1') -RepoRoot $packageRepo -UpstreamSha ('a' * 40) -CandidateSha ('b' * 40) -OutputPath (Join-Path $temp 'package-output.txt')
    $zip = Join-Path $packageRepo 'MPC-HC-AutoSkip-x64.zip'
    $digest = (Get-FileHash -LiteralPath $zip).Hash.ToLowerInvariant()
    Assert-True ((Get-Content -LiteralPath "$zip.sha256" -Raw).StartsWith($digest)) 'Package checksum does not match the actual ZIP.'
    $pe[0x44] = 0x4c; $pe[0x45] = 0x01
    [IO.File]::WriteAllBytes((Join-Path $stage 'mpc-hc64.exe'), $pe)
    Assert-Throws { & (Join-Path $PSScriptRoot 'Verify-Package.ps1') -Path $stage } 'x64 PE'
    Remove-Item (Join-Path $stage 'LAVFilters64/LAVVideo.ax')
    Assert-Throws { & (Join-Path $PSScriptRoot 'Verify-Package.ps1') -Path $stage } 'LAVVideo.ax.*missing'

    Write-Host 'Testing verification catches loss of the timer hook, even when its comment survives...'
    $copy = Join-Path $temp 'sources'
    foreach ($file in @('MainFrm.cpp', 'MainFrm.h', 'AppSettings.h', 'AppSettings.cpp', 'PPageAdvanced.cpp', 'PPageAdvanced.h', 'SettingsDefines.h')) {
        $target = Join-Path $copy "src/mpc-hc/$file"
        New-Item (Split-Path $target -Parent) -ItemType Directory -Force | Out-Null
        Copy-Item (Join-Path $sourceRoot "src/mpc-hc/$file") $target
    }
    & (Join-Path $PSScriptRoot 'Verify-AutoSkipPatch.ps1') -RepoRoot $copy
    $main = Join-Path $copy 'src/mpc-hc/MainFrm.cpp'
    Write-Text $main ([IO.File]::ReadAllText($main).Replace('AutoSkipChapterIfNeeded();', '/* removed timer hook */'))
    Assert-Throws { & (Join-Path $PSScriptRoot 'Verify-AutoSkipPatch.ps1') -RepoRoot $copy } 'MainFrm.cpp.*found 0'
    Assert-Throws { & (Join-Path $PSScriptRoot 'Apply-AutoSkipPatch.ps1') -RepoRoot $copy } 'MainFrm.cpp.*found 0'
    Write-Host 'Automation regression checks passed.'
}
finally { Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue }

# Copyright (C) 2026 MPC-HC AutoSkip contributors. GPL-3.0-or-later.
[CmdletBinding()]
param(
    [string]$RepoRoot = ([IO.Directory]::GetParent($PSScriptRoot).FullName),
    [Parameter(Mandatory)] [string]$UpstreamSha,
    [Parameter(Mandatory)] [string]$CandidateSha,
    [string]$RunUrl = '',
    [string]$OutputPath = $env:GITHUB_OUTPUT
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$version = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'VERSION')).Trim()
$tempRoot = if ($env:RUNNER_TEMP) { $env:RUNNER_TEMP } else { [IO.Path]::GetTempPath() }
$stage = Join-Path $tempRoot ('mpc-hc-package-' + [guid]::NewGuid())
$zip = Join-Path $RepoRoot 'MPC-HC-AutoSkip-x64.zip'
try {
    New-Item $stage -ItemType Directory | Out-Null
    Copy-Item (Join-Path $RepoRoot 'bin/mpc-hc_x64/*') $stage -Recurse -Force
    $buildOnly = @('.pdb', '.lib', '.exp', '.ilk', '.iobj', '.ipdb')
    Get-ChildItem $stage -Recurse -File | Where-Object { $_.Extension.ToLowerInvariant() -in $buildOnly } | Remove-Item -Force
    foreach ($shader in @{ Shaders = 'dx9'; Shaders11 = 'dx11' }.GetEnumerator()) {
        $destination = Join-Path $stage $shader.Key
        New-Item $destination -ItemType Directory -Force | Out-Null
        Copy-Item (Join-Path $RepoRoot "src/mpc-hc/res/shaders/$($shader.Value)/*.hlsl") $destination -Force
    }
    Copy-Item (Join-Path $RepoRoot 'COPYING.txt') $stage -Force
    @"
MPC-HC AutoSkip $version
Upstream: clsid2/mpc-hc@$UpstreamSha
Fork commit: $CandidateSha
Build: $RunUrl

AutoSkip UI: Options > Advanced > Playback
  AutoSkipChapters = True
  AutoSkipChapterPatterns = opening;ending;yokoku;preview
"@ | Set-Content (Join-Path $stage 'AUTOSKIP-BUILD.txt') -Encoding utf8
    & (Join-Path $PSScriptRoot 'Verify-Package.ps1') -Path $stage
    Compress-Archive -Path (Join-Path $stage '*') -DestinationPath $zip -CompressionLevel Optimal -Force
    $archive = [IO.Compression.ZipFile]::OpenRead($zip)
    try {
        foreach ($entry in @('mpc-hc64.exe', 'LAVFilters64/LAVAudio.ax', 'LAVFilters64/LAVSplitter.ax', 'LAVFilters64/LAVVideo.ax', 'MPCVR/MpcVideoRenderer64.ax', 'AUTOSKIP-BUILD.txt')) {
            if (-not $archive.GetEntry($entry)) { throw "ZIP is missing required entry: $entry" }
        }
    }
    finally { $archive.Dispose() }
    $checksum = "$zip.sha256"
    $digest = (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash.ToLowerInvariant()
    "$digest  $([IO.Path]::GetFileName($zip))" | Set-Content -LiteralPath $checksum -Encoding ascii
    if ($OutputPath) {
        @("zip=$zip", "checksum=$checksum", "version=$version") | Out-File $OutputPath -Append -Encoding utf8
    }
    Write-Host "Validated package: $zip (sha256:$digest)"
}
finally { Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue }

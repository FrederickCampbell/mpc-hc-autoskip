# Copyright (C) 2026 MPC-HC AutoSkip contributors. GPL-3.0-or-later.
[CmdletBinding()]
param([Parameter(Mandatory)] [string]$Path)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$binaries = @(
    'mpc-hc64.exe', 'mpciconlib.dll', 'D3DCompiler_47.dll', 'D3DX9_43.dll',
    'LAVFilters64/LAVAudio.ax', 'LAVFilters64/LAVSplitter.ax', 'LAVFilters64/LAVVideo.ax',
    'MPCVR/MpcVideoRenderer64.ax'
)
foreach ($relative in ($binaries + @('COPYING.txt', 'AUTOSKIP-BUILD.txt'))) {
    $file = Join-Path $Path $relative
    if (-not (Test-Path -LiteralPath $file -PathType Leaf) -or (Get-Item -LiteralPath $file).Length -eq 0) {
        throw "Release package is incomplete: $relative is missing or empty."
    }
}
foreach ($relative in $binaries) {
    $stream = [IO.File]::OpenRead((Join-Path $Path $relative))
    $reader = [IO.BinaryReader]::new($stream)
    try {
        if ($stream.Length -lt 64 -or $reader.ReadUInt16() -ne 0x5A4D) { throw "Invalid Windows binary: $relative" }
        $stream.Position = 0x3c
        $offset = $reader.ReadUInt32()
        if ($offset -gt $stream.Length - 6) { throw "Invalid PE header: $relative" }
        $stream.Position = $offset
        if ($reader.ReadUInt32() -ne 0x4550 -or $reader.ReadUInt16() -ne 0x8664) { throw "Expected an x64 PE binary: $relative" }
    }
    finally { $reader.Dispose() }
}
foreach ($directory in @('Shaders', 'Shaders11', 'Lang')) {
    $extension = if ($directory -eq 'Lang') { '*.dll' } else { '*.hlsl' }
    if (@(Get-ChildItem (Join-Path $Path $directory) -Filter $extension -File -ErrorAction SilentlyContinue).Count -eq 0) {
        throw "Release package has no $directory resources."
    }
}
Write-Host 'Release package contains the player, x64 codecs/renderers, translations, shaders, and license.'

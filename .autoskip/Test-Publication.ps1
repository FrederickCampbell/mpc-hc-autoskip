# Copyright (C) 2026 MPC-HC AutoSkip contributors. GPL-3.0-or-later.
[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$temp = Join-Path ([IO.Path]::GetTempPath()) ('publish-tests-' + [guid]::NewGuid())
$candidate = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'
$oldTag = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
$zipName = 'MPC-HC-AutoSkip-x64.zip'

function Fail-Mock {
    param([string]$Point)
    $s = $global:AutoSkipPublicationTest
    if ($s.Fail -eq $Point -and $s.Armed) { $s.Armed = $false; $global:LASTEXITCODE = 1; return $true }
    $false
}
function Get-Flag {
    param([string[]]$Arguments, [string]$Flag, [string]$Default = '')
    $i = [Array]::IndexOf($Arguments, $Flag)
    if ($i -lt 0) { return $Default }
    $Arguments[$i + 1]
}
function Release-Json {
    $s = $global:AutoSkipPublicationTest
    @{ id = 99; name = $s.Name; body = $s.Body; assets = @($s.Assets.Values); draft = $s.Draft } | ConvertTo-Json -Depth 8 -Compress
}
function git {
    param([Parameter(ValueFromRemainingArguments)] [string[]]$Arguments)
    $global:LASTEXITCODE = 0
    $s = $global:AutoSkipPublicationTest
    if ($Arguments[0] -eq '-C') { $Arguments = $Arguments[2..($Arguments.Count - 1)] }
    if ($Arguments[0] -eq 'ls-remote') {
        if ($Arguments[-1] -eq 'refs/heads/autoskip') {
            $s.BranchReads++
            if ($s.Fail -eq 'stale' -and $s.BranchReads -gt 1) { return "cccccccccccccccccccccccccccccccccccccccc`trefs/heads/autoskip" }
            return "$($s.Candidate)`trefs/heads/autoskip"
        }
        if ($s.Tag) { return "$($s.Tag)`trefs/tags/autoskip-latest" }
        return
    }
    if ($Arguments[0] -eq 'push') {
        $s.Tag = ($Arguments[-1] -split ':', 2)[0]
        # Simulate a server accepting a write but losing the acknowledgement.
        if (Fail-Mock tag) { return 'simulated tag push failure' }
        return
    }
    throw "Unexpected mock git command: $Arguments"
}
function gh {
    param([Parameter(ValueFromRemainingArguments)] [string[]]$Arguments)
    $global:LASTEXITCODE = 0
    $s = $global:AutoSkipPublicationTest
    if ($Arguments[0] -eq 'release' -and $Arguments[1] -eq 'upload') {
        if (Fail-Mock upload) { return 'simulated upload failure' }
        $path = $Arguments[3]
        $s.NextId++
        $s.Assets[$s.NextId] = [pscustomobject]@{ id = $s.NextId; name = [IO.Path]::GetFileName($path); size = (Get-Item $path).Length; digest = ('sha256:' + (Get-FileHash $path).Hash.ToLowerInvariant()) }
        if ($s.Fail -eq 'digest') { $s.Assets[$s.NextId].digest = 'incorrect digest' }
        return
    }
    if ($Arguments[0] -eq 'release' -and $Arguments[1] -eq 'edit') {
        $s.Body = [IO.File]::ReadAllText((Get-Flag $Arguments '--notes-file'))
        $s.Name = Get-Flag $Arguments '--title'
        $s.Draft = $false
        if (Fail-Mock metadata) { return 'simulated metadata failure' }
        return
    }
    if ($Arguments[0] -ne 'api') { throw "Unexpected mock gh command: $Arguments" }
    $route = $Arguments[1]
    $method = Get-Flag $Arguments '--method' GET
    if ($route -match '/assets/(\d+)$') {
        $id = [int]$Matches[1]
        if ($method -eq 'DELETE') { $s.Assets.Remove($id); return }
        $name = ($Arguments | Where-Object { $_.StartsWith('name=') }) -replace '^name=', ''
        if ($name -eq 'MPC-HC-AutoSkip-x64.zip' -and $id -gt 2 -and (Fail-Mock rename)) { return 'simulated asset rename failure' }
        $s.Assets[$id].name = "$name"
        return
    }
    if ($route.EndsWith('/tags/autoskip-latest')) {
        if (-not $s.Exists) { $global:LASTEXITCODE = 1; return 'gh: Not Found (HTTP 404)' }
        return Release-Json
    }
    if ($method -eq 'POST') { $s.Exists = $true; $s.Draft = $true; return Release-Json }
    if ($method -eq 'DELETE') { $s.Exists = $false; return }
    if ($method -eq 'PATCH') {
        $s.Name = (($Arguments | Where-Object { $_.StartsWith('name=') }) -replace '^name=', '') -join ''
        $s.Body = (($Arguments | Where-Object { $_.StartsWith('body=') }) -replace '^body=', '') -join ''
        return
    }
    throw "Unexpected mock API: $Arguments"
}

try {
    New-Item $temp -ItemType Directory | Out-Null
    $zip = Join-Path $temp $zipName
    $checksum = "$zip.sha256"
    [IO.File]::WriteAllText($zip, 'new zip bytes')
    [IO.File]::WriteAllText($checksum, 'new checksum')
    foreach ($scenario in @('success', 'upload', 'digest', 'stale', 'rename', 'tag', 'metadata', 'missingRelease')) {
        Write-Host "Testing rolling release: $scenario"
        $missing = $scenario -eq 'missingRelease'
        $global:AutoSkipPublicationTest = @{
            Candidate = $candidate; Tag = $(if ($missing) { '' } else { $oldTag });
            Name = 'old title'; Body = 'old notes'; Draft = $false; Exists = -not $missing;
            NextId = 10; Fail = $scenario; Armed = $true; Assets = @{}; BranchReads = 0
        }
        $s = $global:AutoSkipPublicationTest
        if (-not $missing) {
            $s.Assets[1] = [pscustomobject]@{ id = 1; name = $zipName; size = 3; digest = 'old zip digest' }
            $s.Assets[2] = [pscustomobject]@{ id = 2; name = "$zipName.sha256"; size = 4; digest = 'old checksum digest' }
        }
        $failed = $false
        try {
            & (Join-Path $PSScriptRoot 'Publish-Release.ps1') -Repository 'test/repo' -CandidateSha $candidate -UpstreamSha $candidate -Zip $zip -Checksum $checksum -Version test
        } catch { $failed = $true; if ("$_" -notmatch 'simulated|digest verification|refusing stale') { throw } }
        if ($scenario -in @('success', 'missingRelease')) {
            if ($failed -or $s.Tag -ne $candidate -or $s.Assets.Count -ne 2 -or $s.Draft) { throw 'Successful publication did not commit the new release.' }
        } else {
            if (-not $failed -or $s.Tag -ne $oldTag -or $s.Assets[1].name -ne $zipName -or $s.Assets[2].name -ne "$zipName.sha256" -or $s.Body -ne 'old notes') {
                throw "Failed $scenario publication did not restore the previous release."
            }
        }
    }
    Write-Host 'Publication rollback checks passed.'
}
finally {
    Remove-Variable AutoSkipPublicationTest -Scope Global -ErrorAction SilentlyContinue
    Remove-Item $temp -Recurse -Force -ErrorAction SilentlyContinue
}

# Copyright (C) 2026 MPC-HC AutoSkip contributors. GPL-3.0-or-later.
[CmdletBinding()]
param([string]$UpstreamSha, [string]$CandidateSha)
$ErrorActionPreference = 'Continue'
$root = [IO.Directory]::GetParent($PSScriptRoot).FullName
$lines = @('## AutoSkip workflow failed', '', "Upstream: $UpstreamSha", "Candidate: $CandidateSha", '', 'The failure is recorded in the step log above.')
$logs = @(Get-ChildItem (Join-Path $root 'bin/logs') -Filter '*errors*' -File -ErrorAction SilentlyContinue)
$combined = Join-Path $root 'bin/logs/autoskip-build.log'
if (Test-Path -LiteralPath $combined) { $logs = @((Get-Item $combined)) }
$first = $logs | Select-String -Pattern ':\s*(?:fatal\s+)?error\s+[A-Z]+\d+|The input line is too long' | Select-Object -First 1
if ($first) {
    $message = $first.Line.Trim()
    $lines += @('', 'First build error:', '```text', $message, '```')
    Write-Host ('::error title=First build error::' + $message.Replace('%', '%25').Replace("`r", '%0D').Replace("`n", '%0A'))
}
if ($env:GITHUB_STEP_SUMMARY) { $lines | Out-File $env:GITHUB_STEP_SUMMARY -Encoding utf8 -Append }

[CmdletBinding()]
param(
    [switch]$NoWait
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

function Get-RepoSlug {
    $url = (git remote get-url origin).Trim()
    if ($url -match 'github\.com[/:](?<slug>[^/]+/[^/]+?)(?:\.git)?$') {
        return $Matches.slug
    }
    throw "Could not derive GitHub repository from origin: $url"
}

$repo = Get-RepoSlug
$previousRunId = gh run list --repo $repo --workflow 'AutoSync + Build AutoSkip' --event workflow_dispatch --limit 1 --json databaseId --jq '.[0].databaseId' 2>$null

Write-Host "Triggering upstream sync/build for $repo..." -ForegroundColor Cyan
gh workflow run 'AutoSync + Build AutoSkip' --repo $repo --ref autoskip
if ($LASTEXITCODE -ne 0) { throw 'Could not trigger the GitHub Actions workflow.' }

if ($NoWait) {
    Write-Host 'Triggered. Use the VS Code Watch Build task or GitHub Actions page to follow it.' -ForegroundColor Green
    exit 0
}

$runId = $null
for ($i = 0; $i -lt 45 -and -not $runId; $i++) {
    Start-Sleep -Seconds 2
    $candidate = gh run list --repo $repo --workflow 'AutoSync + Build AutoSkip' --event workflow_dispatch --limit 1 --json databaseId --jq '.[0].databaseId' 2>$null
    if ($candidate -and $candidate -ne $previousRunId) { $runId = $candidate }
}
if (-not $runId) { throw 'Could not find the newly triggered GitHub Actions run.' }

gh run watch $runId --repo $repo --exit-status
if ($LASTEXITCODE -ne 0) { throw "Build failed. Open the run with: gh run view $runId --repo $repo --web" }

Write-Host 'AutoSync/build completed successfully.' -ForegroundColor Green

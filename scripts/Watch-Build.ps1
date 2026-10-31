[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

$url = @(git remote get-url origin)
if ($LASTEXITCODE -ne 0) { throw 'Could not read the repository origin.' }
$url = ($url -join '').Trim()
if ($url -notmatch 'github\.com[/:](?<slug>[^/]+/[^/]+?)(?:\.git)?$') {
    throw "Could not derive GitHub repository from origin: $url"
}
$repo = $Matches.slug
$runId = gh run list --repo $repo --workflow 'AutoSync + Build AutoSkip' --branch autoskip --limit 1 --json databaseId --jq '.[0].databaseId'
if ($LASTEXITCODE -ne 0) { throw 'Could not inspect workflow runs.' }
if (-not $runId) { throw 'No AutoSkip workflow run found.' }
gh run watch $runId --repo $repo --exit-status
if ($LASTEXITCODE -ne 0) { throw "Build failed or the watch connection was interrupted; run ID: $runId" }

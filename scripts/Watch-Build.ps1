[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

$url = (git remote get-url origin).Trim()
if ($url -notmatch 'github\.com[/:](?<slug>[^/]+/[^/]+?)(?:\.git)?$') {
    throw "Could not derive GitHub repository from origin: $url"
}
$repo = $Matches.slug
$runId = gh run list --repo $repo --workflow 'AutoSync + Build AutoSkip' --limit 1 --json databaseId --jq '.[0].databaseId'
if (-not $runId) { throw 'No AutoSkip workflow run found.' }
gh run watch $runId --repo $repo --exit-status

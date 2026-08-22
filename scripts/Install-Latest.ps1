[CmdletBinding()]
param(
    [string]$Repo,
    [string]$InstallDir = (Join-Path $env:LOCALAPPDATA 'Programs\MPC-HC-AutoSkip'),
    [switch]$NoLaunch
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

function Get-RepoSlug {
    if ($Repo) { return $Repo }
    $url = (git remote get-url origin).Trim()
    if ($url -match 'github\.com[/:](?<slug>[^/]+/[^/]+?)(?:\.git)?$') {
        return $Matches.slug
    }
    throw 'Specify -Repo owner/repo or run this script from the cloned AutoSkip repository.'
}

$slug = Get-RepoSlug
$temp = Join-Path $env:TEMP ("mpc-hc-autoskip-" + [guid]::NewGuid().ToString('N'))
$download = Join-Path $temp 'download'
$extract = Join-Path $temp 'extract'
New-Item $download, $extract -ItemType Directory -Force | Out-Null

try {
    Write-Host "Downloading latest successful AutoSkip release from $slug..." -ForegroundColor Cyan
    gh release download --repo $slug --pattern 'MPC-HC-AutoSkip-x64-*.zip' --dir $download --clobber
    if ($LASTEXITCODE -ne 0) { throw 'No successful AutoSkip release is available yet.' }

    $zip = Get-ChildItem $download -Filter '*.zip' -File | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if (-not $zip) { throw 'GitHub CLI completed but no release ZIP was downloaded.' }

    Expand-Archive -LiteralPath $zip.FullName -DestinationPath $extract -Force

    $running = Get-Process -Name 'mpc-hc64','mpc-hc' -ErrorAction SilentlyContinue | Where-Object {
        try { $_.Path -and $_.Path.StartsWith($InstallDir, [StringComparison]::OrdinalIgnoreCase) } catch { $false }
    }
    foreach ($proc in $running) {
        Write-Host "Closing running MPC-HC AutoSkip process $($proc.Id)..."
        $null = $proc.CloseMainWindow()
        if (-not $proc.WaitForExit(3000)) { $proc.Kill() }
    }

    New-Item $InstallDir -ItemType Directory -Force | Out-Null

    # Overlay rather than deleting the directory so portable mpc-hc.ini and any
    # user-added files survive upgrades.
    Get-ChildItem $extract -Force | ForEach-Object {
        Copy-Item $_.FullName -Destination $InstallDir -Recurse -Force
    }

    $exe = Get-ChildItem $InstallDir -Filter 'mpc-hc*.exe' -File | Sort-Object Name | Select-Object -First 1
    if (-not $exe) { throw "Installed release does not contain an MPC-HC executable: $InstallDir" }

    Write-Host "Installed: $($exe.FullName)" -ForegroundColor Green
    Write-Host 'AutoSkip settings: Options > Advanced > Playback' -ForegroundColor Green

    if (-not $NoLaunch) {
        Start-Process -FilePath $exe.FullName
    }
}
finally {
    Remove-Item $temp -Recurse -Force -ErrorAction SilentlyContinue
}

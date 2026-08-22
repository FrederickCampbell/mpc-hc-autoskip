[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

function Assert-LastExitCode {
    param([Parameter(Mandatory)] [string]$Message)
    if ($LASTEXITCODE -ne 0) { throw "$Message (exit $LASTEXITCODE)" }
}

Write-Host 'Preparing MPC-HC x64 build environment...' -ForegroundColor Cyan

$vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
if (-not (Test-Path -LiteralPath $vswhere)) {
    throw 'vswhere.exe is missing. Install Visual Studio C++ build tools with ATL/MFC.'
}
$vs = (& $vswhere -latest -requires Microsoft.Component.MSBuild Microsoft.VisualStudio.Component.VC.ATLMFC Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath | Select-Object -First 1)
if (-not $vs) {
    throw 'Visual Studio C++ ATL/MFC build tools are missing.'
}
Write-Host "Visual Studio: $vs"

# MPC-HC defaults to the legacy 8.1 SDK when MPCHC_WINSDK_VER is unset.
# Hosted Windows runners carry current Windows 10/11 SDKs instead, so select
# the newest installed x64 SDK explicitly.
$sdkRoot = "${env:ProgramFiles(x86)}\Windows Kits\10\Lib"
if (-not (Test-Path -LiteralPath $sdkRoot)) {
    throw "Windows 10/11 SDK library root is missing: $sdkRoot"
}
$sdk = Get-ChildItem -LiteralPath $sdkRoot -Directory | Where-Object {
    $_.Name -match '^\d+\.\d+\.\d+\.\d+$' -and (Test-Path (Join-Path $_.FullName 'um\x64'))
} | Sort-Object { [version]$_.Name } -Descending | Select-Object -First 1
if (-not $sdk) {
    throw 'No usable x64 Windows SDK was found.'
}
$sdkVersion = $sdk.Name
Write-Host "Windows SDK:   $sdkVersion"

$msys = @('C:\msys64', 'C:\tools\msys64') | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
if (-not $msys) {
    if (-not (Get-Command choco -ErrorAction SilentlyContinue)) {
        throw 'MSYS2 is missing and Chocolatey is unavailable.'
    }
    choco install msys2 -y --no-progress
    Assert-LastExitCode 'Chocolatey could not install MSYS2'
    $msys = @('C:\msys64', 'C:\tools\msys64') | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
}
if (-not $msys) { throw 'Unable to locate MSYS2 after installation.' }
Write-Host "MSYS2:        $msys"

$bash = Join-Path $msys 'usr\bin\bash.exe'
if (-not (Test-Path -LiteralPath $bash)) { throw "MSYS2 bash is missing: $bash" }
& $bash -lc 'pacman -Sy --needed --noconfirm make pkgconf diffutils mingw-w64-x86_64-gcc'
Assert-LastExitCode 'MSYS2 package setup failed'

# Current LAV/FFmpeg build scripts explicitly use NASM for x86 assembly.
if (-not (Get-Command nasm.exe -ErrorAction SilentlyContinue)) {
    if (-not (Get-Command choco -ErrorAction SilentlyContinue)) {
        throw 'NASM is missing and Chocolatey is unavailable.'
    }
    choco install nasm -y --no-progress
    Assert-LastExitCode 'Chocolatey could not install NASM'
}
if (-not (Get-Command nasm.exe -ErrorAction SilentlyContinue)) {
    throw 'NASM installation completed but nasm.exe is still unavailable on PATH.'
}
Write-Host "NASM:         $((Get-Command nasm.exe).Source)"

# Translation resources use polib. Python is preinstalled on GitHub's Windows
# runners; this also works on a properly prepared local developer machine.
if (-not (Get-Command python.exe -ErrorAction SilentlyContinue)) {
    throw 'Python 3 is required for MPC-HC translation resources.'
}
python -m pip install --disable-pip-version-check --quiet --upgrade polib
Assert-LastExitCode 'pip could not install polib'

$pythonRoot = Split-Path (Get-Command python.exe).Source -Parent
$mingw64 = Join-Path $msys 'mingw64'
if (-not (Test-Path -LiteralPath (Join-Path $mingw64 'bin\x86_64-w64-mingw32-gcc.exe'))) {
    throw "MinGW x64 cross compiler is missing under $mingw64"
}
$gitExe = (Get-Command git.exe -ErrorAction Stop).Source
$gitRoot = Split-Path (Split-Path $gitExe -Parent) -Parent

@"
@ECHO OFF
SET "MPCHC_MSYS=$msys"
SET "MPCHC_MINGW32=$mingw64"
SET "MPCHC_MINGW64=$mingw64"
SET "MSYSTEM=MINGW32"
SET "MSYS2_PATH_TYPE=inherit"
SET "MPCHC_GIT=$gitRoot"
SET "MPCHC_PYTHON=$pythonRoot"
SET "MPCHC_VS_PATH=$vs"
SET "MPCHC_WINSDK_VER=$sdkVersion"
"@ | Set-Content -LiteralPath build.user.bat -Encoding ascii

Write-Host 'Generated build.user.bat:' -ForegroundColor DarkGray
Get-Content -LiteralPath build.user.bat | ForEach-Object { Write-Host "  $_" -ForegroundColor DarkGray }

Write-Host 'Building MPC-HC x64 Release...' -ForegroundColor Cyan
$oldPreference = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
cmd /c "build.bat x64 MPCHC Release Nocolors Silent"
$buildExit = $LASTEXITCODE
$ErrorActionPreference = $oldPreference

if ($buildExit -ne 0) {
    Write-Host "MPC-HC build failed with exit code $buildExit." -ForegroundColor Red
    if (Test-Path -LiteralPath 'bin\logs') {
        Get-ChildItem 'bin\logs' -File | ForEach-Object {
            Write-Host "===== $($_.Name) =====" -ForegroundColor Yellow
            Get-Content $_.FullName -Tail 200
        }
    }
    exit $buildExit
}

$exe = Get-ChildItem 'bin\mpc-hc_x64' -Filter 'mpc-hc*.exe' -File -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $exe) {
    throw 'Build reported success but no MPC-HC x64 executable was produced.'
}

Write-Host "Built successfully: $($exe.FullName)" -ForegroundColor Green

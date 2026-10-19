# Builds a self-contained TapoCam for Windows x64 into .\dist\TapoCam, bundling everything it needs:
#   TapoCam.exe       the app (.NET 8, self-contained, single file)
#   ffmpeg\           ffmpeg.exe for live view and recording (LGPL build from BtbN/FFmpeg-Builds)
#   python\           embedded Python with pytapo preinstalled, for pan/tilt and camera settings
#   tapo_helper.py    the pytapo bridge shared with the macOS app
#
#   .\build.ps1                     build dist\TapoCam
#   .\build.ps1 -Version 1.2.0      stamp the version (CI passes the tag)
#   .\build.ps1 -Installer          also build the Inno Setup installer into .\out (needs Inno Setup 6)
param(
    [string]$Version = "1.0.0",
    [switch]$Installer
)
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"
Set-Location $PSScriptRoot

$PythonVersion = "3.12.10"
$FfmpegUrl = "https://github.com/BtbN/FFmpeg-Builds/releases/download/latest/ffmpeg-master-latest-win64-lgpl.zip"
$Dist = Join-Path $PSScriptRoot "dist\TapoCam"
$Cache = Join-Path $PSScriptRoot "dist\cache"
New-Item -ItemType Directory -Force $Cache | Out-Null

# Windows file versions are numeric: 1.2.0-abc1234 -> 1.2.0.0
$FileVersion = (($Version -split "[-+]")[0] + ".0.0.0").Split(".")[0..3] -join "."

Write-Host "== Publishing TapoCam $Version"
if (Test-Path $Dist) { Remove-Item -Recurse -Force $Dist }
dotnet publish TapoCam\TapoCam.csproj -c Release -r win-x64 --self-contained true `
    -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true -p:EnableCompressionInSingleFile=true -p:DebugType=none `
    -p:Version=$Version -p:FileVersion=$FileVersion -p:AssemblyVersion=$FileVersion -o $Dist
if ($LASTEXITCODE -ne 0) { throw "dotnet publish failed" }

Write-Host "== Bundling ffmpeg"
$ffZip = Join-Path $Cache "ffmpeg.zip"
if (-not (Test-Path $ffZip)) { Invoke-WebRequest $FfmpegUrl -OutFile $ffZip }
$ffDir = Join-Path $Cache "ffmpeg"
if (Test-Path $ffDir) { Remove-Item -Recurse -Force $ffDir }
Expand-Archive $ffZip $ffDir
New-Item -ItemType Directory -Force "$Dist\ffmpeg" | Out-Null
Get-ChildItem $ffDir -Recurse -Filter ffmpeg.exe | Select-Object -First 1 | Copy-Item -Destination "$Dist\ffmpeg\ffmpeg.exe"
Get-ChildItem $ffDir -Recurse -Filter LICENSE.txt | Select-Object -First 1 | Copy-Item -Destination "$Dist\ffmpeg\LICENSE.txt"

Write-Host "== Bundling Python $PythonVersion + pytapo"
$pyZip = Join-Path $Cache "python-$PythonVersion-embed-amd64.zip"
if (-not (Test-Path $pyZip)) {
    Invoke-WebRequest "https://www.python.org/ftp/python/$PythonVersion/python-$PythonVersion-embed-amd64.zip" -OutFile $pyZip
}
Expand-Archive $pyZip "$Dist\python"
# The embedded distribution ignores site-packages unless its ._pth file lists it.
$pth = Get-ChildItem "$Dist\python" -Filter "python*._pth" | Select-Object -First 1
(Get-Content $pth.FullName) -replace "^#\s*import site", "import site" | Set-Content $pth.FullName
Add-Content $pth.FullName "Lib\site-packages"
# Install pytapo's wheels for the embedded interpreter's exact version and platform.
$pyMinor = ($PythonVersion -split "\.")[0..1] -join ""
python -m pip install --disable-pip-version-check --quiet pytapo `
    --target "$Dist\python\Lib\site-packages" `
    --platform win_amd64 --python-version $pyMinor --implementation cp --only-binary=:all:
if ($LASTEXITCODE -ne 0) { throw "pip install pytapo failed" }

Write-Host "== Smoke test"
& "$Dist\python\python.exe" -c "import pytapo; print('pytapo OK')"
if ($LASTEXITCODE -ne 0) { throw "bundled Python can't import pytapo" }
& "$Dist\ffmpeg\ffmpeg.exe" -hide_banner -version | Select-Object -First 1
if (-not (Test-Path "$Dist\tapo_helper.py")) { throw "tapo_helper.py missing from the build" }

if ($Installer) {
    Write-Host "== Building installer"
    $iscc = "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe"
    if (-not (Test-Path $iscc)) { $iscc = (Get-Command iscc -ErrorAction Stop).Source }
    & $iscc /Qp "/DAppVersion=$Version" "/DFileVersion=$FileVersion" installer.iss
    if ($LASTEXITCODE -ne 0) { throw "Inno Setup failed" }
}

Write-Host "Built $Dist"

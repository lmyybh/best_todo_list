[CmdletBinding()]
param(
    [string]$FlutterPath,
    [string]$InnoSetupPath = 'D:\InnoSetup',
    [switch]$SkipFlutterBuild
)

$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
. (Join-Path $PSScriptRoot 'windows_release_metadata.ps1')
$release = Get-WindowsReleaseMetadata -ProjectRoot $projectRoot

if (-not $FlutterPath) {
    $flutterCommand = Get-Command flutter -ErrorAction SilentlyContinue
    if ($flutterCommand) {
        $FlutterPath = $flutterCommand.Source
    } elseif (Test-Path -LiteralPath 'D:\flutter\bin\flutter.bat') {
        $FlutterPath = 'D:\flutter\bin\flutter.bat'
    } else {
        throw 'Flutter was not found. Pass its path with -FlutterPath.'
    }
}
if (-not (Test-Path -LiteralPath $FlutterPath)) {
    throw "Flutter was not found at $FlutterPath"
}

$isccCandidates = @(
    (Join-Path $InnoSetupPath 'ISCC.exe'),
    (Join-Path $InnoSetupPath 'ISCC-x64.exe')
)
$isccPath = $isccCandidates | Where-Object {
    Test-Path -LiteralPath $_
} | Select-Object -First 1
if (-not $isccPath) {
    throw "Inno Setup compiler was not found under $InnoSetupPath"
}

if (-not $SkipFlutterBuild) {
    & $FlutterPath build windows --release
    if ($LASTEXITCODE -ne 0) {
        throw "Flutter build failed with exit code $LASTEXITCODE"
    }
}

$buildDir = Join-Path $projectRoot 'build\windows\x64\runner\Release'
$appExe = Join-Path $buildDir 'best_todo_list.exe'
if (-not (Test-Path -LiteralPath $appExe)) {
    throw "Windows release executable was not found at $appExe"
}

New-Item -ItemType Directory -Path $release.OutputDir -Force | Out-Null
$installerScript = Join-Path $projectRoot 'installer\windows\best_todo_list.iss'

& $isccPath `
    "/DMyAppVersion=$($release.Version)" `
    "/DBuildDir=$buildDir" `
    "/DOutputDir=$($release.OutputDir)" `
    "/DOutputBaseName=$($release.InstallerBaseName)" `
    $installerScript
if ($LASTEXITCODE -ne 0) {
    throw "Inno Setup compilation failed with exit code $LASTEXITCODE"
}

if (-not (Test-Path -LiteralPath $release.InstallerPath)) {
    throw "Installer was not created at $($release.InstallerPath)"
}

Get-Item -LiteralPath $release.InstallerPath | Select-Object FullName, Length, LastWriteTime

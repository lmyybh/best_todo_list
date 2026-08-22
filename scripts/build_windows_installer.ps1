[CmdletBinding()]
param(
    [string]$FlutterPath,
    [string]$InnoSetupPath = 'D:\InnoSetup',
    [switch]$SkipFlutterBuild
)

$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$pubspecPath = Join-Path $projectRoot 'pubspec.yaml'
$pubspec = Get-Content -LiteralPath $pubspecPath -Raw
$versionMatch = [regex]::Match(
    $pubspec,
    '(?m)^version:\s*(\d+\.\d+\.\d+)\+(\d+)\s*$'
)
if (-not $versionMatch.Success) {
    throw 'pubspec.yaml version must use the X.Y.Z+N format.'
}
$version = $versionMatch.Groups[1].Value

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

$outputDir = Join-Path $projectRoot 'build\installer'
New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
$installerScript = Join-Path $projectRoot 'installer\windows\best_todo_list.iss'

& $isccPath `
    "/DMyAppVersion=$version" `
    "/DBuildDir=$buildDir" `
    "/DOutputDir=$outputDir" `
    $installerScript
if ($LASTEXITCODE -ne 0) {
    throw "Inno Setup compilation failed with exit code $LASTEXITCODE"
}

$installerPath = Join-Path $outputDir "best_todo_list-$version-windows-x64-setup.exe"
if (-not (Test-Path -LiteralPath $installerPath)) {
    throw "Installer was not created at $installerPath"
}

Get-Item -LiteralPath $installerPath | Select-Object FullName, Length, LastWriteTime

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$SigningKeyPath,
    [Parameter(Mandatory=$true)][string]$PublicKey,
    [Parameter(Mandatory=$true)][string]$CertificatePath,
    [Parameter(Mandatory=$true)][string]$CertificatePassword,
    [Parameter(Mandatory=$true)][string]$WinSparklePrivateKeyPath,
    [string]$InnoSetupPath = 'C:\Program Files (x86)\Inno Setup 6'
)
$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
Set-Location -LiteralPath $projectRoot
. (Join-Path $PSScriptRoot 'windows_release_metadata.ps1')
$release = Get-WindowsReleaseMetadata -ProjectRoot $projectRoot
$signTool = Get-ChildItem 'C:\Program Files (x86)\Windows Kits\10\bin\*\x64\signtool.exe' |
    Sort-Object FullName -Descending | Select-Object -First 1
if (-not $signTool) { throw 'Windows SDK signtool was not found.' }
flutter build windows --release "--dart-define=UPDATE_PUBLIC_KEY=$PublicKey"
if ($LASTEXITCODE -ne 0) { throw 'Flutter build failed.' }
$app = Join-Path $projectRoot 'build\windows\x64\runner\Release\best_todo_list.exe'
& $signTool.FullName sign /fd SHA256 /tr http://timestamp.digicert.com /td SHA256 /f $CertificatePath /p $CertificatePassword $app
if ($LASTEXITCODE -ne 0) { throw 'Application Authenticode signing failed.' }
& (Join-Path $PSScriptRoot 'build_windows_installer.ps1') -SkipFlutterBuild -InnoSetupPath $InnoSetupPath
& $signTool.FullName sign /fd SHA256 /tr http://timestamp.digicert.com /td SHA256 /f $CertificatePath /p $CertificatePassword $release.InstallerPath
if ($LASTEXITCODE -ne 0) { throw 'Installer Authenticode signing failed.' }
& $signTool.FullName verify /pa $release.InstallerPath
if ($LASTEXITCODE -ne 0) { throw 'Installer Authenticode verification failed.' }
dart run scripts/sign_update.dart --package $release.InstallerPath --platform windows --version $release.Version `
    --key $SigningKeyPath --public-key $PublicKey --output (Join-Path $release.OutputDir 'update-windows.json')
if ($LASTEXITCODE -ne 0) { throw 'Update manifest signing failed.' }
& (Join-Path $PSScriptRoot 'build_windows_appcast.ps1') -PrivateKeyPath $WinSparklePrivateKeyPath

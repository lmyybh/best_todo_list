[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$PrivateKeyPath
)

$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
. (Join-Path $PSScriptRoot 'windows_release_metadata.ps1')
$release = Get-WindowsReleaseMetadata -ProjectRoot $projectRoot
if (-not (Test-Path -LiteralPath $release.InstallerPath)) {
    throw "Installer was not found at $($release.InstallerPath)"
}
if (-not (Test-Path -LiteralPath $PrivateKeyPath)) {
    throw 'The WinSparkle private key was not found.'
}

$signUpdatePath = Join-Path $projectRoot (
    'windows\flutter\ephemeral\.plugin_symlinks\auto_updater_windows\' +
    'windows\WinSparkle-0.8.1\bin\sign_update.bat'
)
if (-not (Test-Path -LiteralPath $signUpdatePath)) {
    throw 'WinSparkle signing tool was not found. Run flutter pub get first.'
}

$signature = (
    (& $signUpdatePath $release.InstallerPath $PrivateKeyPath | Out-String) -replace '\s', ''
)
if ($LASTEXITCODE -ne 0 -or $signature -notmatch '^[A-Za-z0-9+/]+={0,2}$') {
    throw 'WinSparkle failed to sign the installer.'
}

$installerLength = (Get-Item -LiteralPath $release.InstallerPath).Length
$releaseUrl = "https://github.com/lmyybh/best_todo_list/releases/tag/v$($release.Version)"
$installerUrl = (
    'https://github.com/lmyybh/best_todo_list/releases/latest/download/' +
    "$($release.InstallerBaseName).exe"
)
$pubDate = [DateTimeOffset]::Now.ToString('ddd, dd MMM yyyy HH:mm:ss zzz', [Globalization.CultureInfo]::InvariantCulture)
$appcastPath = Join-Path $release.OutputDir 'appcast-windows.xml'
$appcast = @"
<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Best Todo List Windows Updates</title>
    <description>Best Todo List Windows release feed</description>
    <language>zh-CN</language>
    <item>
      <title>Version $($release.Version)</title>
      <sparkle:releaseNotesLink>$releaseUrl</sparkle:releaseNotesLink>
      <pubDate>$pubDate</pubDate>
      <enclosure url="$installerUrl"
                 sparkle:dsaSignature="$signature"
                 sparkle:version="$($release.Version)"
                 sparkle:os="windows"
                 length="$installerLength"
                 type="application/octet-stream" />
    </item>
  </channel>
</rss>
"@

Set-Content -LiteralPath $appcastPath -Value $appcast -Encoding utf8
Get-Item -LiteralPath $appcastPath | Select-Object FullName, Length, LastWriteTime

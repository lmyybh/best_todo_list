[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$PrivateKeyPath
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
$buildNumber = $versionMatch.Groups[2].Value
$fullVersion = "$version+$buildNumber"
$installerName = "best_todo_list-$version-windows-x64-setup.exe"
$installerPath = Join-Path $projectRoot "build\installer\$installerName"
if (-not (Test-Path -LiteralPath $installerPath)) {
    throw "Installer was not found at $installerPath"
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
    (& $signUpdatePath $installerPath $PrivateKeyPath | Out-String) -replace '\s', ''
)
if ($LASTEXITCODE -ne 0 -or $signature -notmatch '^[A-Za-z0-9+/]+={0,2}$') {
    throw 'WinSparkle failed to sign the installer.'
}

$installerLength = (Get-Item -LiteralPath $installerPath).Length
$releaseUrl = "https://github.com/lmyybh/best_todo_list/releases/tag/v$version"
$installerUrl = (
    'https://github.com/lmyybh/best_todo_list/releases/latest/download/' +
    $installerName
)
$pubDate = [DateTimeOffset]::Now.ToString('ddd, dd MMM yyyy HH:mm:ss zzz', [Globalization.CultureInfo]::InvariantCulture)
$appcastPath = Join-Path $projectRoot 'build\installer\appcast-windows.xml'
$appcast = @"
<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Best Todo List Windows Updates</title>
    <description>Best Todo List Windows release feed</description>
    <language>zh-CN</language>
    <item>
      <title>Version $version</title>
      <sparkle:releaseNotesLink>$releaseUrl</sparkle:releaseNotesLink>
      <pubDate>$pubDate</pubDate>
      <enclosure url="$installerUrl"
                 sparkle:dsaSignature="$signature"
                 sparkle:version="$fullVersion"
                 sparkle:os="windows"
                 length="$installerLength"
                 type="application/octet-stream" />
    </item>
  </channel>
</rss>
"@

Set-Content -LiteralPath $appcastPath -Value $appcast -Encoding utf8
Get-Item -LiteralPath $appcastPath | Select-Object FullName, Length, LastWriteTime

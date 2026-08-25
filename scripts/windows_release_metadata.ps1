function Get-WindowsReleaseMetadata {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProjectRoot
    )

    $pubspecPath = Join-Path $ProjectRoot 'pubspec.yaml'
    $pubspec = Get-Content -LiteralPath $pubspecPath -Raw
    $versionMatch = [regex]::Match(
        $pubspec,
        '(?m)^version:\s*(\d+\.\d+\.\d+)\s*$'
    )
    if (-not $versionMatch.Success) {
        throw 'pubspec.yaml version must use the X.Y.Z format.'
    }

    $version = $versionMatch.Groups[1].Value
    $installerBaseName = "best_todo_list-$version-windows-x64-setup"
    $outputDir = Join-Path $ProjectRoot 'build\installer'
    return [pscustomobject]@{
        Version = $version
        InstallerBaseName = $installerBaseName
        InstallerPath = Join-Path $outputDir "$installerBaseName.exe"
        OutputDir = $outputDir
    }
}

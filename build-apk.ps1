$ErrorActionPreference = 'Stop'
$env:JAVA_HOME = 'C:\Program Files\Java\jdk-17'
$env:GRADLE_USER_HOME = 'D:\DevCaches\.gradle'
$buildTemp = Join-Path $PSScriptRoot '.tmp'
New-Item -ItemType Directory -Path $buildTemp -Force | Out-Null
$env:TEMP = $buildTemp
$env:TMP = $buildTemp
Push-Location (Join-Path $PSScriptRoot 'mobile')
try {
  $ErrorActionPreference = 'Continue'
  & 'C:\Users\anton\fvm\versions\3.47.4\bin\flutter.bat' build apk --release
  $buildExit = $LASTEXITCODE
  $ErrorActionPreference = 'Stop'
  if ($buildExit -ne 0) { throw 'No se pudo generar el APK.' }
  $release = Join-Path $PSScriptRoot 'releases'
  New-Item -ItemType Directory -Path $release -Force | Out-Null
  Copy-Item 'build\app\outputs\flutter-apk\app-release.apk' (Join-Path $release 'umbral-0.2.0+2.apk')
  Get-FileHash (Join-Path $release 'umbral-0.2.0+2.apk') -Algorithm SHA256
} finally { Pop-Location }

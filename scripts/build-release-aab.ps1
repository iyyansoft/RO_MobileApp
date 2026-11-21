<#
.SYNOPSIS
  Builds the NeeroPlus Play Store App Bundle (.aab) signed with the company upload key.
  Builds only: it never uploads or publishes anything.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File scripts\build-release-aab.ps1
  powershell -ExecutionPolicy Bypass -File scripts\build-release-aab.ps1 -KeyProperties D:\Secure\key.properties
#>
param(
  [string]$KeyProperties = 'C:\NeeroPlusSigning\key.properties',
  [string]$ApiBaseUrl = 'https://ro-mobileapp.onrender.com',
  [string]$OutputFolder = "$env:USERPROFILE\ro_mobile_build\release",
  [string]$Keytool = ''
)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent

if ($ApiBaseUrl -notmatch '^https://' -or $ApiBaseUrl -match 'localhost|127\.0\.0\.1|10\.0\.2\.2') {
  throw "Refusing: the release bundle must use the production HTTPS API, not $ApiBaseUrl."
}
if (-not (Test-Path $KeyProperties)) { throw "Company key not found: $KeyProperties (see docs\ANDROID_RELEASE_SIGNING.md)." }
$KeyProperties = (Resolve-Path $KeyProperties).Path
if ($KeyProperties.StartsWith($root, [StringComparison]::OrdinalIgnoreCase)) { throw 'Refusing: key.properties must be outside the project folder.' }
$props = @{}
Get-Content $KeyProperties | Where-Object { $_ -match '^\s*([^#=]+?)\s*=\s*(.*)$' } | ForEach-Object { $props[$Matches[1]] = $Matches[2] }
$storeFile = $props['storeFile'] -replace '/', '\'
if (-not $storeFile -or -not (Test-Path $storeFile)) { throw "Keystore not found: $storeFile" }

$keytoolExe = $Keytool
if (-not $keytoolExe) {
  $keytoolExe = @((Join-Path "$env:JAVA_HOME" 'bin\keytool.exe')) + @(Get-ChildItem "$env:LOCALAPPDATA\ROAndroidJava\*\bin\keytool.exe" -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName }) +
    @('C:\Program Files\Android\Android Studio\jbr\bin\keytool.exe') | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
}
if (-not $keytoolExe) { throw 'keytool.exe not found. Pass -Keytool <path>.' }

$version = ((Get-Content (Join-Path $root 'pubspec.yaml')) | Where-Object { $_ -match '^version:' }) -replace 'version:\s*', ''
Write-Host "App version (pubspec.yaml): $version  -- the number after '+' must be higher than the last Play upload."

$setHere = $false
if (-not $env:NEEROPLUS_KEYSTORE_PASSWORD -and -not $props['storePassword']) {
  $secure = Read-Host 'Company keystore password' -AsSecureString
  $env:NEEROPLUS_KEYSTORE_PASSWORD = [Runtime.InteropServices.Marshal]::PtrToStringBSTR([Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure))
  $setHere = $true
}
$env:NEEROPLUS_KEY_PROPERTIES = $KeyProperties
$aab = Join-Path $root 'build\app\outputs\bundle\release\app-release.aab'
if (Test-Path $aab) { Remove-Item $aab -Force }   # never pick up an older bundle
# Native tools write progress to stderr; Windows PowerShell must not treat that as an error.
$ErrorActionPreference = 'Continue'
try {
  Push-Location $root
  & flutter build appbundle --release "--dart-define=API_BASE_URL=$ApiBaseUrl"
  $buildExit = $LASTEXITCODE
} finally {
  Pop-Location
  if ($setHere) { Remove-Item Env:\NEEROPLUS_KEYSTORE_PASSWORD -ErrorAction SilentlyContinue }
  Remove-Item Env:\NEEROPLUS_KEY_PROPERTIES -ErrorAction SilentlyContinue
}
if ($buildExit -ne 0 -or -not (Test-Path $aab)) { throw 'flutter build appbundle failed.' }
$cert = ((& $keytoolExe -printcert -jarfile $aab 2>&1) | ForEach-Object { "$_" }) -join "`n"
$ErrorActionPreference = 'Stop'
if ($cert -match 'Android Debug' -or $cert -notmatch 'SHA256:') { throw 'Refusing: the bundle is not signed with the company key.' }
$owner = ($cert -split "`n" | Where-Object { $_ -match 'Owner:' } | Select-Object -First 1).Trim()
$fingerprint = ($cert -split "`n" | Where-Object { $_ -match 'SHA256:' } | Select-Object -First 1).Trim()

New-Item -ItemType Directory -Force -Path $OutputFolder | Out-Null
$name = 'NeeroPlus-' + ($version -replace '\+', '-build') + '.aab'
$target = Join-Path $OutputFolder $name
Copy-Item $aab $target -Force
$hash = (Get-FileHash $target -Algorithm SHA256).Hash
Write-Host ''
Write-Host "Bundle:      $target"
Write-Host "Signed by:   $owner"
Write-Host "Certificate  $fingerprint  (must match the fingerprint saved in the password manager)"
Write-Host "File SHA256: $hash"
Write-Host 'Nothing was uploaded. Upload to Play Console only after approval.'

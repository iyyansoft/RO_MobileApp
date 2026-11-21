<#
.SYNOPSIS
  Creates the company's Android UPLOAD key for NeeroPlus (run once, by the owner).

.DESCRIPTION
  - Creates a private folder OUTSIDE any Git repository (default C:\NeeroPlusSigning)
    readable only by you, SYSTEM and Administrators.
  - Asks for a strong password (never shown, never written to disk) and creates
    neeroplus-upload.jks (PKCS12, RSA 2048, valid ~27 years, alias "upload").
  - Writes key.properties WITHOUT any password (the build asks for it).
  - Prints the certificate SHA-256 fingerprint to record in the password manager.
  Never overwrites an existing keystore. Uploads nothing.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File scripts\create-signing-key.ps1 -CompanyName "Aqua Tech Solutions" -City "Coimbatore"
#>
param(
  [Parameter(Mandatory = $true)][string]$CompanyName,
  [Parameter(Mandatory = $true)][string]$City,
  [string]$State = 'Tamil Nadu',
  [string]$Folder = 'C:\NeeroPlusSigning',
  [string]$Keytool = ''
)
$ErrorActionPreference = 'Stop'

function Find-Keytool {
  if ($Keytool -and (Test-Path $Keytool)) { return $Keytool }
  $candidates = @()
  if ($env:JAVA_HOME) { $candidates += (Join-Path $env:JAVA_HOME 'bin\keytool.exe') }
  $candidates += Get-ChildItem "$env:LOCALAPPDATA\ROAndroidJava\*\bin\keytool.exe" -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName }
  $candidates += 'C:\Program Files\Android\Android Studio\jbr\bin\keytool.exe'
  foreach ($c in $candidates) { if ($c -and (Test-Path $c)) { return $c } }
  throw 'keytool.exe not found. Pass -Keytool <path to JDK bin\keytool.exe>.'
}

$keytoolExe = Find-Keytool
$Folder = [System.IO.Path]::GetFullPath($Folder)
$keystore = Join-Path $Folder 'neeroplus-upload.jks'
$properties = Join-Path $Folder 'key.properties'

# Never inside a Git repository (e.g. the project folder).
$probe = $Folder
while ($probe) {
  if (Test-Path (Join-Path $probe '.git')) { throw "Refusing: $Folder is inside a Git repository ($probe). Choose a folder outside the project." }
  $parent = Split-Path $probe -Parent
  if ($parent -eq $probe) { break }
  $probe = $parent
}
if (Test-Path $keystore) { throw "Refusing: $keystore already exists. The company key is never overwritten." }

# Private folder: only the current user, SYSTEM and Administrators.
New-Item -ItemType Directory -Force -Path $Folder | Out-Null
$me = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
& icacls $Folder /inheritance:r /grant:r "${me}:(OI)(CI)F" 'NT AUTHORITY\SYSTEM:(OI)(CI)F' 'BUILTIN\Administrators:(OI)(CI)F' | Out-Null

# Password: from the prompt (or NEEROPLUS_KEYSTORE_PASSWORD if already set, e.g. by a
# password-manager CLI). Passed to keytool through an environment variable only.
$plain = $env:NEEROPLUS_KEYSTORE_PASSWORD
if (-not $plain) {
  $p1 = Read-Host 'New keystore password (at least 16 characters; store it in the password manager)' -AsSecureString
  $p2 = Read-Host 'Repeat the password' -AsSecureString
  $u1 = [Runtime.InteropServices.Marshal]::PtrToStringBSTR([Runtime.InteropServices.Marshal]::SecureStringToBSTR($p1))
  $u2 = [Runtime.InteropServices.Marshal]::PtrToStringBSTR([Runtime.InteropServices.Marshal]::SecureStringToBSTR($p2))
  if ($u1 -ne $u2) { throw 'The passwords do not match. Nothing was created.' }
  $plain = $u1
}
if ($plain.Length -lt 16) { throw 'Password too short (minimum 16 characters). Nothing was created.' }

$env:NEEROPLUS_KEYTOOL_PW = $plain
# keytool writes progress to stderr; Windows PowerShell must not treat that as an error.
$ErrorActionPreference = 'Continue'
try {
  $dname = "CN=$CompanyName, O=$CompanyName, L=$City, ST=$State, C=IN"
  $out = & $keytoolExe -genkeypair -keystore $keystore -storetype PKCS12 -alias upload -keyalg RSA -keysize 2048 -validity 10000 `
    -dname $dname -storepass:env NEEROPLUS_KEYTOOL_PW -keypass:env NEEROPLUS_KEYTOOL_PW 2>&1
  if ($LASTEXITCODE -ne 0 -or -not (Test-Path $keystore)) { throw "keytool did not create the keystore: $out" }
  $listing = & $keytoolExe -list -v -keystore $keystore -alias upload -storepass:env NEEROPLUS_KEYTOOL_PW 2>&1
  if ($LASTEXITCODE -ne 0) { throw 'The new keystore could not be read back.' }
  $sha256 = (($listing | ForEach-Object { "$_" }) | Where-Object { $_ -match 'SHA256:' } | Select-Object -First 1).Trim()
} finally {
  Remove-Item Env:\NEEROPLUS_KEYTOOL_PW -ErrorAction SilentlyContinue
  $plain = $null
  $ErrorActionPreference = 'Stop'
}

# No password in this file: the build asks for it (scripts\build-release-aab.ps1).
@(
  'keyAlias=upload',
  ('storeFile=' + ($keystore -replace '\\', '/'))
) | Set-Content -Path $properties -Encoding ascii

Write-Host ''
Write-Host "Created $keystore"
Write-Host "Created $properties (contains no password)"
Write-Host "Certificate $sha256"
Write-Host ''
Write-Host 'Now, before anything else:'
Write-Host '  1. Save the password and the .jks file (attachment) in the company password manager.'
Write-Host '  2. Record the SHA256 fingerprint above in the same entry.'
Write-Host '  3. Copy the .jks to an encrypted USB drive kept in a locked place; check the copy with:'
Write-Host "     keytool -list -keystore <copy>\neeroplus-upload.jks -alias upload"
Write-Host '  4. Never put the .jks, key.properties or the password in GitHub, email, chat or the project folder.'

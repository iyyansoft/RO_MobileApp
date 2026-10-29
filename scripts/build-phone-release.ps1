param(
  [Parameter(Mandatory = $true)]
  [string]$ApiBaseUrl
)
$ErrorActionPreference = 'Stop'

try {
  $apiUri = [Uri]$ApiBaseUrl
} catch {
  throw 'ApiBaseUrl must be a valid absolute HTTPS API URL.'
}
if (-not $apiUri.IsAbsoluteUri -or $apiUri.Scheme -ne 'https') {
  throw 'Release builds require an HTTPS production API URL.'
}
$hostName = $apiUri.Host.ToLowerInvariant()
if ($hostName -in @('localhost', '127.0.0.1', '10.0.2.2', '0.0.0.0') -or
    $hostName -match '^(10\.|192\.168\.|172\.(1[6-9]|2[0-9]|3[01])\.)') {
  throw 'A release APK cannot use localhost, emulator, or private LAN API hosts.'
}
if ($hostName -like '*.supabase.co' -and $apiUri.AbsolutePath.TrimEnd('/') -eq '/api') {
  throw 'The Supabase project root does not implement this app’s Express /api routes. Complete and verify API migration before building a Supabase-only release.'
}

$flutterCommand = Get-Command flutter -ErrorAction SilentlyContinue
$flutterPath = if ($flutterCommand) {
  $flutterCommand.Source
} else {
  Join-Path $env:LOCALAPPDATA 'FlutterSDK\source\bin\flutter.bat'
}

& $flutterPath build apk --release "--dart-define=API_BASE_URL=$ApiBaseUrl"
if ($LASTEXITCODE -ne 0) {
  throw "Flutter release build failed with exit code $LASTEXITCODE."
}

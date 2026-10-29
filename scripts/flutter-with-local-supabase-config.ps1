param(
  [Parameter(ValueFromRemainingArguments = $true)]
  [string[]] $FlutterArgs
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$envFile = Join-Path $projectRoot '.env'
if (-not (Test-Path -LiteralPath $envFile -PathType Leaf)) {
  throw 'Local .env file was not found in the project root.'
}

# Read only the two client-safe values. Never parse/copy database URLs, service
# role keys, SMTP credentials, payment secrets, or other .env values.
$publicValues = @{}
foreach ($line in Get-Content -LiteralPath $envFile) {
  if ($line -match '^\s*(?:export\s+)?(SUPABASE_URL|SUPABASE_PUBLISHABLE_KEY|SUPABASE_ANON_KEY)\s*=\s*(.*?)\s*$') {
    $name = $Matches[1]
    $value = $Matches[2].Trim()
    if ($value.Length -ge 2 -and
        (($value.StartsWith('"') -and $value.EndsWith('"')) -or
         ($value.StartsWith("'") -and $value.EndsWith("'")))) {
      $value = $value.Substring(1, $value.Length - 2)
    }
    $publicValues[$name] = $value
  }
}

$url = [string]$publicValues['SUPABASE_URL']
$publishableKey = [string]$publicValues['SUPABASE_PUBLISHABLE_KEY']
if (-not $publishableKey) { $publishableKey = [string]$publicValues['SUPABASE_ANON_KEY'] }
if (-not $url -or -not $publishableKey) {
  throw 'Set SUPABASE_URL and SUPABASE_PUBLISHABLE_KEY (or SUPABASE_ANON_KEY) in the local .env file.'
}
$parsedUrl = $null
if (-not [uri]::TryCreate($url, [UriKind]::Absolute, [ref]$parsedUrl) -or
    $parsedUrl.Scheme -notin @('https', 'http') -or -not $parsedUrl.Host) {
  throw 'SUPABASE_URL must be an absolute HTTP or HTTPS URL.'
}

if (-not $FlutterArgs -or $FlutterArgs.Count -eq 0) { $FlutterArgs = @('run') }
$flutterCommand = Get-Command 'flutter.bat' -ErrorAction SilentlyContinue
$flutterPath = if ($flutterCommand) { $flutterCommand.Source } else { $null }
if (-not $flutterPath -and $env:FLUTTER_ROOT) {
  $candidate = Join-Path $env:FLUTTER_ROOT 'bin/flutter.bat'
  if (Test-Path -LiteralPath $candidate) { $flutterPath = $candidate }
}
if (-not $flutterPath) {
  $candidate = Join-Path $env:LOCALAPPDATA 'FlutterSDK/source/bin/flutter.bat'
  if (Test-Path -LiteralPath $candidate) { $flutterPath = $candidate }
}
if (-not $flutterPath) { throw 'Could not locate flutter.bat. Add Flutter to PATH or set FLUTTER_ROOT.' }

$tempDefineFile = Join-Path ([IO.Path]::GetTempPath()) ([IO.Path]::GetRandomFileName() + '.json')
try {
  $defineJson = @{
    SUPABASE_URL = $url
    SUPABASE_PUBLISHABLE_KEY = $publishableKey
  } | ConvertTo-Json -Compress
  [IO.File]::WriteAllText($tempDefineFile, $defineJson, [Text.UTF8Encoding]::new($false))

  # Keep the caller's working directory so Flutter resolves the normal project
  # files and targets. The temp file contains only client-public configuration.
  $subcommand = $FlutterArgs[0]
  $forwardArgs = @($subcommand, "--dart-define-from-file=$tempDefineFile")
  if ($FlutterArgs.Count -gt 1) { $forwardArgs += $FlutterArgs[1..($FlutterArgs.Count - 1)] }
  & $flutterPath @forwardArgs
  $flutterExitCode = $LASTEXITCODE
} finally {
  Remove-Item -LiteralPath $tempDefineFile -Force -ErrorAction SilentlyContinue
}
exit $flutterExitCode

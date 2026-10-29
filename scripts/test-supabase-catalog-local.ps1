$ErrorActionPreference = 'Stop'
$workdir = if ($env:SUPABASE_LOCAL_TEST_WORKDIR) { $env:SUPABASE_LOCAL_TEST_WORKDIR } else { Join-Path $env:TEMP 'ro-catalog-supabase-local' }
$expectedProjectId = if ($env:SUPABASE_LOCAL_TEST_PROJECT_ID) { $env:SUPABASE_LOCAL_TEST_PROJECT_ID } else { 'ro_catalog_local_test' }
$expectedApiPort = if ($env:SUPABASE_LOCAL_TEST_API_PORT) { [int]$env:SUPABASE_LOCAL_TEST_API_PORT } else { 54331 }
$expectedDbPort = if ($env:SUPABASE_LOCAL_TEST_DB_PORT) { [int]$env:SUPABASE_LOCAL_TEST_DB_PORT } else { 54332 }
$configPath = Join-Path $workdir 'supabase\config.toml'
$config = if (Test-Path -LiteralPath $configPath) { Get-Content -LiteralPath $configPath -Raw } else { '' }
if ($config -notmatch "(?m)^project_id\s*=\s*`"$([regex]::Escape($expectedProjectId))`"\s*$" -or
    $config -notmatch "(?m)^port\s*=\s*$expectedApiPort\s*$" -or
    $config -notmatch "(?m)^port\s*=\s*$expectedDbPort\s*$") {
  throw 'Refusing to run/reset Supabase: the isolated local project configuration is missing or does not match the expected project and ports.'
}
if (Test-Path -LiteralPath (Join-Path $workdir 'supabase\.temp\project-ref')) {
  throw 'Refusing to run/reset Supabase: the isolated local workdir contains linked-project metadata.'
}

function Invoke-LocalSupabaseCli([string[]]$Arguments) {
  $previousPreference = $ErrorActionPreference
  try {
    # Windows PowerShell can surface native stderr as a terminating error when
    # ErrorActionPreference is Stop. Invoke the already-cached CLI directly to
    # avoid npx registry/network resolution during a local-only test.
    $ErrorActionPreference = 'Continue'
    $cliExe = Get-ChildItem (Join-Path $env:LOCALAPPDATA 'npm-cache\_npx') -Directory -ErrorAction SilentlyContinue |
      ForEach-Object {
        $candidate = Join-Path $_.FullName 'node_modules\@supabase\cli-windows-x64\bin\supabase.exe'
        if (Test-Path -LiteralPath $candidate) { $candidate }
      } | Select-Object -First 1
    if (-not $cliExe) { throw 'Cached Supabase CLI executable was not found; no remote operation was attempted.' }
    $output = (& $cliExe --workdir $workdir @Arguments 2>&1 | Out-String)
    return @{ ExitCode = $LASTEXITCODE; Output = $output }
  } finally {
    $ErrorActionPreference = $previousPreference
  }
}

function Get-LocalSupabaseStatusValues {
  $result = Invoke-LocalSupabaseCli -Arguments @('status', '--output', 'env')
  $raw = $result.Output
  if ($result.ExitCode -ne 0) {
    $safe = $raw -replace '(?im)^\s*(?:export\s+)?(?:ANON_KEY|SUPABASE_ANON_KEY|PUBLISHABLE_KEY|SUPABASE_PUBLISHABLE_KEY|SERVICE_ROLE_KEY|SUPABASE_SERVICE_ROLE_KEY|SECRET_KEY|SUPABASE_SECRET_KEY|DB_URL|POSTGRES_URL|SUPABASE_DB_URL)=.*$', '[redacted local Supabase value]'
    throw "Could not read local Supabase status. $safe"
  }

  $values = @{}
  foreach ($line in ($raw -split "`r?`n")) {
    if ($line -match '^\s*(?:export\s+)?([A-Z0-9_]+)=(.*)\s*$') {
      $value = $Matches[2].Trim()
      if ($value.Length -ge 2 -and (($value[0] -eq '"' -and $value[$value.Length - 1] -eq '"') -or ($value[0] -eq "'" -and $value[$value.Length - 1] -eq "'"))) {
        $value = $value.Substring(1, $value.Length - 2)
      }
      $values[$Matches[1]] = $value
    }
  }

  $api = $values['API_URL']; if (-not $api) { $api = $values['SUPABASE_URL'] }
  $db = $values['DB_URL']; if (-not $db) { $db = $values['POSTGRES_URL'] }; if (-not $db) { $db = $values['SUPABASE_DB_URL'] }
  $anon = $values['ANON_KEY']; if (-not $anon) { $anon = $values['SUPABASE_ANON_KEY'] }; if (-not $anon) { $anon = $values['PUBLISHABLE_KEY'] }
  $service = $values['SERVICE_ROLE_KEY']; if (-not $service) { $service = $values['SUPABASE_SERVICE_ROLE_KEY'] }; if (-not $service) { $service = $values['SECRET_KEY'] }
  if (-not $api -or -not $db -or -not $anon -or -not $service) {
    throw 'Local Supabase status is missing required local API/database credentials; values were not displayed.'
  }
  return @{ Api = $api; Db = $db; Anon = $anon; Service = $service }
}

$savedNames = @(
  'SUPABASE_LOCAL_TEST_API_URL', 'SUPABASE_LOCAL_TEST_DB_URL',
  'SUPABASE_LOCAL_TEST_ANON_KEY', 'SUPABASE_LOCAL_TEST_SERVICE_ROLE_KEY',
  'SUPABASE_LOCAL_TEST_WORKDIR', 'SUPABASE_LOCAL_TEST_PROJECT_ID',
  'SUPABASE_LOCAL_TEST_API_PORT', 'SUPABASE_LOCAL_TEST_DB_PORT',
  'SUPABASE_LOCAL_TEST_KEEP_IMAGE_FIXTURE', 'SUPABASE_LOCAL_TEST_EDGE_FUNCTION_URL',
  'SUPABASE_TELEMETRY_DISABLED', 'USERPROFILE', 'HOME', 'DOCKER_CONFIG'
)
$previous = @{}
foreach ($name in $savedNames) { $previous[$name] = [Environment]::GetEnvironmentVariable($name, 'Process') }
$edgeProcess = $null
$createdFunctionFolders = @()
$edgeStdout = Join-Path $workdir 'admin-catalog-edge.stdout.log'
$edgeStderr = Join-Path $workdir 'admin-catalog-edge.stderr.log'

try {
  # Supabase CLI telemetry attempts to write under the user profile on some
  # Windows installs. Disable it and point its profile at this disposable
  # workdir for this process only; preserve Docker's existing config explicitly.
  $env:SUPABASE_TELEMETRY_DISABLED = '1'
  $cliProfile = Join-Path $workdir 'cli-profile'
  New-Item -ItemType Directory -Path $cliProfile -Force | Out-Null
  $env:USERPROFILE = $cliProfile
  $env:HOME = $cliProfile
  $dockerConfig = Join-Path $previous['USERPROFILE'] '.docker'
  if (Test-Path -LiteralPath $dockerConfig) { $env:DOCKER_CONFIG = $dockerConfig }
  # Reuse a healthy stack for this exact isolated project; repeated `start`
  # calls can stall while Docker rechecks unrelated optional services.
  $localApiHealthy = $false
  try {
    $health = Invoke-WebRequest -Uri "http://127.0.0.1:$expectedApiPort/auth/v1/health" `
      -Method Get -UseBasicParsing -TimeoutSec 3 -ErrorAction Stop
    $localApiHealthy = $health.StatusCode -eq 200
  } catch { $localApiHealthy = $false }
  if (-not $localApiHealthy) {
    # This workdir has a fixed disposable ID and loopback-only ports, checked
    # above. It contains no linked project-ref metadata.
    $startResult = Invoke-LocalSupabaseCli -Arguments @('start')
    $startOutput = $startResult.Output
    if ($startResult.ExitCode -ne 0) {
      $safe = $startOutput -replace '(?im)^.*(?:ANON_KEY|SERVICE_ROLE_KEY|PUBLISHABLE_KEY|SECRET_KEY|DB_URL|POSTGRES_URL).*$','[redacted local Supabase value]'
      throw "Could not start the isolated local Supabase stack. $safe"
    }
  }

  $status = Get-LocalSupabaseStatusValues
  $apiUri = [Uri]$status.Api
  $dbUri = [Uri]$status.Db
  if ($apiUri.Host -notin @('127.0.0.1', 'localhost', '::1') -or
      $dbUri.Host -notin @('127.0.0.1', 'localhost', '::1')) {
    throw 'Refusing to run catalog integration tests: Supabase status is not loopback-only.'
  }
  if ($apiUri.Port -ne $expectedApiPort -or $dbUri.Port -ne $expectedDbPort) {
    throw 'Refusing to run catalog integration tests: local Supabase ports do not match the isolated test profile.'
  }

  $env:SUPABASE_LOCAL_TEST_API_URL = $status.Api
  $env:SUPABASE_LOCAL_TEST_DB_URL = $status.Db
  $env:SUPABASE_LOCAL_TEST_API_PORT = "$expectedApiPort"
  $env:SUPABASE_LOCAL_TEST_DB_PORT = "$expectedDbPort"
  $env:SUPABASE_LOCAL_TEST_ANON_KEY = $status.Anon
  $env:SUPABASE_LOCAL_TEST_SERVICE_ROLE_KEY = $status.Service
  $env:SUPABASE_LOCAL_TEST_EDGE_FUNCTION_URL = $status.Api
  $keepImageForFlutter = $env:SUPABASE_LOCAL_TEST_SKIP_FLUTTER -ne '1'
  $env:SUPABASE_LOCAL_TEST_KEEP_IMAGE_FIXTURE = if ($keepImageForFlutter) { '1' } else { '0' }

  # Never use db reset as a convenience. Require a verified empty public
  # schema before fixture creation; the API test repeats its table-level guard.
  & node scripts/assert-empty-supabase-local.cjs
  if ($LASTEXITCODE -ne 0) { throw 'Local Supabase database is not empty; refusing to overwrite it.' }

  try {
    # The Edge Runtime must load the real repository function, but it must use
    # only this disposable project's config, local Auth, local Storage and local
    # database. Refuse to overwrite a pre-existing temp function checkout.
    $functionsRoot = Join-Path $workdir 'supabase\functions'
    $adminFunctionTarget = Join-Path $functionsRoot 'admin-catalog'
    $sharedTarget = Join-Path $functionsRoot '_shared'
    if ((Test-Path -LiteralPath $adminFunctionTarget) -or (Test-Path -LiteralPath $sharedTarget)) {
      throw 'Refusing to overwrite existing temporary Supabase function fixtures.'
    }
    New-Item -ItemType Directory -Path $functionsRoot -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path (Get-Location).Path 'supabase\functions\admin-catalog') `
      -Destination $adminFunctionTarget -Recurse
    $createdFunctionFolders += $adminFunctionTarget
    New-Item -ItemType Directory -Path $sharedTarget | Out-Null
    Copy-Item -LiteralPath (Join-Path (Get-Location).Path 'supabase\functions\_shared\admin_catalog_core.mjs') `
      -Destination (Join-Path $sharedTarget 'admin_catalog_core.mjs')
    $createdFunctionFolders += $sharedTarget

    $edgeProcess = Start-Process -FilePath $cliExe `
      -ArgumentList @('--workdir', $workdir, 'functions', 'serve', 'admin-catalog', '--no-verify-jwt') `
      -WorkingDirectory $workdir -WindowStyle Hidden -PassThru `
      -RedirectStandardOutput $edgeStdout -RedirectStandardError $edgeStderr
    $edgeReady = $false
    for ($attempt = 0; $attempt -lt 90; $attempt++) {
      if ($edgeProcess.HasExited) { break }
      try {
        Invoke-WebRequest -Uri "$($status.Api)/functions/v1/admin-catalog" -Method Get `
          -UseBasicParsing -TimeoutSec 2 -ErrorAction Stop | Out-Null
        $edgeReady = $true
        break
      } catch {
        if ($_.Exception.Response) { $edgeReady = $true; break }
      }
      Start-Sleep -Seconds 1
    }
    if (-not $edgeReady) {
      throw 'Local admin-catalog Edge Runtime did not become ready; inspect the sanitized test result, not hosted Supabase.'
    }

    node --test test/supabase_catalog_local_api_test.cjs
    if ($LASTEXITCODE -ne 0) { throw 'Local Supabase catalog API/RLS/Storage integration test failed.' }

    if ($env:SUPABASE_LOCAL_TEST_SKIP_FLUTTER -eq '1') {
      Write-Output 'Flutter local integration was explicitly skipped; Node/PostgREST/Auth/RLS/Storage checks still ran.'
    } else {
      $flutterCommand = Get-Command flutter -ErrorAction SilentlyContinue
      $flutterPath = if ($flutterCommand) { $flutterCommand.Source } else { 'C:\Users\priya\AppData\Local\FlutterSDK\source\bin\flutter.bat' }
      if (-not (Test-Path -LiteralPath $flutterPath)) {
        throw 'Flutter SDK was not found; local Node/PostgREST tests ran, but Flutter integration test could not start.'
      }
      $flutterArgs = @(
        'test',
        "--dart-define=SUPABASE_URL=$($status.Api)",
        "--dart-define=SUPABASE_PUBLISHABLE_KEY=$($status.Anon)",
        '--dart-define=USE_SUPABASE_CATALOG=true',
        'test/supabase_catalog_client_local_test.dart'
      )
      & $flutterPath @flutterArgs
      if ($LASTEXITCODE -ne 0) { throw 'Flutter Supabase catalog integration test failed.' }
    }
  } finally {
    if ($edgeProcess -and -not $edgeProcess.HasExited) {
      Stop-Process -Id $edgeProcess.Id -ErrorAction SilentlyContinue
      $edgeProcess.WaitForExit(5000) | Out-Null
    }
    # Remove only the local public-image fixture and local Auth signup created
    # by the Flutter test. Synthetic SQL fixtures remain in the disposable
    # local database; this script never resets the database automatically.
    try {
      if ($keepImageForFlutter) {
        node scripts/supabase_catalog_local_cleanup.cjs
        if ($LASTEXITCODE -ne 0) { throw 'Local Supabase catalog image fixture cleanup failed.' }
      }
    } finally {
      foreach ($folder in $createdFunctionFolders) {
        $resolved = [System.IO.Path]::GetFullPath($folder)
        $expectedRoot = [System.IO.Path]::GetFullPath((Join-Path $workdir 'supabase\functions'))
        if (-not $resolved.StartsWith($expectedRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
          throw 'Refusing to remove a path outside the isolated temporary function directory.'
        }
        Remove-Item -LiteralPath $resolved -Recurse -Force
      }
      if (Test-Path -LiteralPath $cliProfile) {
        $resolvedProfile = [System.IO.Path]::GetFullPath($cliProfile)
        $expectedWorkdir = [System.IO.Path]::GetFullPath($workdir)
        if (-not $resolvedProfile.StartsWith($expectedWorkdir, [System.StringComparison]::OrdinalIgnoreCase)) {
          throw 'Refusing to remove a CLI profile outside the isolated test workdir.'
        }
        Remove-Item -LiteralPath $resolvedProfile -Recurse -Force
      }
      Remove-Item -LiteralPath $edgeStdout, $edgeStderr -Force -ErrorAction SilentlyContinue
      Write-Output 'Synthetic schema/records remain only in the disposable local database; no database reset was performed.'
    }
  }
} finally {
  foreach ($name in $savedNames) {
    [Environment]::SetEnvironmentVariable($name, $previous[$name], 'Process')
  }
}

param(
  [string]$ApiBaseUrl = 'https://ro-mobileapp.onrender.com',
  [switch]$LocalBackend
)
$ErrorActionPreference = 'Stop'
if ($LocalBackend) {
  $ApiBaseUrl = 'http://10.0.2.2:8081';
  try {
    $policy = (Invoke-RestMethod -Uri 'http://127.0.0.1:8081/api/auth/config' -TimeoutSec 10).dealerPasswordLogin
  } catch {
    throw 'Start the current local backend on port 8081 before using -LocalBackend.'
  }
  if ($policy.requiresAdminApproval -ne $false -or $policy.requiresEmailVerification -ne $true) {
    throw 'Port 8081 is not serving the current verified-dealer login policy. Restart the backend from this project.'
  }
}
Write-Host "Running the emulator against $ApiBaseUrl"
$flutterCommand = Get-Command flutter -ErrorAction SilentlyContinue
$flutterPath = if ($flutterCommand) { $flutterCommand.Source } else { Join-Path $env:LOCALAPPDATA 'FlutterSDK\source\bin\flutter.bat' }
$sdkRoot = Join-Path $env:LOCALAPPDATA 'Android\Sdk'
$env:JAVA_HOME = [Environment]::GetEnvironmentVariable('JAVA_HOME', 'User')
$env:ANDROID_HOME = $sdkRoot
& "$sdkRoot\emulator\emulator.exe" -accel-check
if ($LASTEXITCODE -ne 0) { throw 'Android emulator acceleration is unavailable. Enable CPU virtualization and Windows Hypervisor Platform, then restart Windows.' }
if ((& "$sdkRoot\platform-tools\adb.exe" devices) -notmatch '^emulator-5554\s+device') {
  Start-Process -FilePath "$sdkRoot\emulator\emulator.exe" -ArgumentList @('-avd','RO_Dealer_API_36') -WindowStyle Hidden
}
& "$sdkRoot\platform-tools\adb.exe" -s emulator-5554 wait-for-device
if ($LASTEXITCODE -ne 0) { throw 'Unable to connect to the Android emulator.' }
& $flutterPath run -d emulator-5554 "--dart-define=API_BASE_URL=$ApiBaseUrl"

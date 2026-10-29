param([string]$ApiBaseUrl = 'http://10.0.2.2:8081/api/')
$ErrorActionPreference = 'Stop'
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

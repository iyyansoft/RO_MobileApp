$ErrorActionPreference = 'Stop'
$sdkRoot = Join-Path $env:LOCALAPPDATA 'Android\Sdk'
$flutterRoot = Join-Path $env:LOCALAPPDATA 'FlutterSDK\source'
$javaLocation = 'C:\Program Files\Android\Android Studio\jbr'
if (!(Test-Path "$javaLocation\bin\java.exe")) {
  $javaLocation = [Environment]::GetEnvironmentVariable('JAVA_HOME', 'User')
}
$env:JAVA_HOME = $javaLocation
$env:ANDROID_HOME = $sdkRoot
$sdkManager = Join-Path $sdkRoot 'cmdline-tools\latest\bin\sdkmanager.bat'
$avdManager = Join-Path $sdkRoot 'cmdline-tools\latest\bin\avdmanager.bat'
if (!(Test-Path $sdkManager)) { throw 'Install Android SDK command-line tools first.' }
if (!(Test-Path "$env:JAVA_HOME\bin\java.exe")) { throw 'Install Android Studio first.' }
[Environment]::SetEnvironmentVariable('ANDROID_HOME', $sdkRoot, 'User')
1..100 | ForEach-Object { 'y' } | & $sdkManager "--sdk_root=$sdkRoot" --licenses
& $sdkManager "--sdk_root=$sdkRoot" 'platform-tools' 'emulator' 'platforms;android-36' 'build-tools;36.0.0' 'system-images;android-36;google_apis;x86_64'
if ($LASTEXITCODE -ne 0) { throw 'Android SDK package installation failed.' }
'no' | & $avdManager create avd --name RO_Dealer_API_36 --package 'system-images;android-36;google_apis;x86_64' --device pixel_6 --force
if ($LASTEXITCODE -ne 0) { throw 'Android virtual device creation failed.' }
& "$flutterRoot\bin\flutter.bat" config --android-sdk $sdkRoot
& "$flutterRoot\bin\flutter.bat" doctor -v

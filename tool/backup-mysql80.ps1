$ErrorActionPreference = 'Stop'
$workspacePath = Split-Path -Parent $PSScriptRoot
$statusPath = Join-Path $workspacePath 'build\mysql-backup-status.json'
$serviceName = 'MySQL80'
$configPath = 'C:\ProgramData\MySQL\MySQL Server 8.0\my.ini'
$dataPath = 'C:\ProgramData\MySQL\MySQL Server 8.0\Data'
$backupBase = 'C:\Users\priya\AppData\Local\ROMySQLRecovery'
$backupPath = Join-Path $backupBase ('backup-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
$snapshotId = $null
function Status($phase, $extra = @{}) {
  $result = [ordered]@{ phase=$phase; verified=$false; filesVerified=$false; restoreVerified=$false; backupPath=$backupPath; method='live-VSS-snapshot' }
  foreach ($key in $extra.Keys) { $result[$key] = $extra[$key] }
  $result | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $statusPath -Encoding UTF8
}
try {
  Status 'checking'
  $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
  $principal = New-Object Security.Principal.WindowsPrincipal($identity)
  if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'ADMINISTRATOR_REQUIRED' }
  $service = Get-CimInstance Win32_Service -Filter "Name='MySQL80'"
  if ($service.PathName -notlike '*MySQL Server 8.0*my.ini*') { throw 'UNEXPECTED_SERVICE_CONFIGURATION' }
  $config = [IO.File]::ReadAllText($configPath)
  if ($config -notmatch '(?m)^\s*datadir\s*=\s*["'']?C:[/\\]ProgramData[/\\]MySQL[/\\]MySQL Server 8\.0[/\\]Data["'']?\s*$') { throw 'UNEXPECTED_DATA_DIRECTORY' }
  # Refuse to certify an incomplete backup if storage is configured outside this data directory.
  if ($config -match '(?m)^\s*(innodb_data_home_dir|innodb_log_group_home_dir|innodb_directories|keyring_file_data|early-plugin-load|plugin-load)\s*=') { throw 'EXTERNAL_STORAGE_REQUIRES_BACKUP_REVIEW' }
  if ((Get-ChildItem -LiteralPath $dataPath -Recurse -Force -File | Where-Object { $_.Extension -eq '.isl' }).Count) { throw 'EXTERNAL_TABLESPACE_REQUIRES_BACKUP_REVIEW' }
  $estimatedBytes = (Get-ChildItem -LiteralPath $dataPath -Recurse -Force -File | Measure-Object Length -Sum).Sum
  $freeBytes = (Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'").FreeSpace
  if ($freeBytes -lt ($estimatedBytes * 2 + 1GB)) { throw 'INSUFFICIENT_BACKUP_SPACE' }
  New-Item -ItemType Directory -Path $backupPath | Out-Null
  $acl = New-Object Security.AccessControl.DirectorySecurity
  $acl.SetAccessRuleProtection($true, $false)
  foreach ($sid in @('S-1-5-18','S-1-5-32-544',$identity.User.Value)) {
    $rule = New-Object Security.AccessControl.FileSystemAccessRule((New-Object Security.Principal.SecurityIdentifier($sid)), 'FullControl', 'ContainerInherit,ObjectInherit', 'None', 'Allow')
    $acl.AddAccessRule($rule)
  }
  Set-Acl -LiteralPath $backupPath -AclObject $acl
  # Latest user instruction forbids stopping MySQL. Capture immutable files via VSS.
  # Hash verification alone is NOT a database restore test and cannot authorize a reset.
  Status 'creating-live-snapshot'
  $creation = Invoke-CimMethod -ClassName Win32_ShadowCopy -MethodName Create -Arguments @{Volume='C:\';Context='ClientAccessible'}
  if ($creation.ReturnValue -ne 0) { throw ('VSS_CREATE_FAILED_' + $creation.ReturnValue) }
  $snapshotId = $creation.ShadowID
  $snapshot = Get-CimInstance Win32_ShadowCopy | Where-Object { $_.ID -eq $snapshotId }
  if (-not $snapshot.DeviceObject) { throw 'VSS_SNAPSHOT_NOT_FOUND' }
  $mountPath = Join-Path $backupPath 'SnapshotSource'
  # PowerShell's provider cannot resolve GLOBALROOT; create the directory link through Win32.
  Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class MySQLBackupLink {
  [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
  [return: MarshalAs(UnmanagedType.I1)]
  public static extern bool CreateSymbolicLink(string link, string target, uint flags);
}
'@
  if (-not [MySQLBackupLink]::CreateSymbolicLink($mountPath, $snapshot.DeviceObject + '\', 1)) { throw ('SNAPSHOT_LINK_FAILED_' + [Runtime.InteropServices.Marshal]::GetLastWin32Error()) }
  $snapshotDataPath = Join-Path $mountPath $dataPath.Substring(3)
  $snapshotConfigPath = Join-Path $mountPath $configPath.Substring(3)
  Status 'copying'
  Copy-Item -LiteralPath $snapshotDataPath -Destination (Join-Path $backupPath 'Data') -Recurse -Force
  Copy-Item -LiteralPath $snapshotConfigPath -Destination (Join-Path $backupPath 'my.ini')
  Status 'verifying'
  $sourceFiles = @(Get-ChildItem -LiteralPath $snapshotDataPath -Recurse -Force -File)
  $destinationFiles = @(Get-ChildItem -LiteralPath (Join-Path $backupPath 'Data') -Recurse -Force -File)
  if ($sourceFiles.Count -ne $destinationFiles.Count) { throw 'BACKUP_FILE_COUNT_MISMATCH' }
  $manifest = @()
  foreach ($file in $sourceFiles) {
    $relativePath = $file.FullName.Substring($snapshotDataPath.Length + 1)
    $destination = Join-Path (Join-Path $backupPath 'Data') $relativePath
    if ((Get-Item -LiteralPath $destination -Force).Length -ne $file.Length) { throw 'BACKUP_FILE_SIZE_MISMATCH' }
    $sourceHash = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash
    if ((Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash -ne $sourceHash) { throw 'BACKUP_FILE_HASH_MISMATCH' }
    $manifest += [ordered]@{path=$relativePath;bytes=$file.Length;sha256=$sourceHash}
  }
  $configHash = (Get-FileHash -LiteralPath $snapshotConfigPath -Algorithm SHA256).Hash
  if ((Get-FileHash -LiteralPath (Join-Path $backupPath 'my.ini') -Algorithm SHA256).Hash -ne $configHash) { throw 'BACKUP_CONFIG_HASH_MISMATCH' }
  $manifest | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $backupPath 'manifest.json') -Encoding UTF8
  $summary = [ordered]@{verified=$false;filesVerified=$true;restoreVerified=$false;snapshotId=$snapshotId;fileCount=$sourceFiles.Count;bytes=($sourceFiles | Measure-Object Length -Sum).Sum;configSha256=$configHash;sourceDataPath=$dataPath;verifiedAt=(Get-Date).ToUniversalTime().ToString('o');note='Live snapshot files match SHA-256 hashes. Database restore validation is still required before any reset.'}
  $summary | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $backupPath 'file-verification.json') -Encoding UTF8
  Status 'files-verified-reset-blocked' @{filesVerified=$true;fileCount=$summary.fileCount;bytes=$summary.bytes;verifiedAt=$summary.verifiedAt;snapshotId=$snapshotId}
} catch {
  Status 'failed' @{code=$_.Exception.Message}
}

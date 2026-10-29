$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Security
$vaultPath = Join-Path $env:APPDATA 'MySQL\Workbench\workbench_user_data.dat'
if (-not (Test-Path -LiteralPath $vaultPath)) { Write-Output '{"vaultExists":false}'; exit }
$encrypted = $null
$plain = $null
try {
  $encrypted = [System.IO.File]::ReadAllBytes($vaultPath)
  $plain = [System.Security.Cryptography.ProtectedData]::Unprotect($encrypted, $null, [System.Security.Cryptography.DataProtectionScope]::CurrentUser)
  $vaultText = [System.Text.Encoding]::UTF8.GetString($plain).TrimEnd([char]0)
  $entryCount = 0
  foreach ($entry in ($vaultText -split "`n")) {
    $separator = $entry.IndexOf([char]3)
    if ($separator -lt 0) { continue }
    $identity = $entry.Substring(0, $separator) -split [char]2
    if ($identity.Count -ne 2 -or $identity[1] -ne 'root' -or $identity[0] -notmatch '(localhost|127\.0\.0\.1)') { continue }
    $entryCount++
    $secret = $entry.Substring($separator + 1)
    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = (Get-Command node.exe).Source
    $startInfo.Arguments = '"' + (Join-Path $PSScriptRoot 'check-saved-mysql-credential.cjs') + '"'
    $startInfo.WorkingDirectory = Split-Path -Parent $PSScriptRoot
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardInput = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $child = New-Object System.Diagnostics.Process
    $child.StartInfo = $startInfo
    [void]$child.Start()
    $child.StandardInput.WriteLine((@{password=$secret} | ConvertTo-Json -Compress))
    $child.StandardInput.Close()
    $secret = $null
    $result = $child.StandardOutput.ReadToEnd() | ConvertFrom-Json
    $child.WaitForExit()
    $child.Dispose()
    [ordered]@{localRootVaultEntry=$entryCount;result=$result} | ConvertTo-Json -Compress
  }
  [ordered]@{vaultExists=$true;vaultReadable=$true;localRootEntries=$entryCount} | ConvertTo-Json -Compress
} catch {
  Write-Output '{"vaultExists":true,"vaultReadable":false,"code":"VAULT_CHECK_FAILED"}'
} finally {
  if ($plain) { [Array]::Clear($plain, 0, $plain.Length) }
  $vaultText = $null; $secret = $null; $entry = $null
}

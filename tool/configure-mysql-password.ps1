$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
$workspacePath = Split-Path -Parent $PSScriptRoot
$nodePath = (Get-Command node.exe).Source
$form = New-Object System.Windows.Forms.Form
$form.Text = 'Verify existing MySQL80 password'
$form.Size = New-Object System.Drawing.Size(460, 260)
$form.StartPosition = 'CenterScreen'
$form.TopMost = $true
$form.FormBorderStyle = 'FixedDialog'
$form.MaximizeBox = $false
$label = New-Object System.Windows.Forms.Label
$label.Text = "Enter the existing root password for MySQL80 on port 3306.`r`nIt is verified before saving to the app's .env.`r`nThe password is never displayed in chat or logs."
$label.Location = New-Object System.Drawing.Point(20, 20)
$label.Size = New-Object System.Drawing.Size(410, 65)
$passwordBox = New-Object System.Windows.Forms.TextBox
$passwordBox.UseSystemPasswordChar = $true
$passwordBox.Location = New-Object System.Drawing.Point(20, 95)
$passwordBox.Width = 405
$button = New-Object System.Windows.Forms.Button
$button.Text = 'Verify and save'
$button.Location = New-Object System.Drawing.Point(20, 140)
$button.Width = 150
$status = New-Object System.Windows.Forms.Label
$status.Location = New-Object System.Drawing.Point(20, 177)
$status.Size = New-Object System.Drawing.Size(410, 40)
$button.Add_Click({
  $button.Enabled = $false
  $status.Text = 'Verifying existing credentials...'
  $form.Refresh()
  try {
    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = $nodePath
    $startInfo.Arguments = '"' + (Join-Path $PSScriptRoot 'configure-mysql-password.cjs') + '"'
    $startInfo.WorkingDirectory = $workspacePath
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardInput = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $child = New-Object System.Diagnostics.Process
    $child.StartInfo = $startInfo
    [void]$child.Start()
    $child.StandardInput.WriteLine((@{password=$passwordBox.Text} | ConvertTo-Json -Compress))
    $child.StandardInput.Close()
    $passwordBox.Clear()
    $result = $child.StandardOutput.ReadToEnd() | ConvertFrom-Json
    $child.WaitForExit()
    $child.Dispose()
    if ($result.configured) {
      [void][System.Windows.Forms.MessageBox]::Show('Authentication verified. The existing password was saved to .env. No database data was changed.', 'MySQL verified')
      $form.Close()
    } else { $status.Text = 'Not saved: ' + $result.code + '. Check the existing password and retry.' }
  } catch { $status.Text = 'Could not verify credentials. No password is displayed.' }
  finally { $button.Enabled = $true }
})
$form.Controls.AddRange(@($label, $passwordBox, $button, $status))
$form.AcceptButton = $button
[void]$form.ShowDialog()
$passwordBox.Clear()
$form.Dispose()

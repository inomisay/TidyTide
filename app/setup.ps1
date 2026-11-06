param([switch]$Uninstall)

Add-Type -AssemblyName System.Windows.Forms

$source  = Split-Path -Parent $MyInvocation.MyCommand.Path
$home2   = Join-Path $env:LOCALAPPDATA 'TidyTide'
$links = @(
    (Join-Path ([Environment]::GetFolderPath('Desktop'))  'Tidy Tide.lnk'),
    (Join-Path ([Environment]::GetFolderPath('Programs')) 'Tidy Tide.lnk'),
    (Join-Path ([Environment]::GetFolderPath('SendTo'))   'Tidy Tide.lnk')
)

if ($Uninstall) {
    foreach ($l in $links) { Remove-Item -LiteralPath $l -Force -ErrorAction SilentlyContinue }
    Remove-Item -LiteralPath $home2 -Recurse -Force -ErrorAction SilentlyContinue
    [void][System.Windows.Forms.MessageBox]::Show('Tidy Tide has been removed.', 'Tidy Tide')
    return
}

# ---------- show the licence before installing ----------
$licensePath = Join-Path (Split-Path -Parent $source) 'LICENSE'
if (Test-Path -LiteralPath $licensePath) {
    Add-Type -AssemblyName System.Drawing
    [System.Windows.Forms.Application]::EnableVisualStyles()

    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = 'Tidy Tide - Licence'
    $dlg.ClientSize = New-Object System.Drawing.Size(640, 520)
    $dlg.StartPosition = 'CenterScreen'
    $dlg.FormBorderStyle = 'FixedDialog'
    $dlg.MaximizeBox = $false
    $dlg.MinimizeBox = $false
    $dlg.Font = New-Object System.Drawing.Font('Segoe UI', 10)
    $dlg.BackColor = [System.Drawing.Color]::White
    $ico = Join-Path $source 'TidyTide.ico'
    if (Test-Path -LiteralPath $ico) { $dlg.Icon = New-Object System.Drawing.Icon($ico) }

    $intro = New-Object System.Windows.Forms.Label
    $intro.Location = New-Object System.Drawing.Point(16, 14)
    $intro.Size = New-Object System.Drawing.Size(608, 44)
    $intro.ForeColor = [System.Drawing.ColorTranslator]::FromHtml('#12324A')
    $intro.Text = "Tidy Tide is free software, made by Yasamin Valishariatpanahi and released under the GNU General Public License v3. Please read the licence, then click Install."

    $box = New-Object System.Windows.Forms.TextBox
    $box.Location = New-Object System.Drawing.Point(16, 64)
    $box.Size = New-Object System.Drawing.Size(608, 396)
    $box.Multiline = $true
    $box.ReadOnly = $true
    $box.ScrollBars = 'Vertical'
    $box.BackColor = [System.Drawing.ColorTranslator]::FromHtml('#F4FAFD')
    $box.Font = New-Object System.Drawing.Font('Consolas', 9)
    $box.Text = (Get-Content -LiteralPath $licensePath -Raw) -replace "`r?`n", "`r`n"

    $ok = New-Object System.Windows.Forms.Button
    $ok.Text = 'Install'
    $ok.Size = New-Object System.Drawing.Size(110, 34)
    $ok.Location = New-Object System.Drawing.Point(392, 474)
    $ok.DialogResult = [System.Windows.Forms.DialogResult]::OK

    $cancel = New-Object System.Windows.Forms.Button
    $cancel.Text = 'Cancel'
    $cancel.Size = New-Object System.Drawing.Size(110, 34)
    $cancel.Location = New-Object System.Drawing.Point(514, 474)
    $cancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel

    $dlg.Controls.AddRange(@($intro, $box, $ok, $cancel))
    $dlg.AcceptButton = $ok
    $dlg.CancelButton = $cancel
    $dlg.Add_Shown({ $box.SelectionLength = 0; $ok.Focus() })

    $answer = $dlg.ShowDialog()
    $dlg.Dispose()
    if ($answer -ne [System.Windows.Forms.DialogResult]::OK) { return }
}

New-Item -ItemType Directory -Path $home2 -Force | Out-Null
foreach ($f in 'TidyTide.ps1', 'TidyTide.ico') {
    Copy-Item -LiteralPath (Join-Path $source $f) -Destination $home2 -Force
}
if (Test-Path -LiteralPath $licensePath) {
    Copy-Item -LiteralPath $licensePath -Destination (Join-Path $home2 'LICENSE.txt') -Force
}
Get-ChildItem -LiteralPath $home2 | Unblock-File -ErrorAction SilentlyContinue

$shell = New-Object -ComObject WScript.Shell
$ps = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$app = Join-Path $home2 'TidyTide.ps1'
foreach ($l in $links) {
    $s = $shell.CreateShortcut($l)
    $s.TargetPath = $ps
    $s.Arguments = "-NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File `"$app`""
    $s.WorkingDirectory = $home2
    $s.IconLocation = (Join-Path $home2 'TidyTide.ico') + ',0'
    $s.WindowStyle = 7
    $s.Description = 'Clean up (1) (2) (3) file names'
    $s.Save()
}

$msg = "Tidy Tide is installed!`r`n`r`n" +
       "Open it from the desktop icon or the Start menu.`r`n`r`n" +
       "Shortcut: right-click files or a folder, then Send to > Tidy Tide.`r`n" +
       "(On Windows 11, Send to is under 'Show more options'.)"
[void][System.Windows.Forms.MessageBox]::Show($msg, 'Tidy Tide')

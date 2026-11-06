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

New-Item -ItemType Directory -Path $home2 -Force | Out-Null
foreach ($f in 'TidyTide.ps1', 'TidyTide.ico') {
    Copy-Item -LiteralPath (Join-Path $source $f) -Destination $home2 -Force
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

# Tidy Tide setup
# Installs (or with -Uninstall, removes) Tidy Tide for the current user.
# No admin rights needed: everything goes into %LOCALAPPDATA%\TidyTide plus three shortcuts.

param([switch]$Uninstall)

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

$source      = Split-Path -Parent $MyInvocation.MyCommand.Path
$home2       = Join-Path $env:LOCALAPPDATA 'TidyTide'
$licensePath = Join-Path (Split-Path -Parent $source) 'LICENSE'
$icoPath     = Join-Path $source 'TidyTide.ico'
$psExe       = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$appPath     = Join-Path $home2 'TidyTide.ps1'
$appArgs     = "-NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File `"$appPath`""

$desktopLink  = Join-Path ([Environment]::GetFolderPath('Desktop'))  'Tidy Tide.lnk'
$programsLink = Join-Path ([Environment]::GetFolderPath('Programs')) 'Tidy Tide.lnk'
$sendToLink   = Join-Path ([Environment]::GetFolderPath('SendTo'))   'Tidy Tide.lnk'

# ---------- colours and fonts (same as the app) ----------
function C([string]$hex) { [System.Drawing.ColorTranslator]::FromHtml($hex) }
$cDeep   = C '#0A4D7C'
$cSea    = C '#1C8FC7'
$cSeaHi  = C '#2AA3DB'
$cAqua   = C '#4FC3E8'
$cFoam   = C '#EAF6FB'
$cMist   = C '#D6EEF8'
$cMistHi = C '#C4E6F5'
$cInk    = C '#12324A'
$cSoft   = C '#4C6D86'
$cGray   = C '#8AA3B5'
$cTeal   = C '#12917F'
$cCoral  = C '#E07A5F'
$cWhite  = [System.Drawing.Color]::White

$fTitle    = New-Object System.Drawing.Font('Segoe UI Semibold', 20)
$fSub      = New-Object System.Drawing.Font('Segoe UI', 10)
$fButton   = New-Object System.Drawing.Font('Segoe UI Semibold', 10)
$fBig      = New-Object System.Drawing.Font('Segoe UI Semibold', 14)
$fBody     = New-Object System.Drawing.Font('Segoe UI', 10)
$fBodyBold = New-Object System.Drawing.Font('Segoe UI Semibold', 10)
$fMono     = New-Object System.Drawing.Font('Consolas', 8.5)

$centerFlags = [System.Windows.Forms.TextFormatFlags]'HorizontalCenter, VerticalCenter, SingleLine, NoPrefix'
$CHECK = [string][char]0x2713

# ---------- drawing helpers ----------
function New-RoundPath([float]$x, [float]$y, [float]$w, [float]$h, [float]$r) {
    $p = New-Object System.Drawing.Drawing2D.GraphicsPath
    [float]$d = [Math]::Min($r * 2, [Math]::Min($w, $h))
    $p.AddArc([float]$x, [float]$y, $d, $d, [float]180, [float]90)
    $p.AddArc([float]($x + $w - $d), [float]$y, $d, $d, [float]270, [float]90)
    $p.AddArc([float]($x + $w - $d), [float]($y + $h - $d), $d, $d, [float]0, [float]90)
    $p.AddArc([float]$x, [float]($y + $h - $d), $d, $d, [float]90, [float]90)
    $p.CloseFigure()
    return $p
}

function Set-DoubleBuffered($control) {
    $flags = [System.Reflection.BindingFlags]'Instance, NonPublic'
    $control.GetType().GetProperty('DoubleBuffered', $flags).SetValue($control, $true, $null)
}

function New-PillButton([string]$text, $back, $hover, $fore, [int]$width) {
    $b = New-Object System.Windows.Forms.Button
    $b.Text = $text
    $b.Size = New-Object System.Drawing.Size($width, 40)
    $b.FlatStyle = 'Flat'
    $b.FlatAppearance.BorderSize = 0
    $b.Cursor = [System.Windows.Forms.Cursors]::Hand
    $b.Font = $fButton
    $b.Tag = @{ Back = $back; Hover = $hover; Fore = $fore; Over = $false }
    $b.Add_MouseEnter({ $this.Tag.Over = $true;  $this.Invalidate() })
    $b.Add_MouseLeave({ $this.Tag.Over = $false; $this.Invalidate() })
    $b.Add_Paint({
        param($s, $e)
        $g = $e.Graphics
        $g.SmoothingMode = 'AntiAlias'
        $g.Clear($s.Parent.BackColor)
        $t = $s.Tag
        $fill = if ($t.Over) { $t.Hover } else { $t.Back }
        $path = New-RoundPath 0 0 ($s.Width - 1) ($s.Height - 1) (($s.Height - 1) / 2)
        $brush = New-Object System.Drawing.SolidBrush($fill)
        $g.FillPath($brush, $path)
        if ($s.Focused -and $s.ShowFocusCues) {
            $pen = New-Object System.Drawing.Pen($cAqua, [float]2)
            $g.DrawPath($pen, $path); $pen.Dispose()
        }
        $brush.Dispose(); $path.Dispose()
        [System.Windows.Forms.TextRenderer]::DrawText($g, $s.Text, $s.Font, $s.ClientRectangle, $t.Fore, $centerFlags)
    })
    return $b
}

function New-Label([string]$text, [int]$x, [int]$y, [int]$w, [int]$h, $font, $color, $back) {
    $l = New-Object System.Windows.Forms.Label
    $l.Text = $text
    $l.Location = New-Object System.Drawing.Point($x, $y)
    $l.Size = New-Object System.Drawing.Size($w, $h)
    $l.Font = $font
    $l.ForeColor = $color
    $l.BackColor = $back
    $l.UseMnemonic = $false
    return $l
}

# white rounded card
function New-Card([int]$x, [int]$y, [int]$w, [int]$h) {
    $p = New-Object System.Windows.Forms.Panel
    $p.Location = New-Object System.Drawing.Point($x, $y)
    $p.Size = New-Object System.Drawing.Size($w, $h)
    $p.BackColor = $cFoam
    Set-DoubleBuffered $p
    $p.Add_Paint({
        param($s, $e)
        $g = $e.Graphics
        $g.SmoothingMode = 'AntiAlias'
        $path = New-RoundPath 0 0 ($s.Width - 1) ($s.Height - 1) 16
        $brush = New-Object System.Drawing.SolidBrush($cWhite)
        $pen = New-Object System.Drawing.Pen($cMist, [float]1.5)
        $g.FillPath($brush, $path); $g.DrawPath($pen, $path)
        $brush.Dispose(); $pen.Dispose(); $path.Dispose()
    })
    return $p
}

# a row inside a card: small coloured mark + text
function Add-CardLine($card, [string]$mark, $markColor, [string]$text, [int]$y) {
    $card.Controls.Add((New-Label $mark 18 $y 26 24 $fBodyBold $markColor $cWhite))
    $card.Controls.Add((New-Label $text 44 $y ($card.Width - 60) 24 $fBody $cInk $cWhite))
}

function New-CheckBox([string]$text, [int]$x, [int]$y, [bool]$checked) {
    $c = New-Object System.Windows.Forms.CheckBox
    $c.Text = $text
    $c.Location = New-Object System.Drawing.Point($x, $y)
    $c.AutoSize = $true
    $c.Checked = $checked
    $c.ForeColor = $cInk
    $c.BackColor = $cFoam
    $c.Cursor = [System.Windows.Forms.Cursors]::Hand
    return $c
}

# big round badge with a check (or "!" on failure)
function New-Badge([int]$x, [int]$y) {
    $p = New-Object System.Windows.Forms.Panel
    $p.Location = New-Object System.Drawing.Point($x, $y)
    $p.Size = New-Object System.Drawing.Size(60, 60)
    $p.BackColor = $cFoam
    $p.Tag = @{ Ok = $true }
    Set-DoubleBuffered $p
    $p.Add_Paint({
        param($s, $e)
        $g = $e.Graphics
        $g.SmoothingMode = 'AntiAlias'
        $col = if ($s.Tag.Ok) { $cTeal } else { $cCoral }
        $b = New-Object System.Drawing.SolidBrush($col)
        $g.FillEllipse($b, 1, 1, 57, 57); $b.Dispose()
        $pen = New-Object System.Drawing.Pen($cWhite, [float]5)
        $pen.StartCap = 'Round'; $pen.EndCap = 'Round'; $pen.LineJoin = 'Round'
        if ($s.Tag.Ok) {
            $g.DrawLines($pen, [System.Drawing.PointF[]]@(
                (New-Object System.Drawing.PointF(18, 31)),
                (New-Object System.Drawing.PointF(26, 39)),
                (New-Object System.Drawing.PointF(42, 22))))
        } else {
            $g.DrawLine($pen, 30, 17, 30, 34)
            $g.DrawLine($pen, 30, 43, 30, 43.5)
        }
        $pen.Dispose()
    })
    return $p
}

# ---------- window ----------
$form = New-Object System.Windows.Forms.Form
$form.Text = if ($Uninstall) { 'Uninstall Tidy Tide' } else { 'Install Tidy Tide' }
$form.ClientSize = New-Object System.Drawing.Size(600, 500)
$form.FormBorderStyle = 'FixedSingle'
$form.MaximizeBox = $false
$form.StartPosition = 'CenterScreen'
$form.BackColor = $cFoam
$form.Font = $fBody
if (Test-Path -LiteralPath $icoPath) { $form.Icon = New-Object System.Drawing.Icon($icoPath) }

$script:title = ''
$script:sub = ''

$header = New-Object System.Windows.Forms.Panel
$header.Dock = 'Top'
$header.Height = 118
Set-DoubleBuffered $header
$header.Add_Paint({
    param($s, $e)
    $w = $s.Width; $h = $s.Height
    $g = $e.Graphics
    $g.SmoothingMode = 'AntiAlias'
    $grad = New-Object System.Drawing.Drawing2D.LinearGradientBrush($s.ClientRectangle, $cDeep, $cAqua, [float]0)
    $g.FillRectangle($grad, $s.ClientRectangle); $grad.Dispose()

    $p1 = New-Object System.Drawing.Drawing2D.GraphicsPath
    $p1.AddBezier([float]0, [float]($h - 26), [float]($w * 0.3), [float]($h - 62), [float]($w * 0.55), [float]($h - 2), [float]$w, [float]($h - 40))
    $p1.AddLine([float]$w, [float]($h - 40), [float]$w, [float]$h)
    $p1.AddLine([float]$w, [float]$h, [float]0, [float]$h)
    $p1.CloseFigure()
    $b1 = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(70, 255, 255, 255))
    $g.FillPath($b1, $p1)

    $p2 = New-Object System.Drawing.Drawing2D.GraphicsPath
    $p2.AddBezier([float]0, [float]($h - 12), [float]($w * 0.35), [float]($h - 34), [float]($w * 0.65), [float]($h + 6), [float]$w, [float]($h - 18))
    $p2.AddLine([float]$w, [float]($h - 18), [float]$w, [float]$h)
    $p2.AddLine([float]$w, [float]$h, [float]0, [float]$h)
    $p2.CloseFigure()
    $b2 = New-Object System.Drawing.SolidBrush($cFoam)
    $g.FillPath($b2, $p2)

    $pen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(150, 255, 255, 255), [float]2.5)
    $g.DrawEllipse($pen, [float]($w - 110), [float]20, [float]28, [float]28)
    $g.DrawEllipse($pen, [float]($w - 70), [float]12, [float]13, [float]13)
    $g.DrawEllipse($pen, [float]($w - 146), [float]44, [float]10, [float]10)
    $b1.Dispose(); $b2.Dispose(); $pen.Dispose(); $p1.Dispose(); $p2.Dispose()

    [System.Windows.Forms.TextRenderer]::DrawText($g, $script:title, $fTitle, (New-Object System.Drawing.Point(26, 14)), $cWhite)
    [System.Windows.Forms.TextRenderer]::DrawText($g, $script:sub, $fSub, (New-Object System.Drawing.Point(30, 54)), (C '#DDF1FA'))
})

$footer = New-Object System.Windows.Forms.Panel
$footer.Dock = 'Bottom'
$footer.Height = 72
$footer.BackColor = $cFoam

$btnPrimary = New-PillButton 'Next'   $cDeep $cSea    $cWhite 130
$btnBack    = New-PillButton 'Back'   $cMist $cMistHi $cDeep  100
$btnCancel  = New-PillButton 'Cancel' $cMist $cMistHi $cDeep  100
$btnPrimary.Location = New-Object System.Drawing.Point(446, 14)
$btnBack.Location    = New-Object System.Drawing.Point(336, 14)
$btnCancel.Location  = New-Object System.Drawing.Point(26, 14)
$footer.Controls.AddRange(@($btnPrimary, $btnBack, $btnCancel))

$content = New-Object System.Windows.Forms.Panel
$content.Dock = 'Fill'
$content.BackColor = $cFoam

function New-Page {
    $p = New-Object System.Windows.Forms.Panel
    $p.Dock = 'Fill'
    $p.BackColor = $cFoam
    $p.Visible = $false
    $content.Controls.Add($p)
    return $p
}

# ---------- install pages ----------
$pgWelcome = New-Page
$pgWelcome.Controls.Add((New-Label "Tidy Tide turns  photo (12).jpg  into  12.jpg. Setup takes a few seconds and doesn't need administrator rights." 28 6 544 44 $fBody $cSoft $cFoam))
$cardWelcome = New-Card 28 58 544 140
$cardWelcome.Controls.Add((New-Label 'What setup will do' 18 14 400 24 $fBodyBold $cDeep $cWhite))
Add-CardLine $cardWelcome $CHECK $cTeal 'Copy Tidy Tide to your user folder  (AppData\Local\TidyTide)' 46
Add-CardLine $cardWelcome $CHECK $cTeal 'Add it to the Start menu and to the right-click Send to menu' 74
Add-CardLine $cardWelcome $CHECK $cTeal "Leave your files alone. Nothing is renamed until you press Rename" 102
$pgWelcome.Controls.Add($cardWelcome)
$chkDesktop = New-CheckBox 'Put a Tidy Tide shortcut on my desktop' 30 214 $true
$pgWelcome.Controls.Add($chkDesktop)
$pgWelcome.Controls.Add((New-Label 'Made by Yasamin Valishariatpanahi  ·  Free software under GPL-3.0' 30 262 540 22 $fSub $cGray $cFoam))

$pgLicence = New-Page
$pgLicence.Controls.Add((New-Label "Tidy Tide is free software under the GNU General Public License v3. You don't have to accept it to use the app. It explains what you may do if you share or change it." 28 6 544 44 $fBody $cSoft $cFoam))
$cardLicence = New-Card 28 58 544 238
$licenceBox = New-Object System.Windows.Forms.TextBox
$licenceBox.Multiline = $true
$licenceBox.ReadOnly = $true
$licenceBox.WordWrap = $false
$licenceBox.ScrollBars = 'Vertical'
$licenceBox.BorderStyle = 'None'
$licenceBox.BackColor = $cWhite
$licenceBox.ForeColor = $cInk
$licenceBox.Font = $fMono
$licenceBox.Location = New-Object System.Drawing.Point(16, 12)
$licenceBox.Size = New-Object System.Drawing.Size(516, 214)
$licenceBox.Text = if (Test-Path -LiteralPath $licensePath) {
    (Get-Content -LiteralPath $licensePath -Raw) -replace "`r?`n", "`r`n"
} else {
    'GNU General Public License v3.0. Full text: https://www.gnu.org/licenses/gpl-3.0.txt'
}
$cardLicence.Controls.Add($licenceBox)
$pgLicence.Controls.Add($cardLicence)

$pgDone = New-Page
$badge = New-Badge 28 8
$pgDone.Controls.Add($badge)
$lblDoneTitle = New-Label 'Tidy Tide is ready!' 102 10 470 30 $fBig $cInk $cFoam
$lblDoneSub   = New-Label "Here's how to use it:" 104 42 470 24 $fBody $cSoft $cFoam
$pgDone.Controls.AddRange(@($lblDoneTitle, $lblDoneSub))
$cardDone = New-Card 28 86 544 140
Add-CardLine $cardDone '1' $cSea 'Open Tidy Tide from the Start menu or the desktop icon.' 16
Add-CardLine $cardDone '2' $cSea 'Or right-click files or a folder, then Send to > Tidy Tide.' 44
$cardDone.Controls.Add((New-Label "On Windows 11, Send to is under 'Show more options'." 44 68 480 22 $fSub $cGray $cWhite))
Add-CardLine $cardDone '3' $cSea 'Check the preview, then press Rename. Undo is there if you need it.' 100
$pgDone.Controls.Add($cardDone)
$chkOpen = New-CheckBox 'Open Tidy Tide now' 30 242 $true
$pgDone.Controls.Add($chkOpen)

# ---------- uninstall pages ----------
$pgRemove = New-Page
$pgRemove.Controls.Add((New-Label "This removes Tidy Tide from this computer. Your own files are not touched, including any you renamed." 28 6 544 44 $fBody $cSoft $cFoam))
$cardRemove = New-Card 28 58 544 112
$cardRemove.Controls.Add((New-Label 'What will be removed' 18 14 400 24 $fBodyBold $cDeep $cWhite))
Add-CardLine $cardRemove ([string][char]0x2022) $cCoral 'The app folder in AppData\Local\TidyTide' 46
Add-CardLine $cardRemove ([string][char]0x2022) $cCoral 'The desktop, Start menu and Send to shortcuts' 74
$pgRemove.Controls.Add($cardRemove)

$pgRemoved = New-Page
$badge2 = New-Badge 28 8
$pgRemoved.Controls.Add($badge2)
$lblRemovedTitle = New-Label 'Tidy Tide has been removed' 102 10 470 30 $fBig $cInk $cFoam
$lblRemovedSub   = New-Label 'Thanks for trying it! You can install it again any time.' 104 42 470 24 $fBody $cSoft $cFoam
$pgRemoved.Controls.AddRange(@($lblRemovedTitle, $lblRemovedSub))

$form.Controls.Add($content)
$form.Controls.Add($footer)
$form.Controls.Add($header)
$content.BringToFront()

# ---------- actions ----------
function Invoke-Install {
    try {
        New-Item -ItemType Directory -Path $home2 -Force -ErrorAction Stop | Out-Null
        foreach ($f in 'TidyTide.ps1', 'TidyTide.ico') {
            Copy-Item -LiteralPath (Join-Path $source $f) -Destination $home2 -Force -ErrorAction Stop
        }
        if (Test-Path -LiteralPath $licensePath) {
            Copy-Item -LiteralPath $licensePath -Destination (Join-Path $home2 'LICENSE.txt') -Force -ErrorAction Stop
        }
        Get-ChildItem -LiteralPath $home2 | Unblock-File -ErrorAction SilentlyContinue

        $want = @($programsLink, $sendToLink)
        if ($chkDesktop.Checked) { $want += $desktopLink }
        else { Remove-Item -LiteralPath $desktopLink -Force -ErrorAction SilentlyContinue }

        $shell = New-Object -ComObject WScript.Shell
        foreach ($l in $want) {
            $s = $shell.CreateShortcut($l)
            $s.TargetPath = $psExe
            $s.Arguments = $appArgs
            $s.WorkingDirectory = $home2
            $s.IconLocation = (Join-Path $home2 'TidyTide.ico') + ',0'
            $s.WindowStyle = 7
            $s.Description = 'Clean up (1) (2) (3) file names'
            $s.Save()
        }
        return $null
    } catch {
        return $_.Exception.Message
    }
}

function Invoke-Remove {
    foreach ($l in @($desktopLink, $programsLink, $sendToLink)) {
        Remove-Item -LiteralPath $l -Force -ErrorAction SilentlyContinue
    }
    Remove-Item -LiteralPath $home2 -Recurse -Force -ErrorAction SilentlyContinue
}

$script:page = ''
function Show-Page([string]$name) {
    $script:page = $name
    foreach ($p in @($pgWelcome, $pgLicence, $pgDone, $pgRemove, $pgRemoved)) { $p.Visible = $false }
    $btnBack.Visible = $false
    $btnCancel.Visible = $true
    switch ($name) {
        'welcome' { $pgWelcome.Visible = $true; $script:title = 'Install Tidy Tide'; $script:sub = 'Step 1 of 3  ·  Welcome'; $btnPrimary.Text = 'Next' }
        'licence' { $pgLicence.Visible = $true; $script:title = 'Licence';           $script:sub = 'Step 2 of 3  ·  Please read';  $btnPrimary.Text = 'Install'; $btnBack.Visible = $true }
        'done'    { $pgDone.Visible = $true;    $script:title = 'All done';          $script:sub = 'Step 3 of 3  ·  Finished';     $btnPrimary.Text = 'Finish';  $btnCancel.Visible = $false }
        'remove'  { $pgRemove.Visible = $true;  $script:title = 'Uninstall Tidy Tide'; $script:sub = 'Remove the app and its shortcuts'; $btnPrimary.Text = 'Uninstall' }
        'removed' { $pgRemoved.Visible = $true; $script:title = 'Goodbye for now';   $script:sub = 'Tidy Tide was removed';        $btnPrimary.Text = 'Close';   $btnCancel.Visible = $false }
    }
    $header.Invalidate()
    $btnPrimary.Invalidate()
    $btnPrimary.Focus()
}

$btnPrimary.Add_Click({
    switch ($script:page) {
        'welcome' { Show-Page 'licence' }
        'licence' {
            $form.UseWaitCursor = $true
            $err = Invoke-Install
            $form.UseWaitCursor = $false
            if ($err) {
                $badge.Tag.Ok = $false
                $lblDoneTitle.Text = 'Something went wrong'
                $lblDoneSub.Text = $err
                $cardDone.Visible = $false
                $chkOpen.Checked = $false
                $chkOpen.Visible = $false
            }
            Show-Page 'done'
            if ($err) { $script:title = 'Setup stopped'; $script:sub = 'Nothing was overwritten'; $header.Invalidate() }
        }
        'done' {
            if ($chkOpen.Checked -and (Test-Path -LiteralPath $appPath)) {
                Start-Process -FilePath $psExe -ArgumentList $appArgs -WorkingDirectory $home2 -WindowStyle Hidden
            }
            $form.Close()
        }
        'remove'  { Invoke-Remove; Show-Page 'removed' }
        'removed' { $form.Close() }
    }
})
$btnBack.Add_Click({ if ($script:page -eq 'licence') { Show-Page 'welcome' } })
$btnCancel.Add_Click({ $form.Close() })
$form.CancelButton = $btnCancel

if ($Uninstall) { Show-Page 'remove' } else { Show-Page 'welcome' }
$form.Add_Shown({ $btnPrimary.Focus() })
[void]$form.ShowDialog()

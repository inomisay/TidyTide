# Tidy Tide setup
# Installs (or with -Uninstall, removes) Tidy Tide for the current user.
# No admin rights needed: everything goes into %LOCALAPPDATA%\TidyTide plus three shortcuts.

param([switch]$Uninstall)

$source = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $source 'ui.ps1')

$home2       = Join-Path $env:LOCALAPPDATA 'TidyTide'
$licensePath = Join-Path (Split-Path -Parent $source) 'LICENSE'
$icoPath     = Join-Path $source 'TidyTide.ico'
$psExe       = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$appPath     = Join-Path $home2 'TidyTide.ps1'
$appArgs     = "-NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File `"$appPath`""
$appFiles    = @('TidyTide.ps1', 'ui.ps1', 'TidyTide.ico')

$desktopLink  = Join-Path ([Environment]::GetFolderPath('Desktop'))  'Tidy Tide.lnk'
$programsLink = Join-Path ([Environment]::GetFolderPath('Programs')) 'Tidy Tide.lnk'
$sendToLink   = Join-Path ([Environment]::GetFolderPath('SendTo'))   'Tidy Tide.lnk'

$fMono = New-Object System.Drawing.Font('Consolas', 8.5)

# ---------- small builders (sizes are given at 100% and scaled with P) ----------
function New-Label([string]$text, [int]$x, [int]$y, [int]$w, [int]$h, $font, $color, $back) {
    $l = New-Object System.Windows.Forms.Label
    $l.Text = $text
    $l.Location = New-Object System.Drawing.Point((P $x), (P $y))
    $l.Size = New-Object System.Drawing.Size((P $w), (P $h))
    $l.Font = $font
    $l.ForeColor = $color
    $l.BackColor = $back
    $l.UseMnemonic = $false
    return $l
}

function Add-Card($page, [int]$x, [int]$y, [int]$w, [int]$h) {
    $c = New-Card
    $c.Location = New-Object System.Drawing.Point((P $x), (P $y))
    $c.Size = New-Object System.Drawing.Size((P $w), (P $h))
    $page.Controls.Add($c)
    return $c
}

function Add-CardLine($card, [string]$mark, $markColor, [string]$text, [int]$y) {
    $card.Controls.Add((New-Label $mark 22 $y 24 24 $fBodyBold $markColor $cCard))
    $card.Controls.Add((New-Label $text 48 $y 520 24 $fBody $cInk $cCard))
}

function Add-Toggle($page, [string]$text, [int]$x, [int]$y, [bool]$checked) {
    $t = New-Toggle $text
    $t.Location = New-Object System.Drawing.Point((P $x), (P $y))
    $t.Checked = $checked
    $page.Controls.Add($t)
    return $t
}

# big round badge with a check, or "!" when something went wrong
function New-Badge([int]$x, [int]$y) {
    $p = New-Object System.Windows.Forms.Panel
    $p.Location = New-Object System.Drawing.Point((P $x), (P $y))
    $p.Size = New-Object System.Drawing.Size((P 60), (P 60))
    $p.BackColor = $cBg
    $p.Tag = @{ Ok = $true }
    Set-DoubleBuffered $p
    $p.Add_Paint({
        param($s, $e)
        $g = $e.Graphics
        $g.SmoothingMode = 'AntiAlias'
        $ok = $s.Tag.Ok
        $ring = New-Object System.Drawing.SolidBrush($(if ($ok) { $cMintBg } else { $cCoralBg }))
        $g.FillEllipse($ring, 0, 0, ($s.Width - 1), ($s.Height - 1)); $ring.Dispose()
        [float]$m = PF 8
        $dot = New-Object System.Drawing.SolidBrush($(if ($ok) { $cTeal } else { $cCoral }))
        $g.FillEllipse($dot, $m, $m, ($s.Width - 1 - 2 * $m), ($s.Height - 1 - 2 * $m)); $dot.Dispose()
        $pen = New-Object System.Drawing.Pen($cWhite, (PF 4))
        $pen.StartCap = 'Round'; $pen.EndCap = 'Round'; $pen.LineJoin = 'Round'
        if ($ok) {
            $g.DrawLines($pen, [System.Drawing.PointF[]]@(
                (New-Object System.Drawing.PointF((PF 20), (PF 31))),
                (New-Object System.Drawing.PointF((PF 27), (PF 38))),
                (New-Object System.Drawing.PointF((PF 41), (PF 23)))))
        } else {
            $g.DrawLine($pen, (PF 30), (PF 19), (PF 30), (PF 33))
            $g.DrawLine($pen, (PF 30), (PF 41), (PF 30), (PF 41.5))
        }
        $pen.Dispose()
    })
    return $p
}

# ---------- window ----------
$form = New-Object System.Windows.Forms.Form
$form.Text = if ($Uninstall) { 'Uninstall Tidy Tide' } else { 'Install Tidy Tide' }
$form.ClientSize = New-Object System.Drawing.Size((P 640), (P 520))
$form.FormBorderStyle = 'FixedSingle'
$form.MaximizeBox = $false
$form.StartPosition = 'CenterScreen'
$form.BackColor = $cBg
$form.Font = $fBody
if (Test-Path -LiteralPath $icoPath) { $form.Icon = New-Object System.Drawing.Icon($icoPath) }
Set-ModernWindow $form
$logo = Get-IconBitmap $icoPath 256

$script:title = ''
$script:sub = ''
$script:step = -1    # 0..2 for the install steps, -1 hides the step dots

$header = New-Object System.Windows.Forms.Panel
$header.Dock = 'Top'
$header.Height = P 96
$header.BackColor = $cBg
Set-DoubleBuffered $header
$header.Add_Paint({
    param($s, $e)
    $g = $e.Graphics
    $g.SmoothingMode = 'AntiAlias'
    $g.InterpolationMode = 'HighQualityBicubic'
    if ($logo) { $g.DrawImage($logo, (P 28), (P 24), (P 46), (P 46)) }
    [System.Windows.Forms.TextRenderer]::DrawText($g, $script:title, $fTitle, (New-Object System.Drawing.Point((P 86), (P 20))), $cInk)
    [System.Windows.Forms.TextRenderer]::DrawText($g, $script:sub, $fSub, (New-Object System.Drawing.Point((P 88), (P 52))), $cSoft)

    if ($script:step -ge 0) {
        $names = 'Welcome', 'Licence', 'Done'
        [float]$gap = PF 70; [float]$r = PF 13
        [float]$x0 = $s.Width - (P 40) - 2 * $gap
        [float]$cy = PF 38
        $line = New-Object System.Drawing.Pen($cLine, (PF 2))
        $g.DrawLine($line, $x0, $cy, ($x0 + 2 * $gap), $cy); $line.Dispose()
        if ($script:step -gt 0) {
            $done = New-Object System.Drawing.Pen($cTeal, (PF 2))
            $g.DrawLine($done, $x0, $cy, ($x0 + $script:step * $gap), $cy); $done.Dispose()
        }
        for ($i = 0; $i -lt 3; $i++) {
            [float]$cx = $x0 + $i * $gap
            $rect = New-Object System.Drawing.RectangleF(($cx - $r), ($cy - $r), (2 * $r), (2 * $r))
            if ($i -lt $script:step) {
                $b = New-Object System.Drawing.SolidBrush($cTeal); $g.FillEllipse($b, $rect); $b.Dispose()
                $pen = New-Object System.Drawing.Pen($cWhite, (PF 2.4)); $pen.StartCap = 'Round'; $pen.EndCap = 'Round'
                $g.DrawLines($pen, [System.Drawing.PointF[]]@(
                    (New-Object System.Drawing.PointF(($cx - (PF 5)), $cy)),
                    (New-Object System.Drawing.PointF(($cx - (PF 1.5)), ($cy + (PF 4)))),
                    (New-Object System.Drawing.PointF(($cx + (PF 5.5)), ($cy - (PF 4))))))
                $pen.Dispose()
            } elseif ($i -eq $script:step) {
                $b = New-Object System.Drawing.SolidBrush($cSea); $g.FillEllipse($b, $rect); $b.Dispose()
                [System.Windows.Forms.TextRenderer]::DrawText($g, [string]($i + 1), $fSmall, [System.Drawing.Rectangle]::Round($rect), $cWhite, $centerFlags)
            } else {
                $b = New-Object System.Drawing.SolidBrush($cCard); $g.FillEllipse($b, $rect); $b.Dispose()
                $pen = New-Object System.Drawing.Pen($cLine, (PF 2)); $g.DrawEllipse($pen, $rect); $pen.Dispose()
                [System.Windows.Forms.TextRenderer]::DrawText($g, [string]($i + 1), $fSmall, [System.Drawing.Rectangle]::Round($rect), $cGray, $centerFlags)
            }
            $lr = New-Object System.Drawing.Rectangle([int]($cx - $gap / 2), [int]($cy + $r + (PF 4)), [int]$gap, (P 20))
            $lc = if ($i -eq $script:step) { $cInk } else { $cGray }
            [System.Windows.Forms.TextRenderer]::DrawText($g, $names[$i], $fSmall, $lr, $lc, $centerFlags)
        }
    }
})

$footer = New-Object System.Windows.Forms.Panel
$footer.Dock = 'Bottom'
$footer.Height = P 76
$footer.BackColor = $cBg
$btnPrimary = New-PillButton 'Next'   'primary' 132
$btnBack    = New-PillButton 'Back'   'soft'    100
$btnCancel  = New-PillButton 'Cancel' 'ghost'   100
$btnPrimary.Location = New-Object System.Drawing.Point(((P 640) - (P 26) - $btnPrimary.Width), (P 16))
$btnBack.Location    = New-Object System.Drawing.Point(($btnPrimary.Left - (P 10) - $btnBack.Width), (P 16))
$btnCancel.Location  = New-Object System.Drawing.Point((P 20), (P 16))
$footer.Controls.AddRange(@($btnPrimary, $btnBack, $btnCancel))

$content = New-Object System.Windows.Forms.Panel
$content.Dock = 'Fill'
$content.BackColor = $cBg

function New-Page {
    $p = New-Object System.Windows.Forms.Panel
    $p.Dock = 'Fill'
    $p.BackColor = $cBg
    $p.Visible = $false
    $content.Controls.Add($p)
    return $p
}

# ---------- install pages ----------
$pgWelcome = New-Page
$pgWelcome.Controls.Add((New-Label "Tidy Tide turns  1 (12).jpg  into  12.jpg. Setup takes a few seconds and doesn't need administrator rights." 30 2 580 46 $fBody $cSoft $cBg))
$cardWelcome = Add-Card $pgWelcome 22 52 596 156
$cardWelcome.Controls.Add((New-Label 'What setup will do' 22 18 400 24 $fBodyBold $cDeep $cCard))
Add-CardLine $cardWelcome $CHECK $cTeal 'Copy Tidy Tide to your user folder  (AppData\Local\TidyTide)' 54
Add-CardLine $cardWelcome $CHECK $cTeal 'Add it to the Start menu and to the right-click Send to menu' 84
Add-CardLine $cardWelcome $CHECK $cTeal 'Leave your files alone. Nothing is renamed until you press Rename' 114
$chkDesktop = Add-Toggle $pgWelcome 'Put a Tidy Tide shortcut on my desktop' 28 224 $true
$pgWelcome.Controls.Add((New-Label "Made by Yasamin Valishariatpanahi  $([char]0x00B7)  Free software under GPL-3.0" 30 286 580 22 $fSub $cGray $cBg))

$pgLicence = New-Page
$pgLicence.Controls.Add((New-Label "Tidy Tide is free software under the GNU General Public License v3. You don't have to accept it to use the app. It explains what you may do if you share or change it." 30 2 580 46 $fBody $cSoft $cBg))
$cardLicence = Add-Card $pgLicence 22 52 596 268
$licenceBox = New-Object System.Windows.Forms.TextBox
$licenceBox.Multiline = $true
$licenceBox.ReadOnly = $true
$licenceBox.WordWrap = $false
$licenceBox.ScrollBars = 'Vertical'
$licenceBox.BorderStyle = 'None'
$licenceBox.BackColor = $cCard
$licenceBox.ForeColor = $cInk
$licenceBox.Font = $fMono
$licenceBox.Location = New-Object System.Drawing.Point((P 22), (P 18))
$licenceBox.Size = New-Object System.Drawing.Size(($cardLicence.Width - (P 36)), ($cardLicence.Height - (P 38)))
$licenceBox.Add_HandleCreated({ [void][TidyTideUi.Native]::SetWindowTheme($this.Handle, 'Explorer', $null) })
$licenceBox.Text = if (Test-Path -LiteralPath $licensePath) {
    (Get-Content -LiteralPath $licensePath -Raw) -replace "`r?`n", "`r`n"
} else {
    'GNU General Public License v3.0. Full text: https://www.gnu.org/licenses/gpl-3.0.txt'
}
$cardLicence.Controls.Add($licenceBox)

$pgDone = New-Page
$badge = New-Badge 30 4
$pgDone.Controls.Add($badge)
$lblDoneTitle = New-Label 'Tidy Tide is ready!' 104 6 500 32 $fBig $cInk $cBg
$lblDoneSub   = New-Label "Here's how to use it:" 106 38 500 24 $fBody $cSoft $cBg
$pgDone.Controls.AddRange(@($lblDoneTitle, $lblDoneSub))
$cardDone = Add-Card $pgDone 22 82 596 160
Add-CardLine $cardDone '1' $cSea 'Open Tidy Tide from the Start menu or the desktop icon.' 20
Add-CardLine $cardDone '2' $cSea 'Or right-click files or a folder, then Send to > Tidy Tide.' 50
$cardDone.Controls.Add((New-Label "On Windows 11, Send to is under 'Show more options'." 48 74 500 22 $fSub $cGray $cCard))
Add-CardLine $cardDone '3' $cSea 'Check the preview, then press Rename. Undo is there if you need it.' 108
$chkOpen = Add-Toggle $pgDone 'Open Tidy Tide now' 28 258 $true

# ---------- uninstall pages ----------
$pgRemove = New-Page
$pgRemove.Controls.Add((New-Label 'This removes Tidy Tide from this computer. Your own files are not touched, including any you renamed.' 30 2 580 46 $fBody $cSoft $cBg))
$cardRemove = Add-Card $pgRemove 22 52 596 126
$cardRemove.Controls.Add((New-Label 'What will be removed' 22 18 400 24 $fBodyBold $cDeep $cCard))
Add-CardLine $cardRemove $DOT $cCoral 'The app folder in AppData\Local\TidyTide' 54
Add-CardLine $cardRemove $DOT $cCoral 'The desktop, Start menu and Send to shortcuts' 84

$pgRemoved = New-Page
$badge2 = New-Badge 30 4
$pgRemoved.Controls.Add($badge2)
$pgRemoved.Controls.Add((New-Label 'Tidy Tide has been removed' 104 6 500 32 $fBig $cInk $cBg))
$pgRemoved.Controls.Add((New-Label 'Thanks for trying it! You can install it again any time.' 106 38 500 24 $fBody $cSoft $cBg))

$form.Controls.Add($content)
$form.Controls.Add($footer)
$form.Controls.Add($header)
$content.BringToFront()

# ---------- actions ----------
function Invoke-Install {
    try {
        New-Item -ItemType Directory -Path $home2 -Force -ErrorAction Stop | Out-Null
        foreach ($f in $appFiles) {
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
        'welcome' { $pgWelcome.Visible = $true; $script:step = 0;  $script:title = 'Install Tidy Tide';   $script:sub = 'A quick, friendly setup';   $btnPrimary.Text = 'Next' }
        'licence' { $pgLicence.Visible = $true; $script:step = 1;  $script:title = 'Licence';             $script:sub = 'Please have a read';        $btnPrimary.Text = 'Install'; $btnBack.Visible = $true }
        'done'    { $pgDone.Visible = $true;    $script:step = 2;  $script:title = 'All done';            $script:sub = 'Tidy Tide is installed';    $btnPrimary.Text = 'Finish';  $btnCancel.Visible = $false }
        'remove'  { $pgRemove.Visible = $true;  $script:step = -1; $script:title = 'Uninstall Tidy Tide'; $script:sub = 'Remove the app and its shortcuts'; $btnPrimary.Text = 'Uninstall' }
        'removed' { $pgRemoved.Visible = $true; $script:step = -1; $script:title = 'Goodbye for now';     $script:sub = 'Tidy Tide was removed';     $btnPrimary.Text = 'Close';   $btnCancel.Visible = $false }
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

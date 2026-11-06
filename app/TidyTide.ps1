# Tidy Tide
# Turns "photo (12).jpg" or "(12).jpg" into "12.jpg".

param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Paths)

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

$here = Split-Path -Parent $MyInvocation.MyCommand.Path

# ---------- colours and fonts ----------
function C([string]$hex) { [System.Drawing.ColorTranslator]::FromHtml($hex) }
$cDeep   = C '#0A4D7C'
$cSea    = C '#1C8FC7'
$cSeaHi  = C '#2AA3DB'
$cAqua   = C '#4FC3E8'
$cFoam   = C '#EAF6FB'
$cMist   = C '#D6EEF8'
$cMistHi = C '#C4E6F5'
$cRowAlt = C '#F4FAFD'
$cSelect = C '#CDEBF7'
$cInk    = C '#12324A'
$cGray   = C '#8AA3B5'
$cTeal   = C '#12917F'
$cCoral  = C '#E07A5F'
$cWhite  = [System.Drawing.Color]::White

$fTitle    = New-Object System.Drawing.Font('Segoe UI Semibold', 22)
$fSub      = New-Object System.Drawing.Font('Segoe UI', 10.5)
$fButton   = New-Object System.Drawing.Font('Segoe UI Semibold', 10)
$fBig      = New-Object System.Drawing.Font('Segoe UI Semibold', 15)
$fBody     = New-Object System.Drawing.Font('Segoe UI', 10)
$fBodyBold = New-Object System.Drawing.Font('Segoe UI Semibold', 10)

$centerFlags = [System.Windows.Forms.TextFormatFlags]'HorizontalCenter, VerticalCenter, SingleLine, NoPrefix'
$cellFlags   = [System.Windows.Forms.TextFormatFlags]'Left, VerticalCenter, SingleLine, EndEllipsis, NoPrefix'
$CHECK = [string][char]0x2713
$DOT   = [string][char]0x2022

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
    $b.Width = $width
    $b.Height = 38
    $b.FlatStyle = 'Flat'
    $b.FlatAppearance.BorderSize = 0
    $b.Cursor = [System.Windows.Forms.Cursors]::Hand
    $b.Font = $fButton
    $b.Margin = New-Object System.Windows.Forms.Padding(0, 0, 10, 0)
    $b.Tag = @{ Back = $back; Hover = $hover; Fore = $fore; Over = $false }
    $b.Add_MouseEnter({ $this.Tag.Over = $true;  $this.Invalidate() })
    $b.Add_MouseLeave({ $this.Tag.Over = $false; $this.Invalidate() })
    $b.Add_EnabledChanged({ $this.Invalidate() })
    $b.Add_Paint({
        param($s, $e)
        $g = $e.Graphics
        $g.SmoothingMode = 'AntiAlias'
        $g.Clear($s.Parent.BackColor)
        $t = $s.Tag
        $fill = $t.Back
        $textColor = $t.Fore
        if (-not $s.Enabled) { $fill = $cMist; $textColor = $cGray }
        elseif ($t.Over) { $fill = $t.Hover }
        $path = New-RoundPath 0 0 ($s.Width - 1) ($s.Height - 1) (($s.Height - 1) / 2)
        $brush = New-Object System.Drawing.SolidBrush($fill)
        $g.FillPath($brush, $path)
        $brush.Dispose(); $path.Dispose()
        [System.Windows.Forms.TextRenderer]::DrawText($g, $s.Text, $s.Font, $s.ClientRectangle, $textColor, $centerFlags)
    })
    return $b
}

# ---------- file logic ----------
$pattern = '^.*?\s*\((\d+)\)$'
$script:files = New-Object System.Collections.Generic.List[string]
$script:seen  = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
$script:plan  = @()
$script:undo  = @()
$script:dragOver = $false

function Add-One([string]$full) {
    if ($script:seen.Add($full)) { $script:files.Add($full) }
}

function Add-Paths([string[]]$items) {
    if (-not $items) { return }
    foreach ($p in $items) {
        if ([string]::IsNullOrWhiteSpace($p)) { continue }
        if (Test-Path -LiteralPath $p -PathType Container) {
            Get-ChildItem -LiteralPath $p -File | ForEach-Object { Add-One $_.FullName }
        }
        elseif (Test-Path -LiteralPath $p -PathType Leaf) {
            Add-One (Get-Item -LiteralPath $p).FullName
        }
    }
    Update-Preview
}

function Set-Status([string]$text, $color) {
    $lblStatus.Text = $text
    $lblStatus.ForeColor = $color
}

function Update-Preview {
    $rows = New-Object System.Collections.Generic.List[object]
    foreach ($full in $script:files) {
        $row = [pscustomobject]@{
            Source = $full
            Dir    = [IO.Path]::GetDirectoryName($full)
            Name   = [IO.Path]::GetFileName($full)
            Ext    = [IO.Path]::GetExtension($full)
            Num    = $null
            NewName = ''
            Target = ''
            Code   = 'none'
        }
        $m = [regex]::Match([IO.Path]::GetFileNameWithoutExtension($full), $pattern)
        if ($m.Success) {
            $n = $m.Groups[1].Value.TrimStart('0')
            if ($n -eq '') { $n = '0' }
            $row.Num = $n
            $row.Code = 'ready'
        }
        $rows.Add($row)
    }

    $width = 0
    if ($chkPad.Checked) {
        foreach ($r in $rows) { if ($r.Num -and $r.Num.Length -gt $width) { $width = $r.Num.Length } }
    }

    $counts = @{}
    foreach ($r in $rows) {
        if ($r.Code -ne 'ready') { continue }
        $r.NewName = $r.Num.PadLeft($width, '0') + $r.Ext
        $r.Target  = [IO.Path]::Combine($r.Dir, $r.NewName)
        $counts[$r.Target] = 1 + [int]$counts[$r.Target]
    }
    foreach ($r in $rows) {
        if ($r.Code -ne 'ready') { continue }
        if ($counts[$r.Target] -gt 1) { $r.Code = 'dup' }
        elseif (Test-Path -LiteralPath $r.Target) { $r.Code = 'taken' }
    }

    $script:plan = @($rows | Sort-Object Dir, @{ Expression = { if ($_.Num) { 0 } else { 1 } } }, @{ Expression = { if ($_.Num) { $_.Num.PadLeft(20, '0') } else { '' } } }, Name)

    $list.BeginUpdate()
    $list.Items.Clear()
    $ready = 0
    foreach ($r in $script:plan) {
        $item = New-Object System.Windows.Forms.ListViewItem($r.Name)
        [void]$item.SubItems.Add($r.NewName)
        [void]$item.SubItems.Add('')
        $item.Tag = $r
        if ($r.Code -eq 'ready') { $ready++ }
        [void]$list.Items.Add($item)
    }
    $list.EndUpdate()

    $empty = ($script:files.Count -eq 0)
    $dropZone.Visible = $empty
    $list.Visible = -not $empty
    $btnClear.Enabled = -not $empty
    $btnRename.Enabled = ($ready -gt 0)

    if (-not $empty) {
        $skipped = $script:files.Count - $ready
        if ($ready -eq 0) {
            Set-Status 'None of these files have a (number) to clean up.' $cCoral
        } elseif ($skipped -eq 0) {
            Set-Status "$ready files ready to rename" $cDeep
        } else {
            Set-Status "$ready files ready, $skipped will be left alone" $cDeep
        }
    }
}

function Invoke-Rename {
    $ready = @($script:plan | Where-Object { $_.Code -eq 'ready' })
    if ($ready.Count -eq 0) { return }

    $done = New-Object System.Collections.Generic.List[object]
    $errors = New-Object System.Collections.Generic.List[string]
    foreach ($r in $ready) {
        try {
            [IO.File]::Move($r.Source, $r.Target)
            $done.Add([pscustomobject]@{ From = $r.Target; To = $r.Source })
        } catch {
            $errors.Add("$($r.Name): $($_.Exception.Message)")
        }
    }

    $script:undo = $done.ToArray()
    $btnUndo.Enabled = ($script:undo.Count -gt 0)
    $script:files.Clear()
    $script:seen.Clear()
    Update-Preview
    Set-Status "All done! $($done.Count) files renamed. Changed your mind? Press Undo." $cTeal

    if ($errors.Count -gt 0) {
        $msg = "These files could not be renamed:`r`n`r`n" + (($errors | Select-Object -First 15) -join "`r`n")
        [void][System.Windows.Forms.MessageBox]::Show($msg, 'Tidy Tide', 'OK', 'Warning')
    }
}

function Invoke-Undo {
    $back = 0
    $errors = New-Object System.Collections.Generic.List[string]
    foreach ($u in $script:undo) {
        try {
            if ((Test-Path -LiteralPath $u.From) -and -not (Test-Path -LiteralPath $u.To)) {
                [IO.File]::Move($u.From, $u.To)
                $back++
            }
        } catch {
            $errors.Add("$([IO.Path]::GetFileName($u.From)): $($_.Exception.Message)")
        }
    }
    $script:undo = @()
    $btnUndo.Enabled = $false
    Set-Status "Undone. $back files have their old names back." $cDeep
    if ($errors.Count -gt 0) {
        [void][System.Windows.Forms.MessageBox]::Show("Some files could not be restored:`r`n`r`n" + ($errors -join "`r`n"), 'Tidy Tide', 'OK', 'Warning')
    }
}

function Show-FilePicker {
    $dlg = New-Object System.Windows.Forms.OpenFileDialog
    $dlg.Multiselect = $true
    $dlg.Title = 'Pick the files to tidy up'
    if ($dlg.ShowDialog() -eq 'OK') { Add-Paths $dlg.FileNames }
}

function Show-FolderPicker {
    $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
    $dlg.Description = 'Pick a folder. Every file directly inside it gets added.'
    if ($dlg.ShowDialog() -eq 'OK') { Add-Paths @($dlg.SelectedPath) }
}

# ---------- window ----------
$form = New-Object System.Windows.Forms.Form
$form.Text = 'Tidy Tide'
$form.Size = New-Object System.Drawing.Size(860, 620)
$form.MinimumSize = New-Object System.Drawing.Size(680, 480)
$form.StartPosition = 'CenterScreen'
$form.BackColor = $cFoam
$form.Font = $fBody
$iconPath = Join-Path $here 'TidyTide.ico'
if (Test-Path -LiteralPath $iconPath) { $form.Icon = New-Object System.Drawing.Icon($iconPath) }

# header with gradient and waves
$header = New-Object System.Windows.Forms.Panel
$header.Dock = 'Top'
$header.Height = 128
Set-DoubleBuffered $header
$header.Add_Resize({ $this.Invalidate() })
$header.Add_Paint({
    param($s, $e)
    $w = $s.Width; $h = $s.Height
    if ($w -lt 4 -or $h -lt 4) { return }
    $g = $e.Graphics
    $g.SmoothingMode = 'AntiAlias'

    $grad = New-Object System.Drawing.Drawing2D.LinearGradientBrush($s.ClientRectangle, $cDeep, $cAqua, [float]0)
    $g.FillRectangle($grad, $s.ClientRectangle)
    $grad.Dispose()

    # back wave, see-through
    $p1 = New-Object System.Drawing.Drawing2D.GraphicsPath
    $p1.AddBezier([float]0, [float]($h - 26), [float]($w * 0.3), [float]($h - 62), [float]($w * 0.55), [float]($h - 2), [float]$w, [float]($h - 40))
    $p1.AddLine([float]$w, [float]($h - 40), [float]$w, [float]$h)
    $p1.AddLine([float]$w, [float]$h, [float]0, [float]$h)
    $p1.CloseFigure()
    $b1 = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(70, 255, 255, 255))
    $g.FillPath($b1, $p1)

    # front wave, same colour as the body so it melts into it
    $p2 = New-Object System.Drawing.Drawing2D.GraphicsPath
    $p2.AddBezier([float]0, [float]($h - 12), [float]($w * 0.35), [float]($h - 34), [float]($w * 0.65), [float]($h + 6), [float]$w, [float]($h - 18))
    $p2.AddLine([float]$w, [float]($h - 18), [float]$w, [float]$h)
    $p2.AddLine([float]$w, [float]$h, [float]0, [float]$h)
    $p2.CloseFigure()
    $b2 = New-Object System.Drawing.SolidBrush($cFoam)
    $g.FillPath($b2, $p2)

    # bubbles
    $pen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(150, 255, 255, 255), [float]2.5)
    $g.DrawEllipse($pen, [float]($w - 120), [float]22, [float]30, [float]30)
    $g.DrawEllipse($pen, [float]($w - 78), [float]14, [float]14, [float]14)
    $g.DrawEllipse($pen, [float]($w - 160), [float]48, [float]10, [float]10)

    $b1.Dispose(); $b2.Dispose(); $pen.Dispose(); $p1.Dispose(); $p2.Dispose()

    [System.Windows.Forms.TextRenderer]::DrawText($g, 'Tidy Tide', $fTitle, (New-Object System.Drawing.Point(26, 14)), $cWhite)
    [System.Windows.Forms.TextRenderer]::DrawText($g, 'Turns  photo (12).jpg  into  12.jpg', $fSub, (New-Object System.Drawing.Point(30, 58)), (C '#DDF1FA'))
})

# toolbar
$toolbar = New-Object System.Windows.Forms.FlowLayoutPanel
$toolbar.Dock = 'Top'
$toolbar.Height = 56
$toolbar.BackColor = $cFoam
$toolbar.Padding = New-Object System.Windows.Forms.Padding(24, 8, 24, 0)

$btnFiles  = New-PillButton '+  Add files'  $cSea  $cSeaHi  $cWhite 130
$btnFolder = New-PillButton '+  Add folder' $cSea  $cSeaHi  $cWhite 140
$btnClear  = New-PillButton 'Clear'         $cMist $cMistHi $cDeep  90
$toolbar.Controls.AddRange(@($btnFiles, $btnFolder, $btnClear))

# body: drop zone when empty, list when there are files
$body = New-Object System.Windows.Forms.Panel
$body.Dock = 'Fill'
$body.BackColor = $cFoam
$body.Padding = New-Object System.Windows.Forms.Padding(24, 4, 24, 4)

$dropZone = New-Object System.Windows.Forms.Panel
$dropZone.Dock = 'Fill'
$dropZone.AllowDrop = $true
$dropZone.Cursor = [System.Windows.Forms.Cursors]::Hand
Set-DoubleBuffered $dropZone
$dropZone.Add_Resize({ $this.Invalidate() })
$dropZone.Add_Paint({
    param($s, $e)
    $w = $s.Width; $h = $s.Height
    if ($w -lt 20 -or $h -lt 20) { return }
    $g = $e.Graphics
    $g.SmoothingMode = 'AntiAlias'
    $g.Clear($cFoam)

    $path = New-RoundPath 2 2 ($w - 5) ($h - 5) 22
    $fill = $cWhite
    if ($script:dragOver) { $fill = C '#DDF1FA' }
    $brush = New-Object System.Drawing.SolidBrush($fill)
    $g.FillPath($brush, $path)
    $pen = New-Object System.Drawing.Pen($cAqua, [float]2.5)
    $pen.DashStyle = 'Dash'
    $g.DrawPath($pen, $path)

    # three little waves
    $cx = $w / 2; $cy = $h / 2 - 46
    $wavePen = New-Object System.Drawing.Pen($cSea, [float]4)
    $wavePen.StartCap = 'Round'; $wavePen.EndCap = 'Round'
    foreach ($i in 0..2) {
        $y = $cy + ($i * 14) - 14
        $x0 = $cx - 36
        $g.DrawBezier($wavePen, [float]$x0, [float]$y, [float]($x0 + 18), [float]($y - 12), [float]($x0 + 36), [float]($y + 12), [float]($x0 + 54), [float]$y)
        $g.DrawBezier($wavePen, [float]($x0 + 54), [float]$y, [float]($x0 + 60), [float]($y - 4), [float]($x0 + 66), [float]($y - 4), [float]($x0 + 72), [float]$y)
    }

    $r1 = New-Object System.Drawing.Rectangle(0, [int]($cy + 30), $w, 34)
    $r2 = New-Object System.Drawing.Rectangle(0, [int]($cy + 64), $w, 24)
    [System.Windows.Forms.TextRenderer]::DrawText($g, 'Drop your files or a folder here', $fBig, $r1, $cDeep, $centerFlags)
    [System.Windows.Forms.TextRenderer]::DrawText($g, 'or click anywhere in this box to pick them', $fBody, $r2, $cGray, $centerFlags)

    $brush.Dispose(); $pen.Dispose(); $wavePen.Dispose(); $path.Dispose()
})

$list = New-Object System.Windows.Forms.ListView
$list.Dock = 'Fill'
$list.View = 'Details'
$list.FullRowSelect = $true
$list.AllowDrop = $true
$list.BorderStyle = 'None'
$list.BackColor = $cWhite
$list.OwnerDraw = $true
$list.HeaderStyle = 'Nonclickable'
$list.Visible = $false
Set-DoubleBuffered $list
$rowHeight = New-Object System.Windows.Forms.ImageList
$rowHeight.ImageSize = New-Object System.Drawing.Size(1, 34)
$list.SmallImageList = $rowHeight
[void]$list.Columns.Add('Now', 330)
[void]$list.Columns.Add('Becomes', 170)
[void]$list.Columns.Add('', 200)

$list.Add_Resize({
    $rest = $this.ClientSize.Width - $this.Columns[0].Width - $this.Columns[1].Width
    if ($rest -gt 60) { $this.Columns[2].Width = $rest }
})
$list.Add_DrawColumnHeader({
    param($s, $e)
    $g = $e.Graphics
    $brush = New-Object System.Drawing.SolidBrush($cMist)
    $g.FillRectangle($brush, $e.Bounds)
    $brush.Dispose()
    $r = New-Object System.Drawing.Rectangle(($e.Bounds.X + 12), $e.Bounds.Y, ($e.Bounds.Width - 12), $e.Bounds.Height)
    [System.Windows.Forms.TextRenderer]::DrawText($g, $e.Header.Text, $fBodyBold, $r, $cDeep, $cellFlags)
})
$list.Add_DrawItem({ param($s, $e) })
$list.Add_DrawSubItem({
    param($s, $e)
    $g = $e.Graphics
    $row = $e.Item.Tag
    $back = $cWhite
    if ($e.Item.Selected) { $back = $cSelect }
    elseif ($e.ItemIndex % 2 -eq 1) { $back = $cRowAlt }
    $brush = New-Object System.Drawing.SolidBrush($back)
    $g.FillRectangle($brush, $e.Bounds)
    $brush.Dispose()

    $text = $e.SubItem.Text
    $font = $fBody
    $color = $cInk
    switch ($e.ColumnIndex) {
        0 { if ($row.Code -ne 'ready') { $color = $cGray } }
        1 { $font = $fBodyBold; $color = $cSea }
        2 {
            switch ($row.Code) {
                'ready' { $text = "$CHECK  Ready";                       $color = $cTeal }
                'none'  { $text = "$DOT  No (number), left alone";       $color = $cGray }
                'dup'   { $text = "$DOT  Same number twice, left alone"; $color = $cCoral }
                'taken' { $text = "$DOT  Name already taken, left alone"; $color = $cCoral }
            }
        }
    }
    $r = New-Object System.Drawing.Rectangle(($e.Bounds.X + 12), $e.Bounds.Y, ($e.Bounds.Width - 16), $e.Bounds.Height)
    [System.Windows.Forms.TextRenderer]::DrawText($g, $text, $font, $r, $color, $cellFlags)
})

$body.Controls.Add($list)
$body.Controls.Add($dropZone)

# footer
$footer = New-Object System.Windows.Forms.Panel
$footer.Dock = 'Bottom'
$footer.Height = 78
$footer.BackColor = $cFoam

$chkPad = New-Object System.Windows.Forms.CheckBox
$chkPad.Text = 'Add zeros in front (01, 02 ... 10) so every app sorts them right'
$chkPad.AutoSize = $true
$chkPad.ForeColor = $cInk
$chkPad.Cursor = [System.Windows.Forms.Cursors]::Hand

$lblStatus = New-Object System.Windows.Forms.Label
$lblStatus.AutoSize = $true
$lblStatus.Font = $fBodyBold

$btnUndo   = New-PillButton 'Undo'   $cMist $cMistHi $cDeep 90
$btnRename = New-PillButton 'Rename' $cDeep $cSea    $cWhite 130
$btnUndo.Enabled = $false
$btnRename.Enabled = $false
$footer.Controls.AddRange(@($chkPad, $lblStatus, $btnUndo, $btnRename))
$footer.Add_Resize({
    $w = $footer.ClientSize.Width
    $btnRename.Location = New-Object System.Drawing.Point(($w - 24 - $btnRename.Width), 20)
    $btnUndo.Location   = New-Object System.Drawing.Point(($btnRename.Left - 10 - $btnUndo.Width), 20)
    $chkPad.Location    = New-Object System.Drawing.Point(26, 14)
    $lblStatus.Location = New-Object System.Drawing.Point(28, 44)
})

$form.Controls.Add($body)
$form.Controls.Add($footer)
$form.Controls.Add($toolbar)
$form.Controls.Add($header)
$body.BringToFront()

# ---------- events ----------
$onDragEnter = {
    if ($_.Data.GetDataPresent([System.Windows.Forms.DataFormats]::FileDrop)) {
        $_.Effect = 'Copy'
        $script:dragOver = $true
        $dropZone.Invalidate()
    }
}
$onDragLeave = { $script:dragOver = $false; $dropZone.Invalidate() }
$onDragDrop = {
    $script:dragOver = $false
    Add-Paths ([string[]]$_.Data.GetData([System.Windows.Forms.DataFormats]::FileDrop))
}
foreach ($target in @($dropZone, $list)) {
    $target.Add_DragEnter($onDragEnter)
    $target.Add_DragLeave($onDragLeave)
    $target.Add_DragDrop($onDragDrop)
}

$dropZone.Add_Click({ Show-FilePicker })
$list.Add_KeyDown({
    if ($_.KeyCode -eq 'Delete' -and $list.SelectedItems.Count -gt 0) {
        foreach ($it in @($list.SelectedItems)) {
            [void]$script:files.Remove($it.Tag.Source)
            [void]$script:seen.Remove($it.Tag.Source)
        }
        Update-Preview
    }
})
$btnFiles.Add_Click({ Show-FilePicker })
$btnFolder.Add_Click({ Show-FolderPicker })
$btnClear.Add_Click({ $script:files.Clear(); $script:seen.Clear(); Update-Preview; Set-Status '' $cDeep })
$chkPad.Add_CheckedChanged({ Update-Preview })
$btnRename.Add_Click({ Invoke-Rename })
$btnUndo.Add_Click({ Invoke-Undo })

Update-Preview
Set-Status 'Tip: select rows and press Delete to leave them out.' $cGray
Add-Paths $Paths
[void]$form.ShowDialog()

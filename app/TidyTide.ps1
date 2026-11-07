# Tidy Tide
# Turns "1 (12).jpg", "photo (12).jpg" or "(12).jpg" into "12.jpg".

param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Paths)

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $here 'ui.ps1')

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
$form.ClientSize = New-Object System.Drawing.Size((P 620), (P 460))
$form.MinimumSize = New-Object System.Drawing.Size((P 600), (P 400))
$form.StartPosition = 'CenterScreen'
$form.BackColor = $cBg
$form.Font = $fBody
$iconPath = Join-Path $here 'TidyTide.ico'
if (Test-Path -LiteralPath $iconPath) { $form.Icon = New-Object System.Drawing.Icon($iconPath) }
Set-ModernWindow $form
$logo = Get-IconBitmap $iconPath 256
$fAppTitle = New-Object System.Drawing.Font($fnDisplay, 12.5)
$fAppSub   = New-Object System.Drawing.Font($fnText, 8.5)

# header: logo and name on the left, buttons on the right
$header = New-Object System.Windows.Forms.Panel
$header.Dock = 'Top'
$header.Height = P 62
$header.BackColor = $cBg
Set-DoubleBuffered $header
$header.Add_Paint({
    param($s, $e)
    $g = $e.Graphics
    $g.InterpolationMode = 'HighQualityBicubic'
    if ($logo) { $g.DrawImage($logo, (P 16), (P 15), (P 32), (P 32)) }
    [System.Windows.Forms.TextRenderer]::DrawText($g, 'Tidy Tide', $fAppTitle, (New-Object System.Drawing.Point((P 56), (P 11))), $cInk)
    [System.Windows.Forms.TextRenderer]::DrawText($g, 'Turns  1 (12).jpg  into  12.jpg', $fAppSub, (New-Object System.Drawing.Point((P 57), (P 34))), $cSoft)
})
$btnFiles  = New-PillButton '+  Add files'  'accent' 98  32
$btnFolder = New-PillButton '+  Add folder' 'soft'   108 32
$btnClear  = New-PillButton 'Clear'         'ghost'  62  32
$header.Controls.AddRange(@($btnFiles, $btnFolder, $btnClear))
$header.Add_Resize({
    $x = $this.ClientSize.Width - (P 14)
    foreach ($b in @($btnClear, $btnFolder, $btnFiles)) {
        $x -= $b.Width
        $b.Location = New-Object System.Drawing.Point($x, (P 15))
        $x -= P 6
    }
})

# body: a white card holding the drop zone (when empty) or the list
$body = New-Object System.Windows.Forms.Panel
$body.Dock = 'Fill'
$body.BackColor = $cBg
$body.Padding = New-Object System.Windows.Forms.Padding((P 12), 0, (P 12), 0)
$card = New-Card
$card.Dock = 'Fill'
$card.Padding = New-Object System.Windows.Forms.Padding((P 6))
$body.Controls.Add($card)

$dropZone = New-Object System.Windows.Forms.Panel
$dropZone.Dock = 'Fill'
$dropZone.BackColor = $cCard
$dropZone.AllowDrop = $true
$dropZone.Cursor = [System.Windows.Forms.Cursors]::Hand
Set-DoubleBuffered $dropZone
$dropZone.Add_Resize({ $this.Invalidate() })
$dropZone.Add_Paint({
    param($s, $e)
    $w = $s.Width; $h = $s.Height
    if ($w -lt 40 -or $h -lt 40) { return }
    $g = $e.Graphics
    $g.SmoothingMode = 'AntiAlias'
    $g.Clear($cCard)

    $path = New-RoundPath (PF 6) (PF 6) ($w - (PF 13)) ($h - (PF 13)) (PF 10)
    if ($script:dragOver) {
        $fb = New-Object System.Drawing.SolidBrush((C '#EEF8FD')); $g.FillPath($fb, $path); $fb.Dispose()
    }
    $penColor = if ($script:dragOver) { $cSea } else { C '#A9DDF1' }
    $pen = New-Object System.Drawing.Pen($penColor, (PF 2))
    $pen.DashPattern = [float[]]@(4, 3)
    $g.DrawPath($pen, $path); $pen.Dispose(); $path.Dispose()

    # round badge with an arrow dropping onto waves
    [float]$cx = $w / 2; [float]$cy = $h / 2 - (PF 26); [float]$rad = PF 26
    $cb = New-Object System.Drawing.SolidBrush($cFoam)
    $g.FillEllipse($cb, $cx - $rad, $cy - $rad, 2 * $rad, 2 * $rad); $cb.Dispose()
    $ap = New-Object System.Drawing.Pen($cSea, (PF 2.6))
    $ap.StartCap = 'Round'; $ap.EndCap = 'Round'; $ap.LineJoin = 'Round'
    $g.DrawLine($ap, $cx, $cy - (PF 13), $cx, $cy + (PF 1))
    $g.DrawLines($ap, [System.Drawing.PointF[]]@(
        (New-Object System.Drawing.PointF(($cx - (PF 6)), ($cy - (PF 5)))),
        (New-Object System.Drawing.PointF($cx, ($cy + (PF 1)))),
        (New-Object System.Drawing.PointF(($cx + (PF 6)), ($cy - (PF 5))))))
    [float]$wy = $cy + (PF 10)
    $g.DrawBezier($ap, ($cx - (PF 13)), $wy, ($cx - (PF 6.5)), ($wy - (PF 4.5)), ($cx - (PF 6.5)), ($wy + (PF 4.5)), $cx, $wy)
    $g.DrawBezier($ap, $cx, $wy, ($cx + (PF 6.5)), ($wy - (PF 4.5)), ($cx + (PF 6.5)), ($wy + (PF 4.5)), ($cx + (PF 13)), $wy)
    $ap.Dispose()

    $r1 = New-Object System.Drawing.Rectangle(0, [int]($cy + $rad + (PF 10)), $w, (P 24))
    $r2 = New-Object System.Drawing.Rectangle(0, [int]($cy + $rad + (PF 34)), $w, (P 20))
    [System.Windows.Forms.TextRenderer]::DrawText($g, 'Drop files or a folder here', $fBodyBold, $r1, $cInk, $centerFlags)
    [System.Windows.Forms.TextRenderer]::DrawText($g, 'or click to choose them', $fAppSub, $r2, $cGray, $centerFlags)
})

$list = New-Object System.Windows.Forms.ListView
$list.Dock = 'Fill'
$list.View = 'Details'
$list.FullRowSelect = $true
$list.AllowDrop = $true
$list.BorderStyle = 'None'
$list.BackColor = $cCard
$list.Font = $fBody
$list.OwnerDraw = $true
$list.HeaderStyle = 'Nonclickable'
$list.Visible = $false
Set-DoubleBuffered $list
$rowHeight = New-Object System.Windows.Forms.ImageList
$rowHeight.ImageSize = New-Object System.Drawing.Size(1, (P 34))
$list.SmallImageList = $rowHeight
[void]$list.Columns.Add('CURRENT NAME', (P 230))
[void]$list.Columns.Add('NEW NAME', (P 110))
[void]$list.Columns.Add('STATUS', (P 150))
$list.Add_HandleCreated({ [void][TidyTideUi.Native]::SetWindowTheme($this.Handle, 'Explorer', $null) })
$list.Add_Resize({
    $rest = $this.ClientSize.Width - $this.Columns[0].Width - $this.Columns[1].Width
    if ($rest -gt (P 60)) { $this.Columns[2].Width = $rest }
})

$script:hot = -1
$list.Add_MouseMove({
    $it = $this.GetItemAt((P 4), $_.Y)
    $i = if ($it) { $it.Index } else { -1 }
    if ($i -ne $script:hot) {
        $old = $script:hot; $script:hot = $i
        if ($old -ge 0 -and $old -lt $this.Items.Count) { $this.Invalidate($this.Items[$old].Bounds) }
        if ($i -ge 0) { $this.Invalidate($this.Items[$i].Bounds) }
    }
})
$list.Add_MouseLeave({
    if ($script:hot -ge 0 -and $script:hot -lt $this.Items.Count) { $this.Invalidate($this.Items[$script:hot].Bounds) }
    $script:hot = -1
})

$list.Add_DrawColumnHeader({
    param($s, $e)
    $g = $e.Graphics
    $b = New-Object System.Drawing.SolidBrush($cCard); $g.FillRectangle($b, $e.Bounds); $b.Dispose()
    $pen = New-Object System.Drawing.Pen($cLine, (PF 1))
    $g.DrawLine($pen, $e.Bounds.Left, ($e.Bounds.Bottom - 1), $e.Bounds.Right, ($e.Bounds.Bottom - 1)); $pen.Dispose()
    $r = New-Object System.Drawing.Rectangle(($e.Bounds.X + (P 12)), $e.Bounds.Y, ($e.Bounds.Width - (P 12)), $e.Bounds.Height)
    [System.Windows.Forms.TextRenderer]::DrawText($g, $e.Header.Text, $fSmall, $r, $cGray, $leftFlags)
})
$list.Add_DrawItem({ param($s, $e) })
$list.Add_DrawSubItem({
    param($s, $e)
    $g = $e.Graphics
    $g.SmoothingMode = 'AntiAlias'
    $row = $e.Item.Tag
    $back = $cCard
    if ($e.Item.Selected) { $back = $cSelect }
    elseif ($e.ItemIndex -eq $script:hot) { $back = $cHover }
    $brush = New-Object System.Drawing.SolidBrush($back)
    $g.FillRectangle($brush, ($e.Bounds.X - 1), $e.Bounds.Y, ($e.Bounds.Width + 2), $e.Bounds.Height); $brush.Dispose()
    $pen = New-Object System.Drawing.Pen((C '#EEF4F8'), (PF 1))
    $g.DrawLine($pen, $e.Bounds.Left, ($e.Bounds.Bottom - 1), $e.Bounds.Right, ($e.Bounds.Bottom - 1)); $pen.Dispose()

    $r = New-Object System.Drawing.Rectangle(($e.Bounds.X + (P 12)), $e.Bounds.Y, ($e.Bounds.Width - (P 14)), $e.Bounds.Height)
    $cy = [int]($e.Bounds.Y + $e.Bounds.Height / 2)
    switch ($e.ColumnIndex) {
        0 {
            $color = if ($row.Code -eq 'ready') { $cInk } else { $cGray }
            [System.Windows.Forms.TextRenderer]::DrawText($g, $e.SubItem.Text, $fBody, $r, $color, $leftFlags)
        }
        1 {
            if ($e.SubItem.Text) {
                [System.Windows.Forms.TextRenderer]::DrawText($g, $e.SubItem.Text, $fBodyBold, $r, $cSea, $leftFlags)
            }
        }
        2 {
            switch ($row.Code) {
                'ready' { Draw-Badge $g "$CHECK  Ready" $r.X $cy $cMintBg $cTeal }
                'none'  { Draw-Badge $g 'No (number)' $r.X $cy $cGrayBg $cGray }
                'dup'   { Draw-Badge $g 'Same number twice' $r.X $cy $cCoralBg $cCoral }
                'taken' { Draw-Badge $g 'Name already taken' $r.X $cy $cCoralBg $cCoral }
            }
        }
    }
})

$card.Controls.Add($list)
$card.Controls.Add($dropZone)

# footer
$footer = New-Object System.Windows.Forms.Panel
$footer.Dock = 'Bottom'
$footer.Height = P 62
$footer.BackColor = $cBg

$chkPad = New-Toggle 'Add zeros (01, 02 ... 10)'

$lblStatus = New-Object System.Windows.Forms.Label
$lblStatus.AutoSize = $true
$lblStatus.Font = $fSmall
$lblStatus.BackColor = $cBg

$btnUndo   = New-PillButton 'Undo'   'soft'    74  34
$btnRename = New-PillButton 'Rename' 'primary' 100 34
$btnUndo.Enabled = $false
$btnRename.Enabled = $false
$footer.Controls.AddRange(@($chkPad, $lblStatus, $btnUndo, $btnRename))
$footer.Add_Resize({
    $w = $footer.ClientSize.Width
    $btnRename.Location = New-Object System.Drawing.Point(($w - (P 14) - $btnRename.Width), (P 14))
    $btnUndo.Location   = New-Object System.Drawing.Point(($btnRename.Left - (P 6) - $btnUndo.Width), (P 14))
    $chkPad.Location    = New-Object System.Drawing.Point((P 16), (P 6))
    $lblStatus.Location = New-Object System.Drawing.Point((P 17), (P 36))
})

$form.Controls.Add($body)
$form.Controls.Add($footer)
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

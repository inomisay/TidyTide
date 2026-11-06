# Tidy Tide
# Turns "photo (12).jpg" or "(12).jpg" into "12.jpg".

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
$form.ClientSize = New-Object System.Drawing.Size((P 900), (P 640))
$form.MinimumSize = New-Object System.Drawing.Size((P 720), (P 520))
$form.StartPosition = 'CenterScreen'
$form.BackColor = $cBg
$form.Font = $fBody
$iconPath = Join-Path $here 'TidyTide.ico'
if (Test-Path -LiteralPath $iconPath) { $form.Icon = New-Object System.Drawing.Icon($iconPath) }
Set-ModernWindow $form
$logo = Get-IconBitmap $iconPath 256

# header: logo, name and a little sea on the right
$header = New-Object System.Windows.Forms.Panel
$header.Dock = 'Top'
$header.Height = P 92
$header.BackColor = $cBg
Set-DoubleBuffered $header
$header.Add_Resize({ $this.Invalidate() })
$header.Add_Paint({
    param($s, $e)
    $g = $e.Graphics
    $g.SmoothingMode = 'AntiAlias'
    $g.InterpolationMode = 'HighQualityBicubic'
    $w = $s.Width; $h = $s.Height
    $pen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(110, 79, 195, 232), (PF 2))
    $g.DrawEllipse($pen, [float]($w - (P 118)), (PF 18), (PF 26), (PF 26))
    $g.DrawEllipse($pen, [float]($w - (P 80)), (PF 12), (PF 12), (PF 12))
    $g.DrawEllipse($pen, [float]($w - (P 150)), (PF 40), (PF 9), (PF 9))
    $pen.Dispose()
    if ($logo) { $g.DrawImage($logo, (P 28), (P 22), (P 48), (P 48)) }
    [System.Windows.Forms.TextRenderer]::DrawText($g, 'Tidy Tide', $fTitle, (New-Object System.Drawing.Point((P 88), (P 18))), $cInk)
    [System.Windows.Forms.TextRenderer]::DrawText($g, 'Turns  photo (12).jpg  into  12.jpg', $fSub, (New-Object System.Drawing.Point((P 90), (P 50))), $cSoft)
})

# toolbar
$toolbar = New-Object System.Windows.Forms.FlowLayoutPanel
$toolbar.Dock = 'Top'
$toolbar.Height = P 58
$toolbar.BackColor = $cBg
$toolbar.Padding = New-Object System.Windows.Forms.Padding((P 26), (P 8), (P 26), 0)
$btnFiles  = New-PillButton '+   Add files'  'accent' 132
$btnFolder = New-PillButton '+   Add folder' 'soft'   140
$btnClear  = New-PillButton 'Clear'          'ghost'  86
foreach ($b in @($btnFiles, $btnFolder, $btnClear)) { $b.Margin = New-Object System.Windows.Forms.Padding(0, 0, (P 10), 0) }
$toolbar.Controls.AddRange(@($btnFiles, $btnFolder, $btnClear))

# body: a white card holding the drop zone (when empty) or the list
$body = New-Object System.Windows.Forms.Panel
$body.Dock = 'Fill'
$body.BackColor = $cBg
$body.Padding = New-Object System.Windows.Forms.Padding((P 22), (P 2), (P 22), (P 2))
$card = New-Card
$card.Dock = 'Fill'
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

    $path = New-RoundPath (PF 8) (PF 8) ($w - (PF 17)) ($h - (PF 17)) (PF 12)
    if ($script:dragOver) {
        $fb = New-Object System.Drawing.SolidBrush((C '#EEF8FD')); $g.FillPath($fb, $path); $fb.Dispose()
    }
    $penColor = if ($script:dragOver) { $cSea } else { C '#A9DDF1' }
    $pen = New-Object System.Drawing.Pen($penColor, (PF 2))
    $pen.DashPattern = [float[]]@(4, 3)
    $g.DrawPath($pen, $path); $pen.Dispose(); $path.Dispose()

    # round badge with an arrow dropping onto waves
    [float]$cx = $w / 2; [float]$cy = $h / 2 - (PF 40); [float]$rad = PF 38
    $cb = New-Object System.Drawing.SolidBrush($cFoam)
    $g.FillEllipse($cb, $cx - $rad, $cy - $rad, 2 * $rad, 2 * $rad); $cb.Dispose()
    $ap = New-Object System.Drawing.Pen($cSea, (PF 3.2))
    $ap.StartCap = 'Round'; $ap.EndCap = 'Round'; $ap.LineJoin = 'Round'
    $g.DrawLine($ap, $cx, $cy - (PF 18), $cx, $cy + (PF 2))
    $g.DrawLines($ap, [System.Drawing.PointF[]]@(
        (New-Object System.Drawing.PointF(($cx - (PF 8)), ($cy - (PF 6)))),
        (New-Object System.Drawing.PointF($cx, ($cy + (PF 2)))),
        (New-Object System.Drawing.PointF(($cx + (PF 8)), ($cy - (PF 6))))))
    [float]$wy = $cy + (PF 14)
    $g.DrawBezier($ap, ($cx - (PF 18)), $wy, ($cx - (PF 9)), ($wy - (PF 6)), ($cx - (PF 9)), ($wy + (PF 6)), $cx, $wy)
    $g.DrawBezier($ap, $cx, $wy, ($cx + (PF 9)), ($wy - (PF 6)), ($cx + (PF 9)), ($wy + (PF 6)), ($cx + (PF 18)), $wy)
    $ap.Dispose()

    $r1 = New-Object System.Drawing.Rectangle(0, [int]($cy + $rad + (PF 16)), $w, (P 32))
    $r2 = New-Object System.Drawing.Rectangle(0, [int]($cy + $rad + (PF 48)), $w, (P 24))
    [System.Windows.Forms.TextRenderer]::DrawText($g, 'Drop your files or a folder here', $fBig, $r1, $cInk, $centerFlags)
    [System.Windows.Forms.TextRenderer]::DrawText($g, 'or click to choose them', $fBody, $r2, $cGray, $centerFlags)
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
$rowHeight.ImageSize = New-Object System.Drawing.Size(1, (P 44))
$list.SmallImageList = $rowHeight
[void]$list.Columns.Add('CURRENT NAME', (P 340))
[void]$list.Columns.Add('NEW NAME', (P 170))
[void]$list.Columns.Add('STATUS', (P 200))
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
    $r = New-Object System.Drawing.Rectangle(($e.Bounds.X + (P 16)), $e.Bounds.Y, ($e.Bounds.Width - (P 16)), $e.Bounds.Height)
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

    $r = New-Object System.Drawing.Rectangle(($e.Bounds.X + (P 16)), $e.Bounds.Y, ($e.Bounds.Width - (P 20)), $e.Bounds.Height)
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
                'none'  { Draw-Badge $g 'No (number), left alone' $r.X $cy $cGrayBg $cGray }
                'dup'   { Draw-Badge $g 'Same number twice, left alone' $r.X $cy $cCoralBg $cCoral }
                'taken' { Draw-Badge $g 'Name already taken, left alone' $r.X $cy $cCoralBg $cCoral }
            }
        }
    }
})

$card.Controls.Add($list)
$card.Controls.Add($dropZone)

# footer
$footer = New-Object System.Windows.Forms.Panel
$footer.Dock = 'Bottom'
$footer.Height = P 86
$footer.BackColor = $cBg

$chkPad = New-Toggle 'Add zeros in front (01, 02 ... 10) so every app sorts them right'

$lblStatus = New-Object System.Windows.Forms.Label
$lblStatus.AutoSize = $true
$lblStatus.Font = $fBodyBold
$lblStatus.BackColor = $cBg

$btnUndo   = New-PillButton 'Undo'   'soft'    96
$btnRename = New-PillButton 'Rename' 'primary' 140
$btnUndo.Enabled = $false
$btnRename.Enabled = $false
$footer.Controls.AddRange(@($chkPad, $lblStatus, $btnUndo, $btnRename))
$footer.Add_Resize({
    $w = $footer.ClientSize.Width
    $btnRename.Location = New-Object System.Drawing.Point(($w - (P 28) - $btnRename.Width), (P 22))
    $btnUndo.Location   = New-Object System.Drawing.Point(($btnRename.Left - (P 10) - $btnUndo.Width), (P 22))
    $chkPad.Location    = New-Object System.Drawing.Point((P 28), (P 14))
    $lblStatus.Location = New-Object System.Drawing.Point((P 28), (P 50))
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

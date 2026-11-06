# Tidy Tide: shared look for the app and its setup.
# Sharp text on high-DPI screens, Windows 11 fonts and window style, sea colours, and drawing helpers.
# Dot-source this file before creating any window:  . (Join-Path $here 'ui.ps1')

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

if (-not ('TidyTideUi.Native' -as [type])) {
    Add-Type -Namespace TidyTideUi -Name Native -MemberDefinition @'
[DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
[DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr value);
[DllImport("dwmapi.dll")] public static extern int DwmSetWindowAttribute(IntPtr hwnd, int attr, ref int value, int size);
[DllImport("uxtheme.dll", CharSet = CharSet.Unicode)] public static extern int SetWindowTheme(IntPtr hwnd, string app, string idList);
'@
}

# Draw at the screen's real resolution instead of letting Windows stretch a blurry 96-DPI picture.
try { [void][TidyTideUi.Native]::SetProcessDpiAwarenessContext([IntPtr](-2)) }   # system aware
catch { try { [void][TidyTideUi.Native]::SetProcessDPIAware() } catch {} }
[System.Windows.Forms.Application]::EnableVisualStyles()

$g0 = [System.Drawing.Graphics]::FromHwnd([IntPtr]::Zero)
$script:UiScale = [Math]::Max(1.0, $g0.DpiX / 96.0)
$g0.Dispose()
function P([double]$n) { [int][Math]::Round($n * $script:UiScale) }
function PF([double]$n) { [float]($n * $script:UiScale) }

# ---------- colours ----------
function C([string]$hex) { [System.Drawing.ColorTranslator]::FromHtml($hex) }
$cBg      = C '#F3F8FB'   # window
$cCard    = [System.Drawing.Color]::White
$cLine    = C '#E1ECF3'
$cInk     = C '#12324A'
$cSoft    = C '#557590'
$cGray    = C '#8AA3B5'
$cDeep    = C '#0A4D7C'
$cSea     = C '#1C8FC7'
$cSeaHi   = C '#2AA3DB'
$cAqua    = C '#4FC3E8'
$cFoam    = C '#EAF6FB'
$cMist    = C '#E3F0F7'
$cMistHi  = C '#D3E8F3'
$cSelect  = C '#DDF0FA'
$cHover   = C '#F4FAFD'
$cTeal    = C '#12917F'
$cMintBg  = C '#DDF6EF'
$cCoral   = C '#D25F4B'
$cCoralBg = C '#FDE9E4'
$cGrayBg  = C '#EEF3F6'
$cWhite   = [System.Drawing.Color]::White

# ---------- fonts (Windows 11 "Segoe UI Variable" when available) ----------
$installed = @((New-Object System.Drawing.Text.InstalledFontCollection).Families | ForEach-Object { $_.Name })
function Select-FontName([string[]]$names) {
    foreach ($n in $names) { if ($installed -contains $n) { return $n } }
    return 'Segoe UI'
}
$fnDisplay     = Select-FontName 'Segoe UI Variable Display Semib', 'Segoe UI Semibold'
$fnText        = Select-FontName 'Segoe UI Variable Text', 'Segoe UI'
$fnTextSemi    = Select-FontName 'Segoe UI Variable Text Semibold', 'Segoe UI Semibold'

$fTitle    = New-Object System.Drawing.Font($fnDisplay, 17)
$fBig      = New-Object System.Drawing.Font($fnDisplay, 13.5)
$fSub      = New-Object System.Drawing.Font($fnText, 10)
$fBody     = New-Object System.Drawing.Font($fnText, 10)
$fBodyBold = New-Object System.Drawing.Font($fnTextSemi, 10)
$fSmall    = New-Object System.Drawing.Font($fnTextSemi, 8.5)
$fButton   = New-Object System.Drawing.Font($fnTextSemi, 10)

$centerFlags = [System.Windows.Forms.TextFormatFlags]'HorizontalCenter, VerticalCenter, SingleLine, NoPrefix'
$leftFlags   = [System.Windows.Forms.TextFormatFlags]'Left, VerticalCenter, SingleLine, EndEllipsis, NoPrefix'
$wrapFlags   = [System.Windows.Forms.TextFormatFlags]'Left, Top, WordBreak, NoPrefix'
$CHECK = [string][char]0x2713
$DOT   = [string][char]0x2022

# ---------- helpers ----------
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

function Get-IconBitmap([string]$icoPath, [int]$size) {
    if (-not (Test-Path -LiteralPath $icoPath)) { return $null }
    # Icon.ToBitmap cannot read PNG-compressed images inside an .ico, so read the largest PNG entry directly.
    try {
        $bytes = [IO.File]::ReadAllBytes($icoPath)
        $count = [BitConverter]::ToUInt16($bytes, 4)
        $best = $null; $bestW = 0
        for ($i = 0; $i -lt $count; $i++) {
            $o = 6 + 16 * $i
            $w = if ($bytes[$o] -eq 0) { 256 } else { [int]$bytes[$o] }
            $len = [BitConverter]::ToInt32($bytes, $o + 8)
            $off = [BitConverter]::ToInt32($bytes, $o + 12)
            $isPng = $bytes[$off] -eq 0x89 -and $bytes[$off + 1] -eq 0x50
            if ($isPng -and $w -gt $bestW) { $best = @($off, $len); $bestW = $w }
        }
        if ($best) {
            $ms = New-Object IO.MemoryStream($bytes, $best[0], $best[1])
            return [System.Drawing.Bitmap]::FromStream($ms)
        }
    } catch {}
    foreach ($sz in @($size, 64, 48, 32)) {
        try {
            $ico = New-Object System.Drawing.Icon($icoPath, $sz, $sz)
            $bmp = $ico.ToBitmap(); $ico.Dispose()
            return $bmp
        } catch {}
    }
    return $null
}

# Windows 11: rounded corners and a title bar in the window's own colour (ignored on Windows 10).
function Set-ModernWindow($form) {
    $form.Add_HandleCreated({
        $h = $this.Handle
        $ref = { param($c) [int]$c.R -bor ([int]$c.G -shl 8) -bor ([int]$c.B -shl 16) }
        try {
            $v = 2;                   [void][TidyTideUi.Native]::DwmSetWindowAttribute($h, 33, [ref]$v, 4)   # round corners
            $v = & $ref $cBg;         [void][TidyTideUi.Native]::DwmSetWindowAttribute($h, 35, [ref]$v, 4)   # caption colour
            $v = & $ref $cInk;        [void][TidyTideUi.Native]::DwmSetWindowAttribute($h, 36, [ref]$v, 4)   # caption text
            $v = & $ref (C '#D5E5EE'); [void][TidyTideUi.Native]::DwmSetWindowAttribute($h, 34, [ref]$v, 4)  # border
        } catch {}
    })
}

# Rounded "pill" button. Styles: primary (deep blue), accent (sea blue), soft (light blue), ghost (text only).
function New-PillButton([string]$text, [string]$style, [int]$width) {
    $styles = @{
        primary = @{ Back = $cDeep;  Hover = (C '#0D5E96'); Fore = $cWhite }
        accent  = @{ Back = $cSea;   Hover = $cSeaHi;       Fore = $cWhite }
        soft    = @{ Back = $cMist;  Hover = $cMistHi;      Fore = $cDeep }
        ghost   = @{ Back = $cBg;    Hover = $cMist;        Fore = $cSoft }
    }
    $b = New-Object System.Windows.Forms.Button
    $b.Text = $text
    $b.Size = New-Object System.Drawing.Size((P $width), (P 40))
    $b.FlatStyle = 'Flat'
    $b.FlatAppearance.BorderSize = 0
    $b.Cursor = [System.Windows.Forms.Cursors]::Hand
    $b.Font = $fButton
    $t = $styles[$style].Clone(); $t.Over = $false; $t.Down = $false
    $b.Tag = $t
    Set-DoubleBuffered $b
    $b.Add_MouseEnter({ $this.Tag.Over = $true;  $this.Invalidate() })
    $b.Add_MouseLeave({ $this.Tag.Over = $false; $this.Tag.Down = $false; $this.Invalidate() })
    $b.Add_MouseDown({ $this.Tag.Down = $true;  $this.Invalidate() })
    $b.Add_MouseUp({   $this.Tag.Down = $false; $this.Invalidate() })
    $b.Add_EnabledChanged({ $this.Invalidate() })
    $b.Add_Paint({
        param($s, $e)
        $g = $e.Graphics
        $g.SmoothingMode = 'AntiAlias'
        $g.Clear($s.Parent.BackColor)
        $t = $s.Tag
        $fill = $t.Back; $fore = $t.Fore
        if (-not $s.Enabled) { $fill = $cMist; $fore = C '#A9BFCD' }
        elseif ($t.Over) { $fill = $t.Hover }
        $inset = if ($t.Down -and $s.Enabled) { 1.5 * $script:UiScale } else { 0 }
        $path = New-RoundPath $inset $inset ($s.Width - 1 - 2 * $inset) ($s.Height - 1 - 2 * $inset) (($s.Height - 1) / 2)
        $brush = New-Object System.Drawing.SolidBrush($fill)
        $g.FillPath($brush, $path); $brush.Dispose()
        if ($s.Focused -and $s.ShowFocusCues) {
            $pen = New-Object System.Drawing.Pen($cAqua, (PF 2)); $g.DrawPath($pen, $path); $pen.Dispose()
        }
        $path.Dispose()
        [System.Windows.Forms.TextRenderer]::DrawText($g, $s.Text, $s.Font, $s.ClientRectangle, $fore, $centerFlags)
    })
    return $b
}

# Toggle switch (a CheckBox drawn as a switch, so keyboard and Checked work as usual).
function New-Toggle([string]$text) {
    $c = New-Object System.Windows.Forms.CheckBox
    $c.Text = $text
    $c.Font = $fBody
    $c.AutoSize = $false
    $c.Cursor = [System.Windows.Forms.Cursors]::Hand
    $sz = [System.Windows.Forms.TextRenderer]::MeasureText($text, $fBody)
    $c.Size = New-Object System.Drawing.Size(((P 52) + $sz.Width), [Math]::Max((P 28), $sz.Height + (P 6)))
    Set-DoubleBuffered $c
    $c.Add_CheckedChanged({ $this.Invalidate() })
    $c.Add_Paint({
        param($s, $e)
        $g = $e.Graphics
        $g.SmoothingMode = 'AntiAlias'
        $g.Clear($s.Parent.BackColor)
        [float]$h = PF 22; [float]$w = PF 40; [float]$y = ($s.Height - $h) / 2
        $track = New-RoundPath 0 $y $w $h ($h / 2)
        $fillColor = if ($s.Checked) { $cSea } else { C '#C6D9E4' }
        if (-not $s.Enabled) { $fillColor = $cMist }
        $b = New-Object System.Drawing.SolidBrush($fillColor); $g.FillPath($b, $track); $b.Dispose()
        if ($s.Focused -and $s.ShowFocusCues) {
            $pen = New-Object System.Drawing.Pen($cAqua, (PF 2)); $g.DrawPath($pen, $track); $pen.Dispose()
        }
        $track.Dispose()
        [float]$k = $h - (PF 6)
        [float]$kx = if ($s.Checked) { $w - $k - (PF 3) } else { PF 3 }
        $shadow = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(40, 10, 50, 80))
        $g.FillEllipse($shadow, $kx, ($y + (PF 3.8)), $k, $k); $shadow.Dispose()
        $knob = New-Object System.Drawing.SolidBrush($cWhite)
        $g.FillEllipse($knob, $kx, ($y + (PF 3)), $k, $k); $knob.Dispose()
        $r = New-Object System.Drawing.Rectangle((P 50), 0, ($s.Width - (P 50)), $s.Height)
        $fore = if ($s.Enabled) { $cInk } else { $cGray }
        [System.Windows.Forms.TextRenderer]::DrawText($g, $s.Text, $s.Font, $r, $fore, $leftFlags)
    })
    return $c
}

# White rounded card with a soft shadow. Put content inside; it gets padding automatically.
function New-Card {
    $p = New-Object System.Windows.Forms.Panel
    $p.BackColor = $cBg
    $p.Padding = New-Object System.Windows.Forms.Padding((P 8))
    Set-DoubleBuffered $p
    $p.Add_Resize({ $this.Invalidate() })
    $p.Add_Paint({
        param($s, $e)
        $g = $e.Graphics
        $g.SmoothingMode = 'AntiAlias'
        $g.Clear($s.Parent.BackColor)
        [float]$r = PF 14; [float]$i = PF 2
        foreach ($k in 1..3) {
            $sp = New-RoundPath ($i - $k * 0.5) ($i + $k * 0.8) ($s.Width - 2 * $i + $k) ($s.Height - 2 * $i) ($r + $k)
            $sb = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(7, 10, 77, 124))
            $g.FillPath($sb, $sp); $sb.Dispose(); $sp.Dispose()
        }
        $path = New-RoundPath $i $i ($s.Width - 2 * $i - 1) ($s.Height - 2 * $i - (PF 2)) $r
        $b = New-Object System.Drawing.SolidBrush($cCard); $g.FillPath($b, $path); $b.Dispose()
        $pen = New-Object System.Drawing.Pen($cLine, (PF 1)); $g.DrawPath($pen, $path); $pen.Dispose()
        $path.Dispose()
    })
    return $p
}

# Small coloured pill with text, used for statuses.
function Draw-Badge($g, [string]$text, [int]$x, [int]$cy, $back, $fore) {
    $sz = [System.Windows.Forms.TextRenderer]::MeasureText($g, $text, $fSmall, (New-Object System.Drawing.Size(2000, 100)), $centerFlags)
    [float]$h = PF 24; [float]$w = $sz.Width + (PF 18)
    $path = New-RoundPath $x ($cy - $h / 2) $w $h ($h / 2)
    $b = New-Object System.Drawing.SolidBrush($back); $g.FillPath($b, $path); $b.Dispose(); $path.Dispose()
    $r = New-Object System.Drawing.Rectangle($x, [int]($cy - $h / 2), [int]$w, [int]$h)
    [System.Windows.Forms.TextRenderer]::DrawText($g, $text, $fSmall, $r, $fore, $centerFlags)
}

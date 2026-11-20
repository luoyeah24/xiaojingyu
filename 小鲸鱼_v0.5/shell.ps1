# 小鲸鱼桌面壳 v3 —— 悬浮可阅读提示 + 读文字/看视频
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$ErrorActionPreference = 'Stop'

$scriptDir  = Split-Path -Parent $MyInvocation.MyCommand.Path
$pageUrl    = 'http://127.0.0.1:8787/run.html'
$pageFile   = Join-Path $scriptDir 'run.html'
$posFile    = Join-Path $env:APPDATA 'fish\pos.txt'
$avatarJson = Join-Path $scriptDir 'avatar.json'
$readJson   = Join-Path $scriptDir 'read.json'
$thoughtFile = Join-Path $scriptDir 'thought.json'
$quitFile   = Join-Path $scriptDir 'quit.flag'
$SRV        = 'http://127.0.0.1:8787'

# ---------- 读状态 ----------
function Get-JsonFile($p) {
    if (-not (Test-Path -LiteralPath $p)) { return $null }
    try { return (Get-Content -LiteralPath $p -Raw -Encoding UTF8 | ConvertFrom-Json) } catch { return $null }
}

function Get-AvatarState { return Get-JsonFile $avatarJson }
function Get-ReadState   { return Get-JsonFile $readJson }

function Get-PageState {
    try {
        $r = Invoke-RestMethod -Uri "$SRV/api/page" -TimeoutSec 2 -Method Get
        return $r
    } catch { return $null }
}

function Resolve-AvatarImage($state) {
    if (-not $state) { return $null }
    $v = [string]$state.value
    if ([string]::IsNullOrWhiteSpace($v)) { return $null }
    if ($v -match '^/avatars/(.+)$') {
        $p = Join-Path (Join-Path $scriptDir 'avatars') $matches[1]
        if (Test-Path -LiteralPath $p) { return $p }
    }
    return $null
}

# ---------- 画 ----------
function Draw-Scene([int]$size, [bool]$hover, $state, $readState, [bool]$hasPage) {
    $bmp = New-Object Drawing.Bitmap($size, $size)
    $g = [Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.InterpolationMode = [Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g.Clear([Drawing.Color]::Transparent)

    $s = $size / 160.0
    $g.ScaleTransform($s, $s)

    $water = New-Object Drawing.SolidBrush ([Drawing.Color]::FromArgb($(if($hover){115}else{85}), 70, 140, 190))
    $g.FillEllipse($water, 6, 14, 148, 140)
    $ring = New-Object Drawing.Pen -ArgumentList ([Drawing.Color]::FromArgb(150, 140, 210, 240), [float]1.6)
    $g.DrawEllipse($ring, 6, 14, 148, 140)

    $imgPath = Resolve-AvatarImage $state
    $emoji = $null
    if (-not $imgPath -and $state) {
        $v = [string]$state.value
        if ($v -and $v.Length -le 8) { $emoji = $v }
    }

    if ($imgPath) {
        try {
            $im = [Drawing.Image]::FromFile($imgPath)
            $box = 116
            $sc = [Math]::Min($box / $im.Width, $box / $im.Height)
            $w = [int]($im.Width * $sc); $h = [int]($im.Height * $sc)
            $g.DrawImage($im, 80 - [int]($w/2), 84 - [int]($h/2), $w, $h)
            $im.Dispose()
        } catch { }
    }
    elseif ($emoji) {
        $f = New-Object Drawing.Font('Segoe UI Emoji', 54)
        $fmt = New-Object Drawing.StringFormat
        $fmt.Alignment = [Drawing.StringAlignment]::Center
        $fmt.LineAlignment = [Drawing.StringAlignment]::Center
        $g.DrawString($emoji, $f, [Drawing.Brushes]::White, (New-Object Drawing.RectangleF(6,14,148,140)), $fmt)
    }
    else {
        $tail = New-Object Drawing.SolidBrush ([Drawing.Color]::FromArgb(255, 92, 158, 204))
        $g.FillPolygon($tail, @(
            (New-Object Drawing.PointF(104, 86)), (New-Object Drawing.PointF(134, 68)),
            (New-Object Drawing.PointF(130, 96)), (New-Object Drawing.PointF(134, 122)),
            (New-Object Drawing.PointF(104, 104))))
        $body = New-Object Drawing.SolidBrush ([Drawing.Color]::FromArgb(255, 74, 145, 196))
        $g.FillEllipse($body, 30, 74, 82, 56)
        $belly = New-Object Drawing.SolidBrush ([Drawing.Color]::FromArgb(210, 190, 225, 240))
        $g.FillEllipse($belly, 46, 98, 56, 28)
        $g.FillEllipse([Drawing.Brushes]::White, 46, 88, 15, 15)
        $g.FillEllipse((New-Object Drawing.SolidBrush ([Drawing.Color]::FromArgb(255,20,40,60))), 51, 92, 8, 8)
        $spout = New-Object Drawing.Pen -ArgumentList ([Drawing.Color]::FromArgb(180, 170, 220, 240), [float]2.4)
        $g.DrawLine($spout, 62, 76, 58, 54)
        $g.DrawLine($spout, 66, 76, 68, 50)
        $g.DrawLine($spout, 70, 76, 78, 56)
    }

    # 读取中
    if ($readState -and [string]$readState.status -eq 'reading') {
        $bf = New-Object Drawing.Font('Microsoft YaHei', 9, [Drawing.FontStyle]::Bold)
        $fmt2 = New-Object Drawing.StringFormat
        $fmt2.Alignment = [Drawing.StringAlignment]::Center
        $g.DrawString('读取中…', $bf, [Drawing.Brushes]::White, (New-Object Drawing.RectangleF(0,4,160,18)), $fmt2)
    }
    # 有网页可读
    elseif ($hasPage) {
        $dot = New-Object Drawing.SolidBrush ([Drawing.Color]::FromArgb(255, 110, 220, 150))
        $g.FillEllipse($dot, 132, 20, 16, 16)
    }

    $g.Dispose()
    return $bmp
}

# ---------- 窗口 ----------
$form = New-Object Windows.Forms.Form
$form.FormBorderStyle = [Windows.Forms.FormBorderStyle]::None
$form.ShowInTaskbar = $false
$form.TopMost = $true
$form.StartPosition = [Windows.Forms.FormStartPosition]::Manual
$form.Size = New-Object Drawing.Size(240, 470)
$form.BackColor = [Drawing.Color]::FromArgb(255, 0, 1, 2)
$form.TransparencyKey = $form.BackColor
$form.Text = '小鲸鱼'

$x = -1; $y = -1
if (Test-Path $posFile) {
    try { $parts = (Get-Content -LiteralPath $posFile -Raw).Trim() -split ','; $x = [int]$parts[0]; $y = [int]$parts[1] } catch { }
}
if ($x -lt 0 -or $y -lt 0) {
    $screen = [Windows.Forms.Screen]::PrimaryScreen.WorkingArea
    $x = $screen.Right - 270; $y = $screen.Bottom - 390
}
$form.Location = New-Object Drawing.Point($x, $y)

$pic = New-Object Windows.Forms.PictureBox
$pic.Size = New-Object Drawing.Size(184, 184)
$pic.Location = New-Object Drawing.Point(28, 92)
$pic.SizeMode = [Windows.Forms.PictureBoxSizeMode]::Zoom
$pic.BackColor = [Drawing.Color]::Transparent
$pic.Cursor = [Windows.Forms.Cursors]::Hand
$form.Controls.Add($pic)

function New-MiniBtn([string]$text, [int]$x, [int]$y) {
    $b = New-Object Windows.Forms.Button
    $b.Text = $text
    $b.Size = New-Object Drawing.Size(86, 30)
    $b.Location = New-Object Drawing.Point($x, $y)
    $b.FlatStyle = [Windows.Forms.FlatStyle]::Flat
    $b.FlatAppearance.BorderColor = [Drawing.Color]::FromArgb(60, 120, 170)
    $b.BackColor = [Drawing.Color]::FromArgb(18, 53, 77)
    $b.ForeColor = [Drawing.Color]::White
    $b.Font = New-Object Drawing.Font('Microsoft YaHei', 9)
    $b.Cursor = [Windows.Forms.Cursors]::Hand
    $b.Visible = $false
    $form.Controls.Add($b)
    return $b
}

$btnRead  = New-MiniBtn '读文字' 30 318
$btnVideo = New-MiniBtn '看视频' 124 318
$btnTalk  = New-MiniBtn '画画'   30 352
$btnMusic = New-MiniBtn '听音乐' 124 352

# 输入框：指令 / 歌词
$inputBox = New-Object Windows.Forms.TextBox
$inputBox.Size = New-Object Drawing.Size(168, 26)
$inputBox.Location = New-Object Drawing.Point(6, 392)
$inputBox.BorderStyle = [Windows.Forms.BorderStyle]::FixedSingle
$inputBox.BackColor = [Drawing.Color]::FromArgb(32, 62, 86)
$inputBox.ForeColor = [Drawing.Color]::White
$inputBox.Font = New-Object Drawing.Font('Microsoft YaHei', 9)
try { $inputBox.PlaceholderText = '指令 / 歌词…' } catch { $inputBox.Text = '' }
$inputBox.Visible = $false
$form.Controls.Add($inputBox)

# 输入框末尾的"说话"按钮
$btnSay = New-Object Windows.Forms.Button
$btnSay.Text = '说话'
$btnSay.Size = New-Object Drawing.Size(52, 28)
$btnSay.Location = New-Object Drawing.Point(180, 390)
$btnSay.FlatStyle = [Windows.Forms.FlatStyle]::Flat
$btnSay.FlatAppearance.BorderColor = [Drawing.Color]::FromArgb(60, 120, 170)
$btnSay.BackColor = [Drawing.Color]::FromArgb(45, 127, 184)
$btnSay.ForeColor = [Drawing.Color]::White
$btnSay.Font = New-Object Drawing.Font('Microsoft YaHei', 9)
$btnSay.Cursor = [Windows.Forms.Cursors]::Hand
$btnSay.Visible = $false
$form.Controls.Add($btnSay)

$btnSay.Add_Click({ Send-Action 'talk' })

# 点一下就拿到焦点
$inputBox.Add_Click({
    $form.Activate()
    $inputBox.Focus()
})
$inputBox.Add_Enter({ $hoverGuard.Stop() })
$inputBox.Add_Leave({ $hoverGuard.Start() })

# 打字时告诉网页"我在听"
$script:lastTypePost = [DateTime]::MinValue
$inputBox.Add_TextChanged({
    $now = Get-Date
    if (($now - $script:lastTypePost).TotalMilliseconds -gt 1400) {
        $script:lastTypePost = $now
        try {
            $b = @{ on = $true } | ConvertTo-Json -Compress
            Invoke-RestMethod -Uri "$SRV/api/typing" -Method Post -ContentType 'application/json' -Body ([System.Text.Encoding]::UTF8.GetBytes($b)) -TimeoutSec 2 | Out-Null
        } catch {}
    }
})

$hint = New-Object Windows.Forms.Label
$hint.Text = ''
$hint.Size = New-Object Drawing.Size(240, 24)
$hint.Location = New-Object Drawing.Point(0, 432)
$hint.TextAlign = [Drawing.ContentAlignment]::MiddleCenter
$hint.ForeColor = [Drawing.Color]::FromArgb(230, 200, 120)
$hint.BackColor = [Drawing.Color]::FromArgb(18, 53, 77)
$hint.Font = New-Object Drawing.Font('Microsoft YaHei', 8.5)
$hint.Visible = $false
$form.Controls.Add($hint)

# 想法气泡
$bubble = New-Object Windows.Forms.RichTextBox
$bubble.Text = ''
$bubble.Size = New-Object Drawing.Size(232, 84)
$bubble.Location = New-Object Drawing.Point(4, 4)
$bubble.ReadOnly = $true
$bubble.BorderStyle = [Windows.Forms.BorderStyle]::None
$bubble.ScrollBars = [Windows.Forms.RichTextBoxScrollBars]::Vertical
$bubble.DetectUrls = $false
$bubble.BackColor = [Drawing.Color]::FromArgb(240, 250, 252)
$bubble.ForeColor = [Drawing.Color]::FromArgb(18, 40, 58)
$bubble.Font = New-Object Drawing.Font('Microsoft YaHei', 9)
$bubble.Visible = $false
$bubble.Padding = New-Object Windows.Forms.Padding(8)
$form.Controls.Add($bubble)
$bubble.BringToFront()

$script:lastThoughtAt = ''
$script:thoughtTimer = New-Object Windows.Forms.Timer
$script:thoughtTimer.Interval = 6000
$script:thoughtTimer.Add_Tick({ $script:thoughtTimer.Stop(); $bubble.Visible = $false })

function Refresh-Thought {
    $th = Get-JsonFile $thoughtFile
    if (-not $th) { return }
    $text = [string]$th.text
    $at = [string]$th.at
    if ([string]::IsNullOrWhiteSpace($text) -or $at -eq $script:lastThoughtAt) { return }
    $script:lastThoughtAt = $at
    $bubble.Text = $text
    if ($text.Length -gt 70) { $bubble.Height = 132 }
    elseif ($text.Length -gt 36) { $bubble.Height = 108 }
    else { $bubble.Height = 84 }
    $bubble.Visible = $true
    $bubble.BringToFront()
    $script:thoughtTimer.Stop()
    $script:thoughtTimer.Interval = if ($text.Length -gt 60) { 12000 } else { 6000 }
    $script:thoughtTimer.Start()
}

$script:stateKey = ''
$script:hover = $false
$script:hasPage = $false
$script:pageTitle = ''

function Refresh-Scene {
    $st = Get-AvatarState
    $rd = Get-ReadState
    $key = "{0}|{1}|{2}|{3}" -f $(if($st){$st.value}else{''}), $(if($rd){$rd.status}else{''}), $script:hover, $script:hasPage
    if ($key -eq $script:stateKey) { return }
    $script:stateKey = $key
    $old = $pic.Image
    $pic.Image = Draw-Scene 184 $script:hover $st $rd $script:hasPage
    if ($old) { $old.Dispose() }
}

function Show-Menu([bool]$on) {
    $btnRead.Visible = $on
    $btnVideo.Visible = $on
    $btnTalk.Visible = $on
    $btnMusic.Visible = $on
    $inputBox.Visible = $on
    $btnSay.Visible = $on
}

$script:doing = ''
function Refresh-State {
    if (Test-Path -LiteralPath $quitFile) {
        Remove-Item -LiteralPath $quitFile -Force -ErrorAction SilentlyContinue
        $form.Close()
        return
    }
    try {
        $s = Invoke-RestMethod -Uri "$SRV/api/state" -TimeoutSec 2 -Method Get
        $d = [string]$s.doing
        if ($d) { $script:doing = $d }
    } catch { }
    $txt = if ($script:doing) { '在' + $script:doing } else { '' }
    if ($hint.Text -ne $txt -and -not $script:holdHint) {
        $hint.Text = $txt
        $hint.Visible = [bool]$txt
    }
}

function Refresh-Page {
    $p = Get-PageState
    $title = if ($p) { [string]$p.title } else { '' }
    $script:hasPage = -not [string]::IsNullOrWhiteSpace($title)
    $script:pageTitle = $title
    Refresh-Scene
}

function Send-Action([string]$action) {
    $txt = if ($inputBox) { $inputBox.Text.Trim() } else { '' }
    try {
        $body = @{ action = $action; text = $txt } | ConvertTo-Json -Compress
        Invoke-RestMethod -Uri "$SRV/api/action" -Method Post -ContentType 'application/json; charset=utf-8' -Body ([System.Text.Encoding]::UTF8.GetBytes($body)) -TimeoutSec 3 | Out-Null
        $hint.Text = if ($action -eq 'music') { '在听歌…' } else { '她在等你说话' }
        $hint.Visible = $true
    } catch {
        $hint.Text = '本地服务没开'
        $hint.Visible = $true
    }
}

function Open-Page {
    try {
        Invoke-WebRequest -Uri "$SRV/api/avatar" -TimeoutSec 2 -UseBasicParsing | Out-Null
        Start-Process $pageUrl
    } catch { Start-Process $pageFile }
}

function Send-Request([string]$action) {
    if (-not $script:hasPage) {
        $hint.Text = '没检测到网页：扩展连上了吗'
        $hint.Visible = $true
        return
    }
    $rd0 = Get-ReadState
    $script:beforeStatus = if ($rd0) { [string]$rd0.status } else { '' }

    try {
        $body = @{ action = $action; text = $($inputBox.Text.Trim()) } | ConvertTo-Json -Compress
        Invoke-RestMethod -Uri "$SRV/api/request" -Method Post -ContentType 'application/json; charset=utf-8' -Body ([System.Text.Encoding]::UTF8.GetBytes($body)) -TimeoutSec 3 | Out-Null
        $hint.Text = if ($action -eq 'video') { '正在看视频页…' } else { '正在读这一页…' }
        $hint.Visible = $true
        Refresh-Scene

        $script:chk.Stop()
        $script:chk.Start()
    } catch {
        $hint.Text = '本地服务没开（server.ps1）'
        $hint.Visible = $true
    }
}

$btnRead.Add_Click({ Send-Request 'read' })
$btnVideo.Add_Click({ Send-Request 'video' })
$btnTalk.Add_Click({ Send-Action 'draw' })
$btnMusic.Add_Click({ Send-Action 'music' })

# 鼠标离开就收起来
$hoverGuard = New-Object Windows.Forms.Timer
$hoverGuard.Interval = 200
$hoverGuard.Add_Tick({
    if ($btnRead.Visible -and -not $form.Bounds.Contains([Windows.Forms.Cursor]::Position)) {
        $script:hover = $false
        Show-Menu $false
        Refresh-Scene
    }
})
$hoverGuard.Start()

# 4 秒后检查扩展有没有接活
$script:beforeStatus = ''
$script:chk = New-Object Windows.Forms.Timer
$script:chk.Interval = 4500
$script:chk.Add_Tick({
    $script:chk.Stop()
    $rd = Get-ReadState
    $st = if ($rd) { [string]$rd.status } else { '' }
    if ($st -eq 'idle' -or $st -eq $script:beforeStatus) {
        $hint.Text = '扩展没连上，去 edge://extensions 重新加载'
        $hint.Visible = $true
    }
})

# ---------- 交互 ----------
$script:dragging = $false
$script:moved = $false
$script:downPt = New-Object Drawing.Point(0, 0)

$pic.Add_MouseDown({
    param($s, $e)
    if ($e.Button -eq [Windows.Forms.MouseButtons]::Left) {
        $script:dragging = $true; $script:moved = $false; $script:downPt = $e.Location
    }
})

$pic.Add_MouseMove({
    param($s, $e)
    if ($script:dragging) {
        $dx = $e.X - $script:downPt.X; $dy = $e.Y - $script:downPt.Y
        if ([Math]::Abs($dx) + [Math]::Abs($dy) -gt 3) { $script:moved = $true }
        $form.Left += $dx; $form.Top += $dy
    }
})

$pic.Add_MouseUp({
    param($s, $e)
    $script:dragging = $false
    if (-not $script:moved) { Open-Page }
    try {
        New-Item -ItemType Directory -Force -Path (Split-Path $posFile) | Out-Null
        "$($form.Left),$($form.Top)" | Set-Content -LiteralPath $posFile -Encoding ASCII
    } catch { }
})

$pic.Add_MouseEnter({ $script:hover = $true; Show-Menu $true; Refresh-Scene })

$form.Add_MouseLeave({
    if (-not $form.Bounds.Contains([Windows.Forms.Cursor]::Position)) {
        $script:hover = $false
        Show-Menu $false
        Refresh-Scene
    }
})

# ---------- 右键 ----------
$menu = New-Object Windows.Forms.ContextMenuStrip
$miOpen = $menu.Items.Add('打开面板')
$miTop = $menu.Items.Add('取消置顶')
$null = $menu.Items.Add('-')
$miExit = $menu.Items.Add('退出')
$miOpen.Add_Click({ Open-Page })
$miTop.Add_Click({
    $form.TopMost = -not $form.TopMost
    $miTop.Text = if ($form.TopMost) { '取消置顶' } else { '保持置顶' }
})
$miExit.Add_Click({ $form.Close() })
$pic.ContextMenuStrip = $menu

# ---------- 定时 ----------
$t1 = New-Object Windows.Forms.Timer
$t1.Interval = 2000
$t1.Add_Tick({ Refresh-Scene })
$t1.Start()

$t2 = New-Object Windows.Forms.Timer
$t2.Interval = 3000
$t2.Add_Tick({ Refresh-Page; Refresh-Thought; Refresh-State })
$t2.Start()

Refresh-Page
Refresh-Scene
[Windows.Forms.Application]::Run($form)

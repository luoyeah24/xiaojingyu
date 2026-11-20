# 小鲸鱼本地服务：给页面和桌面壳提供同一份形象数据
# 只监听 127.0.0.1:8787，不对外

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$avatarsDir = Join-Path $root 'avatars'
if (-not (Test-Path $avatarsDir)) { New-Item -ItemType Directory -Path $avatarsDir -Force | Out-Null }

$avatarFile = Join-Path $root 'avatar.json'
$readFile   = Join-Path $root 'read.json'
$pageFile   = Join-Path $root 'page.json'
$reqFile    = Join-Path $root 'request.json'
$thoughtFile = Join-Path $root 'thought.json'
$actionFile  = Join-Path $root 'action.json'
$typingFile  = Join-Path $root 'typing.json'
$stateFile   = Join-Path $root 'state.json'
$keyFile     = Join-Path $root 'apikey.json'

$mime = @{
    '.html' = 'text/html; charset=utf-8'
    '.js'   = 'application/javascript; charset=utf-8'
    '.css'  = 'text/css; charset=utf-8'
    '.json' = 'application/json; charset=utf-8'
    '.csv'  = 'text/csv; charset=utf-8'
    '.png'  = 'image/png'
    '.jpg'  = 'image/jpeg'
    '.jpeg' = 'image/jpeg'
    '.webp' = 'image/webp'
    '.gif'  = 'image/gif'
    '.svg'  = 'image/svg+xml'
    '.ico'  = 'image/x-icon'
}

$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add('http://127.0.0.1:8787/')
try { $listener.Start() } catch {
    Write-Host "端口 8787 被占用，退出"
    exit 1
}

Write-Host "小鲸鱼服务已启动： http://127.0.0.1:8787/"

function Send-Bytes($ctx, [byte[]]$bytes, [string]$type, [int]$code = 200) {
    $r = $ctx.Response
    $r.StatusCode = $code
    $r.ContentType = $type
    $r.Headers.Add('Access-Control-Allow-Origin', '*')
    $r.Headers.Add('Access-Control-Allow-Headers', '*')
    $r.Headers.Add('Access-Control-Allow-Methods', 'GET, POST, OPTIONS')
    $r.Headers.Add('Cache-Control', 'no-store')
    $r.ContentLength64 = $bytes.Length
    $r.OutputStream.Write($bytes, 0, $bytes.Length)
    $r.OutputStream.Close()
}

function Send-Text($ctx, [string]$text, [int]$code = 200) {
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($text)
    Send-Bytes $ctx $bytes 'application/json; charset=utf-8' $code
}

while ($listener.IsListening) {
    try {
        $ctx = $listener.GetContext()
        $req = $ctx.Request
        $path = $req.Url.AbsolutePath

        if ($req.HttpMethod -eq 'OPTIONS') {
            Send-Text $ctx '{}' 204
            continue
        }

        # --- 默认形象列表 ---
        if ($path -eq '/api/avatars') {
            $files = @()
            Get-ChildItem -LiteralPath $avatarsDir -File -ErrorAction SilentlyContinue |
                Where-Object { $_.Extension -match '^\.(png|jpe?g|webp|gif|svg)$' } |
                ForEach-Object { $files += $_.Name }
            Send-Text $ctx ($files | ConvertTo-Json -Compress)
            continue
        }

        # --- 当前形象 ---
        if ($path -eq '/api/avatar') {
            if ($req.HttpMethod -eq 'POST') {
                $sr = New-Object System.IO.StreamReader($req.InputStream, [System.Text.Encoding]::UTF8)
                $body = $sr.ReadToEnd()
                $sr.Close()
                try {
                    $obj = $body | ConvertFrom-Json
                    # 只保存小的记录：emoji 或 /avatars/xxx.png
                    $val = [string]$obj.value
                    if ($val.Length -gt 400) { $val = '' }   # data: 太长不落盘
                    @{ value = $val; kind = [string]$obj.kind; at = (Get-Date).ToString('s') } |
                        ConvertTo-Json -Compress | Set-Content -LiteralPath $avatarFile -Encoding UTF8
                    Send-Text $ctx '{"ok":true}'
                } catch {
                    Send-Text $ctx '{"ok":false}' 400
                }
                continue
            }
            if (Test-Path -LiteralPath $avatarFile) {
                $json = Get-Content -LiteralPath $avatarFile -Raw -Encoding UTF8
                Send-Text $ctx $json
            } else {
                Send-Text $ctx '{"value":"","kind":"emoji"}'
            }
            continue
        }

        # --- 退出（网页上点退出） ---
        if ($path -eq '/api/quit') {
            Send-Text $ctx '{"ok":true}'
            '1' | Set-Content -LiteralPath (Join-Path $root 'quit.flag') -Encoding ASCII
            Start-Sleep -Milliseconds 400
            $listener.Stop()
            break
        }

        # --- 共用 Key（网页写，扩展读） ---
        if ($path -eq '/api/key') {
            if ($req.HttpMethod -eq 'POST') {
                $sr = New-Object System.IO.StreamReader($req.InputStream, [System.Text.Encoding]::UTF8)
                $body = $sr.ReadToEnd(); $sr.Close()
                try {
                    $obj = $body | ConvertFrom-Json
                    @{ key = [string]$obj.key; base = [string]$obj.base; model = [string]$obj.model } |
                        ConvertTo-Json -Compress | Set-Content -LiteralPath $keyFile -Encoding UTF8
                    Send-Text $ctx '{"ok":true}'
                } catch { Send-Text $ctx '{"ok":false}' 400 }
                continue
            }
            if (Test-Path -LiteralPath $keyFile) {
                Send-Text $ctx (Get-Content -LiteralPath $keyFile -Raw -Encoding UTF8)
            } else {
                Send-Text $ctx '{"key":"","base":"","model":""}'
            }
            continue
        }

        # --- 她的当前状态（桌面壳显示） ---
        if ($path -eq '/api/state') {
            if ($req.HttpMethod -eq 'POST') {
                $sr = New-Object System.IO.StreamReader($req.InputStream, [System.Text.Encoding]::UTF8)
                $body = $sr.ReadToEnd(); $sr.Close()
                try {
                    $obj = $body | ConvertFrom-Json
                    @{
                        doing   = [string]$obj.doing
                        mood    = [string]$obj.mood
                        place   = [string]$obj.place
                        energy  = [int]$obj.energy
                        stamina = [int]$obj.stamina
                        trait   = [string]$obj.trait
                        at      = (Get-Date).ToString('s')
                    } | ConvertTo-Json -Compress | Set-Content -LiteralPath $stateFile -Encoding UTF8
                    Send-Text $ctx '{"ok":true}'
                } catch { Send-Text $ctx '{"ok":false}' 400 }
                continue
            }
            if (Test-Path -LiteralPath $stateFile) {
                Send-Text $ctx (Get-Content -LiteralPath $stateFile -Raw -Encoding UTF8)
            } else {
                Send-Text $ctx '{"doing":"","mood":"","place":""}'
            }
            continue
        }

        # --- 桌面壳正在打字（网页照着显示"我在听"） ---
        if ($path -eq '/api/typing') {
            if ($req.HttpMethod -eq 'POST') {
                $sr = New-Object System.IO.StreamReader($req.InputStream, [System.Text.Encoding]::UTF8)
                $body = $sr.ReadToEnd(); $sr.Close()
                try {
                    $obj = $body | ConvertFrom-Json
                    @{ on = [bool]$obj.on; at = (Get-Date).ToString('s') } |
                        ConvertTo-Json -Compress | Set-Content -LiteralPath $typingFile -Encoding UTF8
                    Send-Text $ctx '{"ok":true}'
                } catch { Send-Text $ctx '{"ok":false}' 400 }
                continue
            }
            if (Test-Path -LiteralPath $typingFile) {
                Send-Text $ctx (Get-Content -LiteralPath $typingFile -Raw -Encoding UTF8)
            } else {
                Send-Text $ctx '{"on":false,"at":""}'
            }
            continue
        }

        # --- 桌面壳发给网页的动作（网页来取） ---
        if ($path -eq '/api/action') {
            if ($req.HttpMethod -eq 'POST') {
                $sr = New-Object System.IO.StreamReader($req.InputStream, [System.Text.Encoding]::UTF8)
                $body = $sr.ReadToEnd(); $sr.Close()
                try {
                    $obj = $body | ConvertFrom-Json
                    @{ action = [string]$obj.action; text = [string]$obj.text; at = (Get-Date).ToString('s') } |
                        ConvertTo-Json -Compress | Set-Content -LiteralPath $actionFile -Encoding UTF8
                    Send-Text $ctx '{"ok":true}'
                } catch { Send-Text $ctx '{"ok":false}' 400 }
                continue
            }
            $content = '{"action":"","text":""}'
            if (Test-Path -LiteralPath $actionFile) {
                $content = Get-Content -LiteralPath $actionFile -Raw -Encoding UTF8
            }
            Send-Text $ctx $content
            '{"action":"","text":""}' | Set-Content -LiteralPath $actionFile -Encoding UTF8
            continue
        }

        # --- 她刚冒出的想法 ---
        if ($path -eq '/api/thought') {
            if ($req.HttpMethod -eq 'POST') {
                $sr = New-Object System.IO.StreamReader($req.InputStream, [System.Text.Encoding]::UTF8)
                $body = $sr.ReadToEnd(); $sr.Close()
                try {
                    $obj = $body | ConvertFrom-Json
                    @{ text = [string]$obj.text; at = (Get-Date).ToString('s') } |
                        ConvertTo-Json -Compress | Set-Content -LiteralPath $thoughtFile -Encoding UTF8
                    Send-Text $ctx '{"ok":true}'
                } catch { Send-Text $ctx '{"ok":false}' 400 }
                continue
            }
            if (Test-Path -LiteralPath $thoughtFile) {
                Send-Text $ctx (Get-Content -LiteralPath $thoughtFile -Raw -Encoding UTF8)
            } else {
                Send-Text $ctx '{"text":"","at":""}'
            }
            continue
        }

        # --- 当前页（扩展上报） ---
        if ($path -eq '/api/page') {
            if ($req.HttpMethod -eq 'POST') {
                $sr = New-Object System.IO.StreamReader($req.InputStream, [System.Text.Encoding]::UTF8)
                $body = $sr.ReadToEnd(); $sr.Close()
                try {
                    $obj = $body | ConvertFrom-Json
                    @{ title = [string]$obj.title; url = [string]$obj.url; at = (Get-Date).ToString('s') } |
                        ConvertTo-Json -Compress | Set-Content -LiteralPath $pageFile -Encoding UTF8
                    Send-Text $ctx '{"ok":true}'
                } catch { Send-Text $ctx '{"ok":false}' 400 }
                continue
            }
            if (Test-Path -LiteralPath $pageFile) {
                Send-Text $ctx (Get-Content -LiteralPath $pageFile -Raw -Encoding UTF8)
            } else {
                Send-Text $ctx '{"title":"","url":""}'
            }
            continue
        }

        # --- 桌面壳发起的请求（扩展来取） ---
        if ($path -eq '/api/request') {
            if ($req.HttpMethod -eq 'POST') {
                $sr = New-Object System.IO.StreamReader($req.InputStream, [System.Text.Encoding]::UTF8)
                $body = $sr.ReadToEnd(); $sr.Close()
                try {
                    $obj = $body | ConvertFrom-Json
                    @{ action = [string]$obj.action; text = [string]$obj.text; at = (Get-Date).ToString('s') } |
                        ConvertTo-Json -Compress | Set-Content -LiteralPath $reqFile -Encoding UTF8
                    Send-Text $ctx '{"ok":true}'
                } catch { Send-Text $ctx '{"ok":false}' 400 }
                continue
            }
            $content = '{"action":"","text":""}'
            if (Test-Path -LiteralPath $reqFile) {
                $content = Get-Content -LiteralPath $reqFile -Raw -Encoding UTF8
            }
            Send-Text $ctx $content
            # 取走即清空，避免重复执行
            '{"action":"","text":""}' | Set-Content -LiteralPath $reqFile -Encoding UTF8
            continue
        }

        # --- 阅读状态 ---
        if ($path -eq '/api/read') {
            if ($req.HttpMethod -eq 'POST') {
                $sr = New-Object System.IO.StreamReader($req.InputStream, [System.Text.Encoding]::UTF8)
                $body = $sr.ReadToEnd()
                $sr.Close()
                try {
                    $obj = $body | ConvertFrom-Json
                    $rec = @{
                        status  = [string]$obj.status
                        title   = [string]$obj.title
                        url     = [string]$obj.url
                        summary = [string]$obj.summary
                        tokens  = [int]($obj.tokens)
                        at      = (Get-Date).ToString('s')
                    }
                    $rec | ConvertTo-Json -Compress | Set-Content -LiteralPath $readFile -Encoding UTF8
                    Send-Text $ctx '{"ok":true}'
                } catch {
                    Send-Text $ctx '{"ok":false}' 400
                }
                continue
            }
            if (Test-Path -LiteralPath $readFile) {
                Send-Text $ctx (Get-Content -LiteralPath $readFile -Raw -Encoding UTF8)
            } else {
                Send-Text $ctx '{"status":"idle"}'
            }
            continue
        }

        # --- 静态文件 ---
        $rel = [System.Uri]::UnescapeDataString($path.TrimStart('/'))
        if ([string]::IsNullOrWhiteSpace($rel)) { $rel = 'run.html' }
        $full = Join-Path $root $rel

        # 防目录穿越
        $fullNorm = [System.IO.Path]::GetFullPath($full)
        if (-not $fullNorm.StartsWith([System.IO.Path]::GetFullPath($root), [System.StringComparison]::OrdinalIgnoreCase)) {
            Send-Text $ctx '{"error":"forbidden"}' 403
            continue
        }

        if (-not (Test-Path -LiteralPath $fullNorm)) {
            Send-Text $ctx '{"error":"not found"}' 404
            continue
        }

        $ext = [System.IO.Path]::GetExtension($fullNorm).ToLower()
        $type = if ($mime.ContainsKey($ext)) { $mime[$ext] } else { 'application/octet-stream' }
        $bytes = [System.IO.File]::ReadAllBytes($fullNorm)
        Send-Bytes $ctx $bytes $type
    } catch {
        # 单个请求出错不要杀死服务
    }
}

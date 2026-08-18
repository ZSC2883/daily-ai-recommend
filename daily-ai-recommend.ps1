# ============================================================
# daily-ai-recommend.ps1
# 每天生成当日 AI 推荐并桌面弹窗（未点「确定」不消失）
# 由 Windows 任务计划程序触发，独立于 Claude Code 交互会话
# 输出（不再生成任何带日期的文件）：
#   今日推荐.html —— 唯一展示页面，每天覆盖更新
#   历史.md      —— 每日记录归档，只保留最近 30 天
# 用法：powershell -File daily-ai-recommend.ps1        (生成+弹窗)
#       powershell -File daily-ai-recommend.ps1 -Test  (仅生成，不弹窗)
#       powershell -File daily-ai-recommend.ps1 -RenderOnly  (从历史.md当日记录重渲染页面)
# ============================================================
param(
    [switch]$Test,
    [switch]$RenderOnly
)

$ErrorActionPreference = "Stop"

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$dir = $PSScriptRoot
if (-not (Test-Path $dir)) {
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
}

# 自动探测 claude CLI（优先底层 exe，避免 cmd 中文编码问题）
$claudeCmd = Get-Command claude -ErrorAction SilentlyContinue
if (-not $claudeCmd) {
    Write-Output "错误：未找到 claude CLI，请先安装 Claude Code 并登录"
    exit 1
}
$claudeExe = $claudeCmd.Source
$candidateExe = Join-Path (Split-Path $claudeCmd.Source) "node_modules\@anthropic-ai\claude-code\bin\claude.exe"
if (Test-Path $candidateExe) { $claudeExe = $candidateExe }

$today = Get-Date -Format "yyyy年M月d日"
$dateStr     = Get-Date -Format "yyyy-MM-dd"
$historyPath = Join-Path $dir "历史.md"
$pagePath    = Join-Path $dir "今日推荐.html"

# ---- 已收藏/已推荐过的不再推荐：读收藏清单 + 全部历史记录，喂给提示词并按链接过滤 ----
$favUrls = @(); $favNames = @(); $histUrls = @(); $histNames = @()
$favFile = Join-Path $dir "favorites.json"
if (Test-Path $favFile) {
    try {
        $favsRaw = Get-Content -Path $favFile -Raw -Encoding UTF8 | ConvertFrom-Json
        $favUrls  = @($favsRaw | ForEach-Object { $_.url }  | Where-Object { $_ })
        $favNames = @($favsRaw | ForEach-Object { $_.name } | Where-Object { $_ })
    } catch { }
}
if (Test-Path $historyPath) {
    try {
        $histText = Get-Content -Path $historyPath -Raw -Encoding UTF8
        $histNames = @([regex]::Matches($histText, '(?m)^###\s+\d+\.\s*(.+?)\s*$') | ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique)
        $histUrls  = @([regex]::Matches($histText, '(?m)^-\s*\*\*链接\*\*[：:]\s*(.+?)\s*$') | ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique)
    } catch { }
}
$excludeNames = @(($favNames + $histNames) | Where-Object { $_ } | Select-Object -Unique)
$excludeUrls  = @(($favUrls  + $histUrls)  | Where-Object { $_ } | Select-Object -Unique)
$excludeNote = ""
if ($excludeNames.Count -gt 0) {
    $excludeNote = "重要：以下项目用户已经收藏过或之前已经推荐过（历史里有记录），这次绝不能再推荐，同名或同一仓库的不同叫法都算重复：$($excludeNames -join '、')。必须挑名单之外的全新项目。"
}

$prompt = "请联网搜索过去24小时内(今天是$today)GitHub上最新发布或热门的、与AI相关的开源插件、工具、MCP服务器、Claude/Agent技能。要求：必须是开源、可实际下载使用的项目（有代码仓库、有安装或使用方式），不要闭源商业产品、不要只有营销文案没有实物的内容。以 GitHub 为主，可少量补充其他平台的开源项目。挑选12个最有价值的（系统会从中剔除重复项后精选8条展示，所以宁多勿少）。用中文输出，每个条目单独一行，格式严格为：名称 || 介绍 || 链接 || 使用方法（四个字段用两个竖线分隔，不要序号，不要markdown语法，不要其他任何文字）。介绍要求：面向普通用户，用一句通俗的话讲清楚核心功能、解决什么问题；不要罗列上线时间、星数、融资、版本号等次要信息。使用方法要求：用中文分号分隔成几个要点，每个要点用「标签：内容」的格式写，标签固定用：安装、部署、使用技巧、常见指令（可只写有内容的几项），尤其要说明该工具在 Claude/Claude Code 里如何安装配置使用（若是 Claude 技能或 MCP，给出安装命令和典型用法）。最后单独一行输出：参考来源域名：xxx"
if ($excludeNote -ne "") { $prompt += $excludeNote }

# ---- 历史记录格式化与解析（正反两方向，保证 -RenderOnly 能从历史还原页面） ----
function Normalize-Url([string]$u) {
    if ([string]::IsNullOrWhiteSpace($u)) { return "" }
    $u = $u.Trim().ToLowerInvariant()
    $u = $u -replace '^https?://', ''
    $u = $u -replace '^www\.', ''
    return $u.TrimEnd('/')
}

function Format-HistorySection {
    param([string]$Date, $Items, [string]$SourcesLine, $FundNames)
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append("## $Date`r`n")
    $i = 0
    foreach ($it in $Items) {
        $i++
        [void]$sb.Append("`r`n### $i. $($it.Name)`r`n`r`n")
        [void]$sb.Append("- **介绍**：$($it.Desc)`r`n")
        if ($it.Url) { [void]$sb.Append("- **链接**：$($it.Url)`r`n") }
        foreach ($seg in ($it.Usage -split '[；;]')) {
            $seg = $seg.Trim()
            if ($seg -ne "") { [void]$sb.Append("- $seg`r`n") }
        }
    }
    if ($SourcesLine -ne "") { [void]$sb.Append("`r`n- $SourcesLine`r`n") }
    if ($FundNames.Count -gt 0) {
        [void]$sb.Append("`r`n### 基金黄金`r`n`r`n")
        foreach ($f in $FundNames) { [void]$sb.Append("- $f`r`n") }
    }
    return $sb.ToString()
}

function Parse-HistorySection {
    param([string]$SectionText)
    $items = @(); $sources = ""; $funds = @()
    $mainPart = $SectionText
    $fundIdx = $SectionText.IndexOf("### 基金黄金")
    if ($fundIdx -ge 0) {
        $fundPart = $SectionText.Substring($fundIdx + 8)
        $mainPart = $SectionText.Substring(0, $fundIdx)
        foreach ($fl in ($fundPart -split "`r?`n")) {
            $fl = $fl.Trim() -replace '^-\s*', ''
            if ($fl -ne "") { $funds += $fl }
        }
    }
    $curName = ""; $curDesc = ""; $curUrl = ""; $usageSegs = @()
    foreach ($line in ($mainPart -split "`r?`n")) {
        $t = $line.Trim()
        if ($t -eq "") { continue }
        if ($t -match '^###\s+\d+\.\s*(.+)$') {
            if ($curName -ne "") {
                $items += [PSCustomObject]@{ Name = $curName; Desc = $curDesc; Url = $curUrl; Usage = ($usageSegs -join '；') }
            }
            $curName = $Matches[1].Trim(); $curDesc = ""; $curUrl = ""; $usageSegs = @()
            continue
        }
        if ($t -match '^-\s*参考来源') { $sources = ($t -replace '^-\s*', ''); continue }
        if ($t -match '^-\s*\*\*介绍\*\*[：:]\s*(.*)$') { $curDesc = $Matches[1].Trim(); continue }
        if ($t -match '^-\s*\*\*链接\*\*[：:]\s*(.*)$') { $curUrl = $Matches[1].Trim(); continue }
        if ($t -match '^-\s*(.+)$') {
            $seg = $Matches[1].Trim() -replace '\*\*', ''
            if ($seg -ne "") { $usageSegs += $seg }
            continue
        }
        if ($curName -ne "" -and $curDesc -eq "") { $curDesc = $t }
    }
    if ($curName -ne "") {
        $items += [PSCustomObject]@{ Name = $curName; Desc = $curDesc; Url = $curUrl; Usage = ($usageSegs -join '；') }
    }
    return @{ Items = $items; Sources = $sources; Funds = $funds }
}

function Update-History {
    param([string]$Date, [string]$SectionText)
    $sections = @()
    if (Test-Path $historyPath) {
        $histRaw = Get-Content -Path $historyPath -Raw -Encoding UTF8
        if ($histRaw) {
            foreach ($p in ($histRaw -split '(?m)^## ')) {
                $p = $p.Trim()
                if ($p -match '^\d{4}-\d{2}-\d{2}') { $sections += "## $p" }
            }
        }
    }
    $sections = @($sections | Where-Object { -not $_.StartsWith("## $Date") })
    $sections += $SectionText.Trim()
    if ($sections.Count -gt 30) {
        $sections = $sections[($sections.Count - 30)..($sections.Count - 1)]
    }
    $header = "# 每日推荐历史（自动保留最近 30 天）`r`n`r`n"
    Set-Content -Path $historyPath -Value ($header + ($sections -join "`r`n`r`n") + "`r`n") -Encoding UTF8
}

if ($RenderOnly) {
    # 从历史.md取当日记录重新渲染页面，不联网不重写历史
    $content = "历史.md 中没有 $dateStr 的记录，请先运行正常生成"
    $items = @(); $sourcesLine = ""; $fundNames = @()
    if (Test-Path $historyPath) {
        $histRaw = Get-Content -Path $historyPath -Raw -Encoding UTF8
        if ($histRaw -match ("(?ms)^## " + $dateStr + "\r?\n.*?(?=^## |\z)")) {
            $body = $Matches[0] -replace ("(?m)^## " + $dateStr + "\r?\n"), ""
            $parsed = Parse-HistorySection -SectionText $body
            $items = $parsed.Items; $sourcesLine = $parsed.Sources; $fundNames = $parsed.Funds
            # 页面只展示当日最新的 8 条（更早的重跑旧条目仅留档）
            $items = @($items | Select-Object -First 8)
            if ($items.Count -gt 0) { $content = "" }
        }
    }
} else {
    try {
        $raw = & $claudeExe -p $prompt --output-format text --allowedTools "WebSearch" 2>&1 | Out-String
    } catch {
        $raw = "生成失败：$($_.Exception.Message)"
    }
    $content = $raw.Trim()
    if ([string]::IsNullOrWhiteSpace($content)) {
        $content = "生成失败：claude 未返回内容（可能网络异常或额度不足）"
    }
}

# ---- 基金黄金（可选本地模块 fund.ps1，被 .gitignore 排除不公开；无此文件则自动跳过） ----
if ($RenderOnly) {
    # fundNames 已从历史.md解析
} elseif (Test-Path (Join-Path $dir "fund.ps1")) {
    . (Join-Path $dir "fund.ps1")
    $fundContent = Get-DailyFund -ClaudeExe $claudeExe -Today $today
} else {
    $fundContent = ""
}

# ---- 归档逻辑见文件头部的 Format-HistorySection / Update-History ----

# ---- 解析为卡片条目 ----
if (-not $RenderOnly) {
    $items = @()
    $sourcesLine = ""
    foreach ($rawLine in ($content -split "`r?`n")) {
        $line = $rawLine.Trim()
        if ([string]::IsNullOrWhiteSpace($line)) { continue }

        if ($line -match '参考来源|来源域名|^Sources') {
            $sourcesLine = $line
            continue
        }

        if ($line -match '\|\|') {
            $parts = $line -split '\|\|', 4
            $name = $parts[0].Trim() -replace '^\d+[\.、\)]\s*', '' -replace '^[-*]\s*', ''
            $desc  = ""
            $url   = ""
            $usage = ""
            if ($parts.Count -gt 1) { $desc  = $parts[1].Trim() }
            if ($parts.Count -gt 2) { $url   = $parts[2].Trim() }
            if ($parts.Count -gt 3) { $usage = $parts[3].Trim() }
            if ($name -ne "") {
                $items += [PSCustomObject]@{ Name = $name; Desc = $desc; Url = $url; Usage = $usage }
            }
        }
    }

    # 已收藏/已推荐过的剔除（按规范化链接比对），取前 8 条展示；候选 12 条保证剔除后仍够 8 条
    if ($excludeUrls.Count -gt 0) {
        $excludeNorm = @($excludeUrls | ForEach-Object { Normalize-Url $_ } | Where-Object { $_ })
        $items = @($items | Where-Object { $excludeNorm -notcontains (Normalize-Url $_.Url) })
    }
    $items = @($items | Select-Object -First 8)
}

function HtmlEnc([string]$s) {
    if ([string]::IsNullOrEmpty($s)) { return "" }
    return [System.Net.WebUtility]::HtmlEncode($s)
}

if (-not $RenderOnly) {
    $fundNames = @()
    foreach ($rawLine in ($fundContent -split "`r?`n")) {
        $line = $rawLine.Trim() -replace '^\d+[\.、\)]\s*', '' -replace '^[-*]\s*', ''
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        if ($line -match '参考来源|来源|以下|说明|行情|价格|API Error|生成失败|错误') { continue }
        $fundNames += $line
    }
}

# ---- 归档当日记录进历史.md（结构化；同日重跑把旧条目并入尾部防丢记录，只留最近30天） ----
if (-not $RenderOnly -and $content -match '\|\|' -and $items.Count -gt 0) {
    # 内容有效才归档：生成失败(API错误/网络异常)时不覆盖历史里当日已有的好内容
    $newUrlSet = @($items | ForEach-Object { Normalize-Url $_.Url })
    if (Test-Path $historyPath) {
        $histRawDay = Get-Content -Path $historyPath -Raw -Encoding UTF8
        if ($histRawDay -match ("(?ms)^## " + $dateStr + "\r?\n.*?(?=^## |\z)")) {
            $oldBody = $Matches[0] -replace ("(?m)^## " + $dateStr + "\r?\n"), ""
            $oldParsed = Parse-HistorySection -SectionText $oldBody
            foreach ($oit in $oldParsed.Items) {
                if ($newUrlSet -notcontains (Normalize-Url $oit.Url)) { $items += $oit }
            }
        }
    }
    $sectionText = Format-HistorySection -Date $dateStr -Items $items -SourcesLine $sourcesLine -FundNames $fundNames
    Update-History -Date $dateStr -SectionText $sectionText
    # 页面只展示最新的 8 条（旧条目仅留档，不展示）
    $items = @($items | Select-Object -First 8)
}

# 基金面板：有数据才渲染整个面板（无 fund.ps1 或当日无结果时完全不显示）
$fundPanelHtml = ""
if ($fundNames.Count -gt 0) {
    $fundItemsHtml = ""
    foreach ($fname in $fundNames) {
        $fnameEsc = HtmlEnc $fname
        $fundItemsHtml += "<div class='fund-item'>$fnameEsc</div>"
    }
    $fundPanelHtml = "<div class=""fav-panel"" style=""margin-top:16px""><div class=""fav-title"">📈 基金黄金</div>$fundItemsHtml</div>"
}

# ---- 生成 Element 风格卡片 ----
$cardsHtml = ""
if ($items.Count -gt 0) {
    $idx = 0
    foreach ($it in $items) {
        $idx++
        $nameEsc  = HtmlEnc $it.Name
        $descEsc  = HtmlEnc $it.Desc
        $urlEsc   = HtmlEnc $it.Url
        $usageHtml = ""
        if ($it.Usage) {
            foreach ($seg in ($it.Usage -split '[；;]')) {
                $seg = $seg.Trim()
                if ($seg -eq "") { continue }
                if ($seg -match '^(.*?)[：:](.*)$') {
                    $tagEsc = HtmlEnc $matches[1].Trim()
                    $valEsc = HtmlEnc $matches[2].Trim()
                    $usageHtml += "<div class='usage-item'><span class='usage-tag'>$tagEsc</span><span class='usage-val'>$valEsc</span></div>"
                } else {
                    $valEsc = HtmlEnc $seg
                    $usageHtml += "<div class='usage-item'><span class='usage-val'>$valEsc</span></div>"
                }
            }
        }
        $linkHtml = ""
        if ($it.Url -ne "") {
            $linkHtml = "<a class=""link"" href=""$urlEsc"" target=""_blank"">$urlEsc</a>"
        }
        $cardsHtml += @"
<div class="card">
  <div class="card-head"><span class="badge">$idx</span><span class="name">$nameEsc</span><button class="fav-btn" id="fav-$($idx-1)" onclick="toggleFav($($idx-1))">☆</button></div>
  <div class="desc">$descEsc</div>
  $linkHtml
  <button class="usage-btn" onclick="toggleUsage($($idx-1))">⚙ 使用方法</button>
  <div class="usage" id="usage-$($idx-1)" style="display:none">$usageHtml</div>
</div>
"@
    }
} else {
    $cardsHtml = "<div class=""card""><div class=""desc"">$(HtmlEnc $content)</div></div>"
}

$sourcesHtml = ""
if ($sourcesLine -ne "") {
    $sourcesHtml = "<div class=""sources"">$(HtmlEnc $sourcesLine)</div>"
}

# 下载背景图到本地（每天换一张，失败则退回渐变）
$bgFile = Join-Path $dir "bg.jpg"
$bgCss = "radial-gradient(ellipse 55% 42% at 12% -2%,rgba(124,92,255,.18),transparent 62%),radial-gradient(ellipse 48% 40% at 88% 8%,rgba(56,189,248,.16),transparent 60%),radial-gradient(ellipse 55% 45% at 50% 105%,rgba(236,72,153,.10),transparent 60%),#f4f5fb"
try {
    Invoke-WebRequest -Uri "https://picsum.photos/seed/daily$dateStr/1920/1080" -OutFile $bgFile -TimeoutSec 25 -UseBasicParsing
    if ((Test-Path $bgFile) -and ((Get-Item $bgFile).Length -gt 10000)) {
        $bgCss = "linear-gradient(180deg,rgba(247,248,252,.80) 0%,rgba(247,248,252,.92) 100%),linear-gradient(120deg,rgba(109,74,255,.14),rgba(59,130,246,.10)),url('bg.jpg') center/cover no-repeat fixed,#f4f5fb"
    }
} catch { }

# 生成收藏用的条目数据(JSON) 和 一键重新生成脚本
$itemsJson = $items | ConvertTo-Json -Compress
$refreshBat = Join-Path $dir "refresh.bat"
Set-Content -Path $refreshBat -Value "@echo off`r`nschtasks /Run /TN DailyAIRecommend" -Encoding ASCII

$html = @"
<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="UTF-8">
<title>每日 AI 推荐 $dateStr</title>
<style>
*{box-sizing:border-box}
body{margin:0;font-family:-apple-system,"PingFang SC","Microsoft YaHei",sans-serif;color:#1f2430;height:100vh;overflow:hidden;background:$bgCss;-webkit-font-smoothing:antialiased}
.wrapper{max-width:1100px;height:100vh;margin:0 auto;padding:24px 20px;display:flex;flex-direction:column}
.content{flex:1;display:flex;gap:24px;min-height:0}
.main{flex:1;min-width:0;overflow-y:auto;height:100%;padding-right:6px}
.sidebar{flex:none;width:300px;overflow-y:auto;height:100%}
.toolbar{flex:none;display:flex;align-items:flex-end;justify-content:space-between;gap:16px;margin-bottom:20px}
.main::-webkit-scrollbar,.sidebar::-webkit-scrollbar{width:8px}
.main::-webkit-scrollbar-track,.sidebar::-webkit-scrollbar-track{background:transparent}
.main::-webkit-scrollbar-thumb,.sidebar::-webkit-scrollbar-thumb{background:transparent;border-radius:4px}
.main:hover::-webkit-scrollbar-thumb,.sidebar:hover::-webkit-scrollbar-thumb{background:rgba(31,38,135,.22)}
.main::-webkit-scrollbar-thumb:hover,.sidebar:hover::-webkit-scrollbar-thumb:hover{background:rgba(31,38,135,.4)}
.page-title{font-size:32px;font-weight:800;letter-spacing:-.5px;margin:0 0 6px;background:linear-gradient(120deg,#5b3df5,#3b82f6);-webkit-background-clip:text;background-clip:text;-webkit-text-fill-color:transparent;color:transparent}
.page-date{color:#7c8399;font-size:13px}
.toolbar-btns{display:flex;gap:10px;flex:none}
.btn{display:inline-flex;align-items:center;gap:4px;padding:8px 14px;border-radius:10px;border:1px solid rgba(91,61,245,.28);background:rgba(255,255,255,.75);color:#5b3df5;font-size:13px;font-weight:600;cursor:pointer;transition:all .2s;white-space:nowrap}
.btn:hover{background:#5b3df5;color:#fff;border-color:#5b3df5}
.card{background:rgba(255,255,255,.88);backdrop-filter:blur(18px) saturate(160%);-webkit-backdrop-filter:blur(18px) saturate(160%);border:1px solid rgba(255,255,255,.6);border-radius:18px;padding:22px;margin-bottom:18px;box-shadow:0 8px 30px rgba(31,38,135,.08);transition:transform .25s ease,box-shadow .25s ease}
.card:hover{transform:translateY(-4px);box-shadow:0 18px 44px rgba(31,38,135,.16)}
.card-head{display:flex;align-items:center;gap:12px;margin-bottom:10px}
.badge{flex:none;min-width:30px;height:30px;padding:0 9px;display:inline-flex;align-items:center;justify-content:center;border-radius:10px;background:linear-gradient(135deg,#6d4aff,#3b82f6);color:#fff;font-size:13px;font-weight:700;box-shadow:0 4px 12px rgba(91,61,245,.32)}
.name{font-size:17px;font-weight:700;color:#1f2430;flex:1}
.fav-btn{flex:none;width:30px;height:30px;border:none;background:transparent;color:#c0c4cc;font-size:20px;line-height:1;cursor:pointer;transition:color .15s,transform .15s}
.fav-btn:hover{transform:scale(1.2)}
.fav-btn.fav-on{color:#f7ba2a}
.desc{margin:0 0 12px;color:#4b5563;font-size:14px;line-height:1.75}
.link{display:inline-flex;align-items:center;color:#5b3df5;font-size:13px;font-weight:500;text-decoration:none;word-break:break-all}
.link:hover{color:#3b82f6}
.link::after{content:"↗";margin-left:3px;font-size:12px}
.fav-panel{background:rgba(255,255,255,.9);border:1px solid rgba(255,255,255,.6);border-radius:18px;padding:18px;box-shadow:0 8px 30px rgba(31,38,135,.08)}
.fav-title{font-size:15px;font-weight:700;color:#303133;margin-bottom:10px;padding-bottom:10px;border-bottom:1px solid #f0f0f5}
.fav-item{padding:10px 0;border-bottom:1px solid #f0f0f5}
.fav-item:last-child{border-bottom:none}
.fav-item-top{display:flex;align-items:flex-start;gap:8px;margin-bottom:5px}
.fav-name{flex:1;font-size:14px;font-weight:600;color:#303133;word-break:break-word;line-height:1.4}
.fav-desc{font-size:12px;color:#909399;line-height:1.6;margin-bottom:5px;word-break:break-word}
.fav-link{display:block;font-size:12px;color:#5b3df5;text-decoration:none;word-break:break-all}
.fav-link:hover{text-decoration:underline}
.fav-usage-btn{display:inline-flex;align-items:center;gap:4px;margin-top:8px;padding:4px 10px;border-radius:6px;border:1px solid #e4e7ed;background:#f5f7fa;color:#606266;font-size:11px;font-weight:600;cursor:pointer}
.fav-usage-btn:hover{background:#ecf5ff;color:#409eff;border-color:#d9ecff}
.fav-usage{display:none;margin-top:8px;padding:10px;background:#f8f9fc;border:1px solid #f0f0f5;border-radius:8px}
.fav-del{flex:none;width:20px;height:20px;border:none;background:#fef0f0;color:#f56c6c;border-radius:6px;cursor:pointer;font-size:12px;line-height:1}
.fav-empty{color:#c0c4cc;font-size:13px;text-align:center;padding:20px 0;line-height:1.8}
.fund-item{padding:8px 12px;border-radius:8px;background:rgba(255,255,255,.65);border:1px solid rgba(255,255,255,.6);margin-bottom:6px;font-size:12px;font-weight:600;color:#303133}
.usage-btn{display:inline-flex;align-items:center;gap:4px;margin-top:12px;padding:6px 12px;border-radius:8px;border:1px solid #e4e7ed;background:#f5f7fa;color:#606266;font-size:12px;font-weight:600;cursor:pointer;transition:all .2s}
.usage-btn:hover{background:#ecf5ff;color:#409eff;border-color:#d9ecff}
.usage{display:none;margin-top:10px;padding:12px 14px;background:#f8f9fc;border:1px solid #f0f0f5;border-radius:10px}
.usage-item{display:flex;align-items:flex-start;gap:8px;padding:5px 0}
.usage-tag{flex:none;display:inline-block;padding:2px 9px;border-radius:6px;background:#ecf5ff;color:#409eff;font-size:12px;font-weight:600;margin-top:1px;white-space:nowrap}
.usage-val{color:#5a6270;font-size:13px;line-height:1.7;word-break:break-word}
.sources{margin-top:24px;padding:14px 18px;background:rgba(255,255,255,.5);border:1px solid rgba(255,255,255,.6);border-radius:12px;color:#8a94a6;font-size:12px;backdrop-filter:blur(10px);-webkit-backdrop-filter:blur(10px)}
</style>
</head>
<body>
<div class="wrapper">
<div class="toolbar">
  <div>
    <div class="page-title">每日 AI 推荐</div>
    <div class="page-date">$dateStr</div>
  </div>
  <div class="toolbar-btns">
    <button class="btn" onclick="reloadPage()">↻ 刷新</button>
    <button class="btn" id="regenBtn" onclick="regen()">✦ 重新生成</button>
  </div>
</div>
<div class="content">
<div class="main">
$cardsHtml
$sourcesHtml
</div>
<aside class="sidebar">
<div class="fav-panel">
  <div class="fav-title">⭐ 我的收藏</div>
  <div id="favList"></div>
</div>
$fundPanelHtml
</aside>
</div>
</div>
<script>
var API='http://127.0.0.1:8765';
var ITEMS=$itemsJson;
var FAVS=[];
function esc(s){return String(s==null?'':s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;')}
function isFavUrl(url){for(var i=0;i<FAVS.length;i++){if(FAVS[i].url===url)return true}return false}
function toggleFav(i){var it=ITEMS[i];if(!it)return;var action=isFavUrl(it.Url)?'remove':'add';fetch(API+'/fav',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({action:action,name:it.Name,desc:it.Desc,url:it.Url,usage:it.Usage||''})}).then(function(){loadFavs()}).catch(function(){alert('收藏失败，请确认本地服务已启动')})}
function delFav(el){var url=el.getAttribute('data-url');fetch(API+'/fav',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({action:'remove',url:url})}).then(function(){loadFavs()}).catch(function(){alert('操作失败，请确认本地服务已启动')})}
function toggleUsage(i){var u=document.getElementById('usage-'+i);if(!u)return;u.style.display=(u.style.display==='none')?'block':'none'}
function renderStars(){for(var i=0;i<ITEMS.length;i++){var b=document.getElementById('fav-'+i);if(!b)continue;var on=isFavUrl(ITEMS[i].Url);b.textContent=on?'★':'☆';b.className='fav-btn'+(on?' fav-on':'')}}
function renderUsage(u){if(!u)return'';var ps=u.split(/[；;]/);var h='';for(var i=0;i<ps.length;i++){var s=ps[i].trim();if(!s)continue;var m=s.match(/^(.*?)[：:](.*)$/);if(m){h+='<div class="usage-item"><span class="usage-tag">'+esc(m[1].trim())+'</span><span class="usage-val">'+esc(m[2].trim())+'</span></div>'}else{h+='<div class="usage-item"><span class="usage-val">'+esc(s)+'</span></div>'}}return h}
function toggleFavUsage(btn){var u=btn.nextElementSibling;if(!u)return;u.style.display=(u.style.display==='none')?'block':'none'}
function renderFavs(){var list=document.getElementById('favList');if(FAVS.length===0){list.innerHTML='<div class="fav-empty">暂无收藏<br>点卡片右上角 ⭐ 收藏</div>';return}var h='';for(var i=0;i<FAVS.length;i++){var it=FAVS[i];var ub=it.usage?'<button class="fav-usage-btn" onclick="toggleFavUsage(this)">⚙ 使用方法</button><div class="fav-usage" style="display:none">'+renderUsage(it.usage)+'</div>':'';h+='<div class="fav-item"><div class="fav-item-top"><span class="fav-name">'+esc(it.name)+'</span><button class="fav-del" data-url="'+esc(it.url)+'" onclick="delFav(this)">✕</button></div><div class="fav-desc">'+esc(it.desc)+'</div><a class="fav-link" href="'+esc(it.url)+'" target="_blank">'+esc(it.url)+'</a>'+ub+'</div>'}list.innerHTML=h}
function loadFavs(){fetch(API+'/favs').then(function(r){return r.json()}).then(function(f){FAVS=f||[];renderFavs();renderStars()}).catch(function(){})}
function reloadPage(){location.reload()}
function regen(){fetch(API+'/regen',{method:'POST'}).then(function(r){return r.json()}).then(function(d){alert('已触发重新生成，约 1-2 分钟后自动刷新显示新内容');setTimeout(function(){location.reload()},120000)}).catch(function(){alert('重新生成失败，请确认本地服务已启动')})}
loadFavs();
</script>
</body>
</html>
"@

# 唯一展示页面：每天覆盖，不再按日期堆文件
Set-Content -Path $pagePath -Value $html -Encoding UTF8

# 兜底清理：删除历史遗留的带日期输出文件
Get-ChildItem -Path $dir -File -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -match '^\d{4}-\d{2}-\d{2}.*\.(md|html)$' } |
    Remove-Item -Force -ErrorAction SilentlyContinue

if (-not $Test) {
    # 弹窗只给标题 + 一句提示，不塞列表
    $shell = New-Object -ComObject WScript.Shell
    [void]$shell.Popup("今日 AI 推荐已生成，点【确定】查看详情", 0, "每日 AI 推荐 - $dateStr", 0x40)

    # 本地服务在则打开完整页面(可收藏/使用方法)，否则退回静态页
    $serviceUp = $false
    try {
        Invoke-WebRequest -Uri "http://127.0.0.1:8765/favs" -TimeoutSec 2 -UseBasicParsing | Out-Null
        $serviceUp = $true
    } catch { $serviceUp = $false }
    if ($serviceUp) {
        Start-Process "http://127.0.0.1:8765/"
    } else {
        Start-Process $pagePath
    }
}

Write-Output "OK $dateStr -> $pagePath (items=$($items.Count))"

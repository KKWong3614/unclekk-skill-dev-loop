# =============================================================================
# sync-to-cache.ps1 — 从实盘发布包重新生成 cache 插件实例（唯一派生通道）
# -----------------------------------------------------------------------------
# 权威副本位于：<用户主目录>/.workbuddy/skills/unclekk-skill-dev-loop/scripts/
# 实盘项目根可有同名副本（分发用），但必须与权威副本同源；不同源时以权威副本为准。
#
# 用途：把 <RealDiskRoot>\<Slug>\（git 仓库 = 唯一真相源）重新生成为
#       WorkBuddy 的 cache 插件实例，供 host 加载生效。
#       所有改动只在实盘做，cache 只由本脚本派生，禁止手改 cache。
#
# 映射（实盘结构 → cache 插件结构）：
#   scripts/*.py                    -> 1.0.0/scripts/*.py
#   hooks/hooks.json                -> 1.0.0/hooks/hooks.json（存在才复制）
#   SKILL.md                        -> 1.0.0/skills/<cachePluginId>/SKILL.md（必需）
#   README.md                       -> 1.0.0/skills/<cachePluginId>/README.md（存在才复制）
#   references/*.md                 -> 1.0.0/skills/<cachePluginId>/references/*.md（存在才复制）
#   package.json                    -> 1.0.0/package.json（必需）
#   test-prompts.json               -> 1.0.0/test-prompts.json（存在才复制）
#   .codebuddy-plugin/plugin.json   -> 由脚本生成（实盘不含，字段取自 package.json）
#   不复制：.git/ .gitignore audit/ *.bak __pycache__（版本控制/运行时产物）
#
# 重要约束：
#   - cache 目录名固定为 1.0.0（host 在 installed_plugins.json 写死 installPath），勿改目录名。
#   - 内容版本以 package.json 的 version 字段为准；host 注册表 version 由另一条命令对齐
#     （注册表路径见 references/env-constraints.md）。
#   - 每次运行自动备份旧 cache 为 <cachePluginId>.bak-<时间戳>，默认保留最新 3 个。
#   - safe-delete 会拦截 cache 路径内的删除，历史 .bak 清理失败时降级为非致命警告，
#     需手动清理（见 references/env-constraints.md）。
#
# 用法（PowerShell）：
#   powershell -ExecutionPolicy Bypass -File "<权威副本路径>\sync-to-cache.ps1" -Slug <Slug>
#   ... -Slug <Slug> -CachePluginId <id>          # 推导不符时显式指定
#   ... -Slug <Slug> -DryRun                      # 只预览映射，不写任何文件
#   ... -Slug <Slug> -VerifyFiles "scripts/a.py,scripts/b.py"   # 显式指定校验清单
#   ... -Slug <Slug> -NoBackup                    # 跳过备份
#   ... -Slug <Slug> -KeepBackups 5               # 自定义备份保留个数
#
# 变更记录：
#   v1.2.1 (2026-09-25) 实盘根不再回退到硬编码盘符路径（规则 14）：未设 SKILL_DEV_REALDISK 且未传
#          -RealDiskRoot 时直接报错退出并提示如何设置，避免换机器/换用户时静默指向不存在的目录。
#   v1.1.0 (2026-09-06) 校验清单不再硬编码 redflags.py，改为自动推导 + -VerifyFiles 覆盖；
#          所有复制加存在性保护；新增 -DryRun / -KeepBackups / -VerifyFiles；
#          新增 .codebuddy-plugin/plugin.json 生成（吸收自 pmu-guard 实盘版，避免功能倒退）；
#          默认路径改为可由环境变量覆盖，不再硬编码用户名。
# =============================================================================
param(
  [Parameter(Mandatory=$true)][string]$Slug,
  [string]$RealDiskRoot = "",
  [string]$CacheRoot = "",
  [string]$CachePluginId = "",
  [string]$VerifyFiles = "",
  [int]$KeepBackups = 3,
  [switch]$NoBackup,
  [switch]$DryRun
)
$ErrorActionPreference = 'Stop'

# --- 默认路径：优先环境变量，回退到历史默认（不再硬编码用户名） ---
if (-not $RealDiskRoot) {
  if ($env:SKILL_DEV_REALDISK) { $RealDiskRoot = $env:SKILL_DEV_REALDISK }
  else {
    Write-Host "[ERROR] 未指定实盘根：请显式传 -RealDiskRoot，或先设置环境变量 SKILL_DEV_REALDISK（例：`$env:SKILL_DEV_REALDISK='<你的实盘根>'）。本脚本不再猜测默认盘符路径。"
    exit 1
  }
}
if (-not $CacheRoot) {
  if ($env:SKILL_DEV_CACHEROOT) { $CacheRoot = $env:SKILL_DEV_CACHEROOT }
  else { $CacheRoot = Join-Path $env:USERPROFILE ".workbuddy\plugins\cache\codebuddy-plugins-official" }
}
# 推导 cache 插件ID（默认去 unclekk- 前缀）
if (-not $CachePluginId) { $CachePluginId = $Slug -replace '^unclekk-', '' }

$Src = Join-Path $RealDiskRoot $Slug
$VER_DIR = Join-Path (Join-Path $CacheRoot $CachePluginId) "1.0.0"
$SKILL_DIR = Join-Path (Join-Path $VER_DIR "skills") $CachePluginId

Write-Host "==> 源(实盘/真相源): $Src"
Write-Host "==> 目标(cache实例): $VER_DIR"
Write-Host "==> cache 插件ID: $CachePluginId"
if ($DryRun) { Write-Host "==> 模式: DryRun（只预览，不写任何文件）" }

if (-not (Test-Path $Src)) {
  Write-Host "[ERROR] 实盘目录不存在: $Src"
  Write-Host "        怎么修：① 确认实盘根变量指向'仓库们的父目录'而不是 <slug> 本身（echo 出来看一眼）；"
  Write-Host "                ② 在父目录下确认 <slug> 目录存在；③ 先跑 -DryRun 预览源/目标两个路径（详见本 skill references/faq.md Q2）。"
  exit 1
}

# 条件复制：源不存在时跳过（非必需）或报错退出（必需）
$script:Missing = 0
function Copy-Mapped {
  param([string]$From, [string]$To, [switch]$Required)
  $found = $false
  if (Test-Path $From) {
    $items = @(Get-Item $From -ErrorAction SilentlyContinue)
    if ($items.Count -gt 0) { $found = $true }
  }
  if (-not $found) {
    if ($Required) {
      Write-Host "[ERROR] 缺少必需文件: $From"
      if ($From -like '*package.json') {
        Write-Host "        怎么修：实盘形态必需 package.json（版本唯一权威）。在实盘根补一个最小 package.json（name/version/description/license）再重跑 sync，详见 references/faq.md Q3。"
      } else {
        Write-Host "        怎么修：SKILL.md 是必需源，确认实盘根 <slug> 目录下存在该文件后重跑（详见 references/faq.md Q3）。"
      }
      $script:Missing = 1; return $false
    }
    Write-Host "  skip（源不存在）: $From"
    return $false
  }
  if ($DryRun) {
    foreach ($it in @(Get-Item $From)) { Write-Host "  [dry-run] 复制 $($it.FullName) -> $To" }
  } else {
    Copy-Item $From $To -Force
  }
  return $true
}

# 0. 备份旧 cache（时间戳），并保留最新 $KeepBackups 个
if (-not $NoBackup -and (Test-Path $VER_DIR)) {
  if ($DryRun) {
    Write-Host "  [dry-run] 将备份 $VER_DIR -> $(Join-Path $CacheRoot "$CachePluginId.bak-<时间戳>")"
  } else {
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $bak = Join-Path $CacheRoot "$CachePluginId.bak-$stamp"
    Copy-Item $VER_DIR $bak -Recurse -Force
    Write-Host "已备份旧 cache -> $bak"
  }
  # 清理超量历史备份（safe-delete 可能拦截，降级为非致命警告）
  $old = @(Get-ChildItem $CacheRoot -Directory -Filter "$CachePluginId.bak-*" -ErrorAction SilentlyContinue |
           Sort-Object LastWriteTime -Descending | Select-Object -Skip $KeepBackups)
  if ($old.Count -gt 0) {
    foreach ($d in $old) {
      if ($DryRun) { Write-Host "  [dry-run] 将清理历史备份 $($d.Name)" }
      else { Remove-Item $d.FullName -Recurse -Force -ErrorAction SilentlyContinue }
    }
    if (-not $DryRun) {
      $left = @(Get-ChildItem $CacheRoot -Directory -Filter "$CachePluginId.bak-*" -ErrorAction SilentlyContinue)
      if ($left.Count -gt $KeepBackups) {
        Write-Host "提示: safe-delete 拦截了部分历史备份删除（不影响本次派生），需手动清理 $CacheRoot\$CachePluginId.bak-*（与插件目录平级，详见 references/faq.md Q6）"
      }
    }
  }
}

# 1. 清空可变内容（保留 1.0.0/ 骨架，host 锁定路径）
if ($DryRun) {
  Write-Host "  [dry-run] 将清空 $VER_DIR 下的 scripts/ hooks/ skills/"
} else {
  foreach ($sub in 'scripts','hooks','skills') {
    try { Remove-Item (Join-Path $VER_DIR $sub) -Recurse -Force -ErrorAction SilentlyContinue }
    catch {
      Write-Host "  [WARN] 清空 $sub 被拦截（常见为 SAFE_DELETE_BULK_GUARD_ERROR）："
      Write-Host "         不影响后续覆盖复制继续执行，但完成后必须 diff -r 逐文件比对（见 references/faq.md Q4）。"
    }
  }
}

# 2. 重新映射（覆盖复制派生，不删除、直接覆盖，规避 safe-delete）
if (-not $DryRun) {
  New-Item -ItemType Directory -Force -Path (Join-Path $VER_DIR 'scripts') | Out-Null
  New-Item -ItemType Directory -Force -Path (Join-Path $VER_DIR 'hooks')   | Out-Null
  New-Item -ItemType Directory -Force -Path (Join-Path $SKILL_DIR 'references') | Out-Null
}
$copiedPy = @()
if (Test-Path (Join-Path $Src 'scripts')) {
  $pyItems = @(Get-ChildItem (Join-Path $Src 'scripts') -Filter '*.py' -File -ErrorAction SilentlyContinue)
  foreach ($p in $pyItems) {
    if ($DryRun) { Write-Host "  [dry-run] 复制 $($p.FullName) -> $(Join-Path $VER_DIR 'scripts')" }
    else { Copy-Item $p.FullName (Join-Path $VER_DIR 'scripts') -Force }
    $copiedPy += $p.Name
  }
  if ($pyItems.Count -eq 0) { Write-Host "  skip（无 .py 文件）: $Src\scripts" }
} else {
  Write-Host "  skip（目录不存在）: $Src\scripts"
}
$hasHooks = Copy-Mapped (Join-Path $Src 'hooks\hooks.json') (Join-Path $VER_DIR 'hooks')
Copy-Mapped (Join-Path $Src 'SKILL.md')          (Join-Path $SKILL_DIR 'SKILL.md')      -Required | Out-Null
Copy-Mapped (Join-Path $Src 'README.md')         (Join-Path $SKILL_DIR 'README.md')       | Out-Null
Copy-Mapped (Join-Path $Src 'references\*.md')   (Join-Path $SKILL_DIR 'references')      | Out-Null
Copy-Mapped (Join-Path $Src 'package.json')      (Join-Path $VER_DIR 'package.json') -Required | Out-Null
Copy-Mapped (Join-Path $Src 'test-prompts.json') (Join-Path $VER_DIR 'test-prompts.json') | Out-Null
if ($script:Missing -eq 1) { exit 1 }

# 2.5 生成 .codebuddy-plugin/plugin.json（派生产物，字段取自实盘 package.json）
$plugDir = Join-Path $VER_DIR '.codebuddy-plugin'
$pjPath = Join-Path $Src 'package.json'
if (Test-Path $pjPath) {
  $ver = '0.0.0'; $desc = "$CachePluginId"; $repo = ''; $authorName = 'KK大叔'
  try {
    $pj = Get-Content $pjPath -Raw | ConvertFrom-Json
    if ($pj.version) { $ver = $pj.version }
    if ($pj.description) { $desc = $pj.description }
    if ($pj.url -and $pj.url.repository) { $repo = $pj.url.repository }
  } catch { Write-Host "警告: package.json 解析失败，plugin.json 用默认值" }
  $hooksLine = ''
  if ($hasHooks) { $hooksLine = ",`n  `"hooks`": `"hooks/hooks.json`"" }
  $repoLines = ''
  if ($repo) { $repoLines = ",`n  `"homepage`": `"$repo`",`n  `"repository`": `"$repo`"" }
  $pluginJson = "{`n  `"name`": `"$CachePluginId`",`n  `"version`": `"$ver`",`n  `"description`": `"$desc`",`n  `"author`": { `"name`": `"$authorName`" }$repoLines$hooksLine`n}`n"
  if ($DryRun) { Write-Host "  [dry-run] 将生成 $plugDir\plugin.json (name=$CachePluginId, version=$ver)" }
  else {
    New-Item -ItemType Directory -Force -Path $plugDir | Out-Null
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText((Join-Path $plugDir 'plugin.json'), $pluginJson, $utf8NoBom)
    Write-Host "已生成 .codebuddy-plugin/plugin.json (name=$CachePluginId, version=$ver)"
  }
} else {
  Write-Host "  skip（无 package.json，跳过 plugin.json 生成）"
}

# 3. 清理派生产物
if (-not $DryRun) {
  Remove-Item (Join-Path $VER_DIR 'scripts\__pycache__') -Recurse -Force -ErrorAction SilentlyContinue
}

# 4. 校验：默认自动推导（复制了什么就校验什么），-VerifyFiles 可显式覆盖
$files = @((Join-Path $SKILL_DIR 'SKILL.md'))
if ($VerifyFiles) {
  foreach ($rel in ($VerifyFiles -split ',')) {
    $rel = $rel.Trim()
    if ($rel) { $files += (Join-Path $VER_DIR ($rel -replace '/', '\')) }
  }
} else {
  if ($hasHooks) { $files += (Join-Path $VER_DIR 'hooks\hooks.json') }
  foreach ($n in $copiedPy) { $files += (Join-Path (Join-Path $VER_DIR 'scripts') $n) }
}
if ($DryRun) {
  Write-Host "==> 校验清单（$($files.Count) 项）："
  foreach ($f in $files) { Write-Host "  ? $f" }
  Write-Host "[OK] DryRun 完成，未写入任何文件。"
  exit 0
}
$fail = 0
foreach ($f in $files) {
  if (Test-Path $f) { Write-Host "OK  $f" } else { Write-Host "MISSING $f"; $fail = 1 }
}
if ($fail -eq 1) { Write-Host "[FAIL] 校验未通过，cache 可能未完整派生"; exit 1 }
Write-Host "[OK] cache 实例已从实盘派生（内容版本见 package.json）。重启 host 后加载生效。"

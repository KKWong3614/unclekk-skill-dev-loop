#!/usr/bin/env bash
# [Windows] 优先使用 sync-to-cache.ps1：本 .sh 在 Git Bash 下删除操作会被 safe-delete 拦截导致中途退出。
# =============================================================================
# sync-to-cache.sh — 从实盘发布包重新生成 cache 插件实例（唯一派生通道 · Linux/Git Bash 版）
# -----------------------------------------------------------------------------
# 权威副本位于：<用户主目录>/.workbuddy/skills/unclekk-skill-dev-loop/scripts/
# 行为与 sync-to-cache.ps1 对齐：参数化校验、条件复制、-DryRun、备份保留策略、
# .codebuddy-plugin/plugin.json 生成。详见 .ps1 顶部说明。
#
# 用法：bash sync-to-cache.sh -Slug <Slug> [-CachePluginId <id>] [-DryRun]
#       [-VerifyFiles "scripts/a.py,scripts/b.py"] [-NoBackup] [-KeepBackups 3]
#
# 注意：本脚本全程使用 if 而非 [[ ]] && cmd —— 后者在 set -e 下短路时会误判为
#       命令失败并终止脚本（隐蔽陷阱，曾导致误退出）。
# =============================================================================
set -euo pipefail

# 默认参数
SLUG=""
REAL_DISK_ROOT="${SKILL_DEV_REALDISK:-}"
CACHE_ROOT="${SKILL_DEV_CACHEROOT:-$HOME/.workbuddy/plugins/cache/codebuddy-plugins-official}"
CACHE_PLUGIN_ID=""
VERIFY_FILES=""
KEEP_BACKUPS=3
NO_BACKUP=0
DRY_RUN=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    -Slug) SLUG="$2"; shift 2;;
    -RealDiskRoot) REAL_DISK_ROOT="$2"; shift 2;;
    -CacheRoot) CACHE_ROOT="$2"; shift 2;;
    -CachePluginId) CACHE_PLUGIN_ID="$2"; shift 2;;
    -VerifyFiles) VERIFY_FILES="$2"; shift 2;;
    -KeepBackups) KEEP_BACKUPS="$2"; shift 2;;
    -NoBackup) NO_BACKUP=1; shift;;
    -DryRun) DRY_RUN=1; shift;;
    *) echo "未知参数: $1"; exit 1;;
  esac
done

if [[ -z "$SLUG" ]]; then echo "错误: 必须提供 -Slug"; exit 1; fi
if [[ -z "$REAL_DISK_ROOT" ]]; then
  echo "错误: 未指定实盘根 —— 请显式传 -RealDiskRoot，或先设置环境变量 SKILL_DEV_REALDISK（例：export SKILL_DEV_REALDISK='<你的实盘根>'）。本脚本不再猜测默认盘符路径。"
  exit 1
fi
if [[ -z "$CACHE_PLUGIN_ID" ]]; then CACHE_PLUGIN_ID="${SLUG#unclekk-}"; fi

SRC="$REAL_DISK_ROOT/$SLUG"
VER_DIR="$CACHE_ROOT/$CACHE_PLUGIN_ID/1.0.0"
SKILL_DIR="$VER_DIR/skills/$CACHE_PLUGIN_ID"

echo "==> 源(实盘/真相源): $SRC"
echo "==> 目标(cache实例): $VER_DIR"
echo "==> cache 插件ID: $CACHE_PLUGIN_ID"
if [[ $DRY_RUN -eq 1 ]]; then echo "==> 模式: DryRun（只预览，不写任何文件）"; fi

if [[ ! -d "$SRC" ]]; then
  echo "[ERROR] 实盘目录不存在: $SRC"
  echo "        怎么修：① 确认实盘根变量指向'仓库们的父目录'而不是 <slug> 本身；② 确认 <slug> 目录存在；③ 先跑 -DryRun 预览路径（详见 references/faq.md Q2）。"
  exit 1
fi

# 条件复制：源不存在时跳过（非必需）或标记缺失（必需）
MISSING=0
copy_mapped() {
  local from="$1" to="$2" required="${3:-0}" n
  n=$(compgen -G "$from" 2>/dev/null | wc -l)
  if [[ "$n" -eq 0 ]]; then
    if [[ "$required" -eq 1 ]]; then
      echo "[ERROR] 缺少必需文件: $from"
      case "$from" in
        *package.json) echo "        怎么修：实盘形态必需 package.json（版本唯一权威）。在实盘根补一个最小 package.json（name/version/description/license）再重跑 sync，详见 references/faq.md Q3。" ;;
        *) echo "        怎么修：SKILL.md 是必需源，确认实盘根 <slug> 目录下存在该文件后重跑（详见 references/faq.md Q3）。" ;;
      esac
      MISSING=1; return 1
    fi
    echo "  skip（源不存在）: $from"; return 1
  fi
  if [[ $DRY_RUN -eq 1 ]]; then
    echo "  [dry-run] 复制 $from -> $to"
  else
    cp $from "$to" 2>/dev/null || cp -r $from "$to"
  fi
  return 0
}

# 0. 备份旧 cache，并保留最新 KEEP_BACKUPS 个
if [[ $NO_BACKUP -eq 0 && -d "$VER_DIR" ]]; then
  if [[ $DRY_RUN -eq 1 ]]; then
    echo "  [dry-run] 将备份 $VER_DIR -> $CACHE_ROOT/$CACHE_PLUGIN_ID.bak-<时间戳>"
  else
    BAK="$CACHE_ROOT/$CACHE_PLUGIN_ID.bak-$(date +%Y%m%d-%H%M%S)"
    cp -r "$VER_DIR" "$BAK"
    echo "已备份旧 cache -> $BAK"
  fi
  # 清理超量历史备份（safe-delete 可能拦截，失败降级为非致命）
  n=0
  for d in $(ls -dt "$CACHE_ROOT"/$CACHE_PLUGIN_ID.bak-* 2>/dev/null); do
    n=$((n+1))
    if [[ "$n" -gt "$KEEP_BACKUPS" ]]; then
      if [[ $DRY_RUN -eq 1 ]]; then
        echo "  [dry-run] 将清理历史备份 $d"
      else
        rm -rf "$d" 2>/dev/null || echo "提示: safe-delete 拦截删除（不影响本次派生），需手动清理 $d（与插件目录平级，详见 references/faq.md Q6）"
      fi
    fi
  done
fi

# 1. 清空可变内容（保留 1.0.0/ 骨架，host 锁定路径）
if [[ $DRY_RUN -eq 1 ]]; then
  echo "  [dry-run] 将清空 $VER_DIR 下的 scripts/ hooks/ skills/"
else
  if ! rm -rf "$VER_DIR/scripts" "$VER_DIR/hooks" "$VER_DIR/skills" 2>/dev/null; then
    echo "  [WARN] 清空步骤被 safe-delete 拦截：不影响后续覆盖复制继续执行，但完成后必须 diff -r 逐文件比对（见 references/faq.md Q4）。"
  fi
fi

# 2. 重新映射（覆盖复制派生，不删除、直接覆盖，规避 safe-delete）
if [[ $DRY_RUN -eq 0 ]]; then
  mkdir -p "$VER_DIR/scripts" "$VER_DIR/hooks" "$SKILL_DIR/references"
fi

COPIED_PY=()
if [[ -d "$SRC/scripts" ]]; then
  shopt -s nullglob
  for p in "$SRC"/scripts/*.py; do
    if [[ $DRY_RUN -eq 1 ]]; then
      echo "  [dry-run] 复制 $p -> $VER_DIR/scripts"
    else
      cp "$p" "$VER_DIR/scripts/"
    fi
    COPIED_PY+=("$(basename "$p")")
  done
  shopt -u nullglob
  if [[ ${#COPIED_PY[@]} -eq 0 ]]; then echo "  skip（无 .py 文件）: $SRC/scripts"; fi
else
  echo "  skip（目录不存在）: $SRC/scripts"
fi

HAS_HOOKS=0
if copy_mapped "$SRC/hooks/hooks.json" "$VER_DIR/hooks/" 0; then HAS_HOOKS=1; fi
copy_mapped "$SRC/SKILL.md" "$SKILL_DIR/SKILL.md" 1 || true
copy_mapped "$SRC/README.md" "$SKILL_DIR/README.md" 0 || true
copy_mapped "$SRC"/references/*.md "$SKILL_DIR/references/" 0 || true
copy_mapped "$SRC/package.json" "$VER_DIR/package.json" 1 || true
copy_mapped "$SRC/test-prompts.json" "$VER_DIR/test-prompts.json" 0 || true
if [[ $MISSING -eq 1 ]]; then echo "[FAIL] 缺少必需文件，终止"; exit 1; fi

# 2.5 生成 .codebuddy-plugin/plugin.json（派生产物，字段取自实盘 package.json）
PLUG_DIR="$VER_DIR/.codebuddy-plugin"
if [[ -f "$SRC/package.json" ]]; then
  VER=$(grep -m1 '"version"' "$SRC/package.json" | sed 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/') || VER="0.0.0"
  DESC=$(grep -m1 '"description"' "$SRC/package.json" | sed 's/.*"description"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/') || DESC="$CACHE_PLUGIN_ID"
  REPO=$(grep -m1 '"repository"' "$SRC/package.json" | sed 's/.*"repository"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/') || REPO=""
  if [[ -z "$VER" ]]; then VER="0.0.0"; fi
  if [[ -z "$DESC" ]]; then DESC="$CACHE_PLUGIN_ID"; fi
  HOOKS_LINE=""
  if [[ $HAS_HOOKS -eq 1 ]]; then HOOKS_LINE=",
  \"hooks\": \"hooks/hooks.json\""; fi
  REPO_LINES=""
  if [[ -n "$REPO" ]]; then REPO_LINES=",
  \"homepage\": \"$REPO\",
  \"repository\": \"$REPO\""; fi
  if [[ $DRY_RUN -eq 1 ]]; then
    echo "  [dry-run] 将生成 $PLUG_DIR/plugin.json (name=$CACHE_PLUGIN_ID, version=$VER)"
  else
    mkdir -p "$PLUG_DIR"
    cat > "$PLUG_DIR/plugin.json" <<EOF
{
  "name": "$CACHE_PLUGIN_ID",
  "version": "$VER",
  "description": "$DESC",
  "author": { "name": "KK大叔" }$REPO_LINES$HOOKS_LINE
}
EOF
    echo "已生成 .codebuddy-plugin/plugin.json (name=$CACHE_PLUGIN_ID, version=$VER)"
  fi
else
  echo "  skip（无 package.json，跳过 plugin.json 生成）"
fi

# 3. 清理派生产物
if [[ $DRY_RUN -eq 0 ]]; then rm -rf "$VER_DIR/scripts/__pycache__" 2>/dev/null || true; fi

# 4. 校验：默认自动推导（复制了什么就校验什么），-VerifyFiles 可显式覆盖
FILES=("$SKILL_DIR/SKILL.md")
if [[ -n "$VERIFY_FILES" ]]; then
  IFS=',' read -ra VF <<< "$VERIFY_FILES"
  for rel in "${VF[@]}"; do
    rel="$(echo "$rel" | xargs)"
    if [[ -n "$rel" ]]; then FILES+=("$VER_DIR/$rel"); fi
  done
else
  if [[ $HAS_HOOKS -eq 1 ]]; then FILES+=("$VER_DIR/hooks/hooks.json"); fi
  if [[ ${#COPIED_PY[@]} -gt 0 ]]; then
    for n in "${COPIED_PY[@]}"; do FILES+=("$VER_DIR/scripts/$n"); done
  fi
fi

if [[ $DRY_RUN -eq 1 ]]; then
  echo "==> 校验清单（${#FILES[@]} 项）："
  for f in "${FILES[@]}"; do echo "  ? $f"; done
  echo "[OK] DryRun 完成，未写入任何文件。"
  exit 0
fi

FAIL=0
for f in "${FILES[@]}"; do
  if [[ -f "$f" ]]; then echo "OK  $f"; else echo "MISSING $f"; FAIL=1; fi
done
if [[ $FAIL -eq 1 ]]; then echo "[FAIL] 校验未通过，cache 可能未完整派生"; exit 1; fi
echo "[OK] cache 实例已从实盘派生（内容版本见 package.json）。重启 host 后加载生效。"

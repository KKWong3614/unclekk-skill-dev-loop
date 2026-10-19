# 端到端完整演示 | End-to-End Walkthrough

> 用一个虚构的 `unclekk-demo-skill` 把四步闭环完整走一遍。所有路径走环境变量（规则 14）。
> A full pass of the four-step loop with a fictional `unclekk-demo-skill`.

## 第 0 步 · 环境准备（一次性） | Setup

```bash
# Git Bash：设实盘根与 cache 根（cache 根有 $HOME 默认值，可不设）
export SKILL_DEV_REALDISK='<你的实盘根>'
export SKILL_DEV_CACHEROOT="$HOME/.workbuddy/plugins/cache/codebuddy-plugins-official"
# 实盘形态必需两个文件：SKILL.md + package.json（缺 package.json 会报"缺少必需文件"，见 FAQ Q3）
ls "$SKILL_DEV_REALDISK/unclekk-demo-skill"
```

## 第 1 步 · 规范自检 → 修改 → 提交 | Audit → Edit → Commit

```bash
# 改动前先跑一次 18 项审计（ERROR 级必须清零再动手）
python3 "$SKILL_DEV_REALDISK/unclekk-skill-spec/scripts/spec_audit.py" \
        --path "$SKILL_DEV_REALDISK/unclekk-demo-skill" --target skillhub
# 然后在实盘 git 仓库里改 SKILL.md / scripts / hooks / references，改完提交
cd "$SKILL_DEV_REALDISK/unclekk-demo-skill" && git add -A && git commit -m "feat: xxx"
```

## 第 2 步 · DryRun 预览 → 正式派生 | Preview then Sync

```powershell
# PowerShell：先预览（不写任何文件），确认源/目标两个路径都对
powershell -ExecutionPolicy Bypass -File "<用户主目录>\.workbuddy\skills\unclekk-skill-dev-loop\scripts\sync-to-cache.ps1" -Slug unclekk-demo-skill -DryRun
# 确认无误后正式派生（cache 插件ID 自动 = slug 去掉 unclekk- 前缀 → demo-skill）
powershell -ExecutionPolicy Bypass -File "<用户主目录>\.workbuddy\skills\unclekk-skill-dev-loop\scripts\sync-to-cache.ps1" -Slug unclekk-demo-skill
```

## 第 3 步 · 重启 host | Restart

完全退出并重新打开 WorkBuddy 桌面应用。改的是 `scripts/*.py` 可跳过（即时生效）；改了 `SKILL.md` / `hooks.json` / `package.json` 等元数据则**必须重启**。

## 第 4 步 · 端到端验证 | Verify

```bash
# 本 skill 无 hook → 用内容一致性判据（无输出 = 完全一致）
diff -r "$SKILL_DEV_REALDISK/unclekk-demo-skill/scripts" "$SKILL_DEV_CACHEROOT/demo-skill/1.0.0/scripts" --exclude=__pycache__
diff "$SKILL_DEV_REALDISK/unclekk-demo-skill/SKILL.md" "$SKILL_DEV_CACHEROOT/demo-skill/1.0.0/skills/demo-skill/SKILL.md"
grep -m1 '"version"' "$SKILL_DEV_CACHEROOT/demo-skill/1.0.0/.codebuddy-plugin/plugin.json"
```

- `diff` 无差异 **且** version 与 package.json 相同 → 派生成功 ✓
- 有差异 → 大概率是 Q4 的假成功，重跑 sync 或改用手动覆盖复制
- 改完重启后 Agent 会话里 skill 行为仍不对 → 回第 3 步（重启不彻底是最常见原因）

## 第 5 步 · 发布前（铁律 2） | Before Publish

先把 `displayName` / `summary` / `description`（均中英双语）/ `slug` / `version` / `license` / `tags`
整理给用户**确认，不点头不发布**；确认后：

```bash
export MSYS_NO_PATHCONV=1
skillhub publish "$SKILL_DEV_REALDISK/unclekk-demo-skill" --dry-run   # 先本地预检
skillhub publish "$SKILL_DEV_REALDISK/unclekk-demo-skill" --changelog "本次变更说明"
```

**全程避坑清单**：DryRun 先行 → sync 后必须 `diff -r`（别信退出码）→ 元数据改动必重启 → 发布前字段必确认。逐条反例见 SKILL.md 反例黑名单。

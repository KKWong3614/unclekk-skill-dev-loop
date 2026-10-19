---
slug: unclekk-skill-dev-loop
name: unclekk-skill-dev-loop
displayName: UncleKK 技能开发闭环（实盘→派生→验证） | UncleKK Skill Dev Loop (Real-Disk→Derive→Verify)
version: 1.3.0
summary: >-
  固化 KK 的 skill 开发铁律与"改 skill → 同步派生到 cache → 重启 host → 端到端验证"闭环，避免每次重新排查"改完不生效"。含通用化 sync-to-cache 脚本与 safe-delete 环境限制应对。 | Encodes KK's skill-dev disciplines and the "edit skill → derive to cache → restart host → end-to-end verify" loop, so we never re-debug "edit didn't take effect". Ships a generalized sync-to-cache script and works around the safe-delete environment constraint.
description: >-
  当用户要创建/修改/更新一个 WorkBuddy 插件式 skill（尤其是 unclekk- 系），或遇到「改了不生效」「host 没加载新 hooks」「cache 与实盘不一致」「发布前需确认对外信息」时加载。本 skill 是给 Agent 自己用的开发流程纪律（非 hook 护栏）：①新建 skill 带 unclekk- 前缀；②每次 publish 前展示对外字段并获确认，不点头不发布；③绝不手改 cache，改动只在实盘 git 仓库、cache 由脚本派生。 | Load when creating/updating a WorkBuddy plugin-style skill (esp. unclekk-*), or when a skill changed but didn't take effect, the host didn't load new hooks, cache diverged from the real disk, or the listing needs confirming before a SkillHub publish. An Agent-side dev-process discipline (not a hook guardrail): unclekk- prefix on new skills; show and confirm the public listing fields before every publish; never hand-edit the cache (edits go to the real-disk git repo, cache is script-derived).
license: MIT
tags: [技能开发, 闭环, 实盘真相源, cache派生, 端到端验证, skillhub发布, unclekk, safe-delete]
triggers: [改skill, 更新skill, 新建skill, skill不生效, 改完不生效, 同步cache, 派生cache, 端到端验证skill, skill开发闭环, sync-to-cache, skill发布前验证, 发布前展示, skill规范, skill自检, skill审计, 13条]
---

# Skill Dev Loop（技能开发闭环 · 实盘→派生→验证）

**🔴 CHECKPOINT · 本 skill 是给 Agent 自己用的开发纪律，不是被 hook 自动触发的护栏。**

## 什么时候用我 | When to use me

| 你正在… | 就用我 |
|---|---|
| 改了 skill，验证后行为不对 | [FAQ Q5](references/faq.md) 三步排查 |
| 要把 skill 同步进系统 / 发 SkillHub | 四步闭环；首次走全流程看[端到端演示](references/walkthrough.md) |
| sync / hook / safe-delete 报错看不懂 | [FAQ](references/faq.md) 按症状索引 |

---

## 三条铁律（来自用户级 MEMORY.md，内化于此） | Three Hard Disciplines

| # | 铁律 | 含义 |
|---|------|------|
| 1 | **unclekk- 前缀** | 所有新建 skill 的 slug / name / 目录名一律 `unclekk-` 开头，无例外 |
| 2 | **发布前展示对外信息** | 每次 `skillhub publish` 前，先把 displayName / summary / description（中英双语）/ slug / version / license / tags 整理给用户确认，**不点头不发布**。其中 `displayName` 必须带 **`UncleKK`** 前缀；双语顺序：SkillHub 文档中文在前英文在后，GitHub 的 `README.md` 英文在前中文在后（细则见 `unclekk-skill-spec` 的发布检查单，此处不重复以免两处漂移） |
| 3 | **弃用 cache 工作依赖** | 所有创建/修改/审查只在**实盘文件**（如 `<实盘根>\<slug>\` git 仓库，实盘根由环境变量 `SKILL_DEV_REALDISK` 指定）做；cache 实例降格为"由实盘派生的运行时产物"，绝不手改 |

> 详细背景与取舍见 `references/disciplines.md`。
>
> **配套规范**：「skill 交付物该长什么样」的 14 条规范不在本 skill，见 **`unclekk-skill-spec`**（hook 自动注入并审计，无需手动加载）。本 skill 只管 *How to ship*，它管 *What to ship*。

---

## 架构：实盘 = 唯一真相源，cache = 派生 | Architecture

```
<实盘根>\<slug>\                ← 实盘 git 仓库 = 唯一真相源（所有改动在此）
       ├── SKILL.md  scripts/  hooks/  references/  package.json  test-prompts.json
                    │
                    │  sync-to-cache.ps1  (唯一派生通道，禁止手改 cache)
                    ▼
<用户主目录>\.workbuddy\plugins\cache\
   codebuddy-plugins-official\<cache-plugin-id>\1.0.0\   ← 派生产物，host 加载这里
       ├── scripts/  hooks/  package.json  test-prompts.json
       ├── .codebuddy-plugin\plugin.json      ← 由脚本生成（字段取自 package.json）
       └── skills\<cache-plugin-id>\SKILL.md  README.md  references/
```

**关键约束**
- **路径一律走环境变量（规则 14）**：`SKILL_DEV_REALDISK` = 实盘根，`SKILL_DEV_CACHEROOT` = cache 根（默认 `$HOME/.workbuddy/...`）。命令与脚本都不写死盘符路径；未设实盘根时 sync 脚本直接报错提示，不猜默认盘符。例：`export SKILL_DEV_REALDISK='<你的实盘根>'`。
- cache 目录名固定为 `1.0.0`（host 在 `installed_plugins.json` 写死 `installPath`），**不要改目录名**，只改内容。
- `<cache-plugin-id>` 通常是 `<slug>` 去掉 `unclekk-` 前缀（如 `unclekk-skill-misevolution-guard` → `skill-misevolution-guard`）。若不符，用脚本 `-CachePluginId` 显式指定。
- 内容版本以 `package.json` 的 `version` 字段为准；脚本会据此生成 `.codebuddy-plugin/plugin.json`，host 注册表 `installed_plugins.json` 的 `version` 字段需另条命令对齐（见下文"版本标签对齐"）。
- 只有 `SKILL.md` 与 `package.json` 是必需源；`hooks/`、`README.md`、`references/`、`test-prompts.json` 缺失时脚本跳过而非失败。

---

## 四步闭环 | The Four-Step Loop

### 步骤 0：先过规范自检（spec gate）
改动前/后各跑一次，确认没把 skill 写残（14 条：最小示例、版本、断链、受众、硬代码、兜底、触发、报告样例、FAQ、前缀、双语顺序、新手可读、路径不硬编码）：

```bash
python3 "$SKILL_DEV_REALDISK/unclekk-skill-spec/scripts/spec_audit.py" --path "$SKILL_DEV_REALDISK/<slug>" --target github
```

ERROR 级不通过先修再往下走（hook 平时已自动做，此步是手动兜底）。首次全流程 → [端到端演示](references/walkthrough.md)。

### 步骤 1：改（只在实盘）
在 `$SKILL_DEV_REALDISK/<slug>/`（实盘 git 仓库）里改 `SKILL.md` / `scripts/*.py` / hook 配置 / `references/*`。
**🛑 STOP · 绝不手改 cache 实例。** 任何改动先落实盘、提交 git，再走步骤 2 派生。

### 步骤 2：sync 派生到 cache

**权威脚本位置**（唯一真相源，实盘副本为分发用，必须同源）：
```
<用户主目录>\.workbuddy\skills\unclekk-skill-dev-loop\scripts\sync-to-cache.ps1
```

```powershell
# 预览映射（推荐先跑，不写任何文件）
powershell -ExecutionPolicy Bypass -File "<权威脚本>\sync-to-cache.ps1" -Slug <slug> -DryRun
# 正式派生（自动去 unclekk- 前缀推导 cache 插件ID；推导不符时加 -CachePluginId <id>）
powershell -ExecutionPolicy Bypass -File "<权威脚本>\sync-to-cache.ps1" -Slug <slug>
```

脚本做：备份旧 cache → 清空 → 条件覆盖复制 → 生成 `.codebuddy-plugin/plugin.json` → 校验。
全套参数（`-DryRun` / `-KeepBackups` / `-VerifyFiles` / 路径覆盖）与 Linux 版见 **`references/sync-reference.md`**。
**🛑 脚本分发纪律**：实盘副本必须与权威副本同源，不同源时从权威副本 `copy` 覆盖，绝不就地改写。

### 步骤 3：重启 host 加载
cache 改动**必须重启 host 才生效**（Agent 跑在 host 进程内，无法从会话内重启）。
最稳方式：**完全退出并重新打开 WorkBuddy 桌面应用**。
局部重载备选：设置 → 插件 里把该 skill 先「禁用」再「启用」（不如全重启稳）。

### 步骤 4：端到端验证

**4A · hook 型护栏（带 hook 配置，如 pmu-misevolution-guard）**
重启后，用一个含 `sk-` 前缀长令牌的测试 `SKILL.md` 实弹写入，确认 guard 是否拦截：
- **被拦截** → 工具调用被 hook 拒绝（`permissionDecision: deny`），文件不落盘 ✓ 闭环成功
- **未拦截** → 文件落盘，说明 host 仍加载旧 hooks，回到步骤 3
- **fail-open 兜底保障** → 即使脚本异常/缺失，也是 `exit 0` 放行，不会锁死工具（这是护栏自身的设计，非本 skill 新增）

探针示例（写入 `_probe/SKILL.md`，含一条符合 `sk-` + 长随机串格式的假令牌）：

```
sk-<自己现编 32 位随机串，仅用于触发检测，勿使用任何真实密钥>
```

⚠️ 不要用真实密钥做探针，也不要把探针内容固化进任何文件/记忆库；验证后清理探针目录（工作区路径的 `rm` 不受 cache 专属 safe-delete 限制）。

**4B · 无 hook 的 skill（如 SHE、本 skill 自身）**
"是否被 deny 拦截"不适用，改用**内容一致性判据**——cache 必须逐字节等于实盘：
```bash
# 逐文件比对（无输出 = 完全一致）
diff -r "$SKILL_DEV_REALDISK/<slug>/scripts" "$SKILL_DEV_CACHEROOT/<cache-plugin-id>/1.0.0/scripts" --exclude=__pycache__
diff "$SKILL_DEV_REALDISK/<slug>/SKILL.md" "$SKILL_DEV_CACHEROOT/<cache-plugin-id>/1.0.0/skills/<cache-plugin-id>/SKILL.md"
# 版本标签比对：package.json version 必须等于 cache 的 .codebuddy-plugin/plugin.json version
grep -m1 '"version"' "$SKILL_DEV_REALDISK/<slug>/package.json"
grep -m1 '"version"' "$SKILL_DEV_CACHEROOT/<cache-plugin-id>/1.0.0/.codebuddy-plugin/plugin.json"
```
判据：`diff` 无差异 **且** 两处 version 相同 = 派生成功；有差异 = 回到步骤 2 重跑 sync。
（若 plugin.json 版本落后于 package.json，说明上次 sync 后 package.json 又升版了，重跑 sync 即可。）

---

## 环境限制：safe-delete（务必知道） | Environment Constraint: safe-delete

WorkBuddy 的 safe-delete 对 cache 路径内**所有**删除操作硬拦截（bash `rm` / PowerShell `Remove-Item` / .NET 全拦，回收站失败 → fail-closed）。三条后果：❌ 不能"先删后建"重建 cache（改用 sync 的**覆盖复制派生**）；⚠️ 第二次起 sync 常报 `SAFE_DELETE_BULK_GUARD_ERROR` 且**退出码仍 0**（必须 `diff -r` 复核）；⚠️ `.bak` 备份可能删不掉（与插件目录**平级**，脚本报提示时手动清）。
**报错看不懂 → [FAQ](references/faq.md) Q4/Q6；完整说明见 `references/env-constraints.md` 第 1/7 节。**

---

## 发布前展示对外信息（铁律 2） | Show Public Listing Before Publish

每次 `skillhub publish` 前，整理以下字段给用户确认，**不点头不发布**：
- `displayName`（中英双语）
- `summary`（中英双语，一行）
- `description`（中英双语，详述）
- `slug` / `version` / `license` / `tags`

确认后发布（Git Bash 下务必 `MSYS_NO_PATHCONV=1` + `C:/` 路径，否则路径被静默错转成 `c:\c\`）：
```bash
export MSYS_NO_PATHCONV=1
skillhub publish "$SKILL_DEV_REALDISK/<slug>" --changelog "本次变更说明"   # 发布前建议先 --dry-run
```

---

## 版本标签对齐 | Version Label Alignment

注册表 `installed_plugins.json` 在 `.workbuddy\plugins\` 下（**不在** `plugins\cache\` 下）。若其 `version` 与 `package.json` 脱钩：用 Python 原子改该条 `version`（**不动 `installPath`**），改完回读校验；⚠️ 条目是**数组**、可能含多个历史版本对象，别盲改第一个匹配项。完整步骤与诊断脚本见 `references/env-constraints.md` 第 8 节。

---

## 反例黑名单 | Anti-Patterns

| # | 反模式 | 为什么不要 | 替代 |
|---|--------|-----------|------|
| 1 | 直接手改 cache 实例 | cache 非 git、host 可能覆盖、版本易脱钩 | 只改实盘，sync 派生 |
| 2 | 改完不等重启就验证 | host 加载的是旧 hooks，验证无意义 | 先重启 host 再端到端验证 |
| 3 | 发布前不展示对外信息 | 违反铁律 2，可能发出错误元数据 | 先整理字段给用户确认 |
| 4 | 新建 skill 不带 unclekk- 前缀 | 违反铁律 1，与 KK 系命名冲突 | slug 一律 unclekk- 开头 |
| 5 | 在 cache 路径内用 rm 删 .bak | safe-delete 拦截，删除静默失败 | 脚本已自动清理（保留最新 3 个）；仅当脚本报"拦截"提示时才手动清 |
| 6 | 就地改写实盘根的 sync 脚本副本 | 副本与权威副本漂移，修复丢失 | 永远从权威副本 `...\unclekk-skill-dev-loop\scripts\` 复制覆盖 |
| 7 | 拿真实密钥当护栏探针 | 密钥可能流入日志/记忆库 | 用现编随机串，验证后删除，不固化 |
| 8 | 改完 skill 不做规范自检 | 可能缺最小示例/断链/受众说明就发出去 | 步骤 0 跑 `spec_audit.py`（hook 平时已自动做） |
| 9 | sync 完只看退出码 | 被 safe-delete 拦截时脚本抛异常但退出码仍 0 | 必须 `diff -r` 逐文件比对确认 |

---

## 参考文件 | References

- `scripts/sync-to-cache.ps1` — **权威**派生脚本（Windows，参数化 -Slug / -DryRun / -VerifyFiles / -KeepBackups）
- `scripts/sync-to-cache.sh` — Linux/Git Bash 版派生脚本（行为与 .ps1 对齐；Windows 下优先用 .ps1）
- `references/disciplines.md` — 三条铁律的背景与取舍
- `references/env-constraints.md` — safe-delete / 路径 / 版本锁定等环境限制详述
- `references/faq.md` — 按症状索引的 FAQ（sync 报错 / 改了不生效 / 假成功 / hook 不触发）
- `references/walkthrough.md` — 端到端完整演示（准备 → 自检 → sync → 重启 → 验证 → 发布）
- **`unclekk-skill-spec`**（独立 skill）— 14 条交付规范 + 硬代码审计器，hook 自动触发，写 `SKILL.md` 时自动注入并审计

---

## 变更记录 | Changelog

- **v1.3.0**（2026-09-28）：按 SkillHub 测评补短板——新增 `references/faq.md`（8 条按症状索引的 FAQ）与 `references/walkthrough.md`（端到端演示）；顶部加白话「什么时候用我」表；safe-delete / 版本对齐章节压缩为指针式；sync 脚本报错改「现象 + 怎么修」、清空步骤加拦截防御。
- **v1.2.1**（2026-09-25）：全包路径通用化以符合规则 14（C18）——sync 脚本实盘根不再回退到硬编码盘符，未设 `SKILL_DEV_REALDISK` 且未传 `-RealDiskRoot` 时直接报错提示；`.sh` 的 cache 根改用 `$HOME` 推导；文档 14 处命令示例改为环境变量 / 占位符式；步骤 0 清单同步至 14 条。
- **v1.2.0**（2026-09-07）：新增步骤 0（规范自检，指向 `unclekk-skill-spec`）；铁律 2 补 displayName 与双语顺序；补 sync 二次报 `SAFE_DELETE_BULK_GUARD_ERROR` 且退出码仍 0 的实测坑；反例表加 2 条。
- **v1.1.0**（2026-09-06）：校验清单自动推导 + `-VerifyFiles` 覆盖；复制加存在性保护；新增 `-DryRun` / `-KeepBackups`；生成 `.codebuddy-plugin/plugin.json`；默认路径走环境变量；探针示例改占位符（禁固化真实密钥）。
- **v1.0.0**（2026-08-28）：初版，固化三条铁律与四步闭环。

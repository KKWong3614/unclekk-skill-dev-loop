# 三条铁律的背景与取舍 | Three Hard Disciplines — Background & Rationale

本文件详述 `unclekk-skill-dev-loop` 三条铁律的来源、边界与为何定为硬纪律（不可被"这次就手改一下"式的临时便利打破）。

---

## 铁律 1：unclekk- 前缀 | The `unclekk-` Prefix

**规则**：所有新建 skill 的 `slug` / `name` / 目录名一律 `unclekk-` 开头，无例外。

**来源**：KK（祈）的个人技能品牌前缀。既有「Skill 命名规范」原仅说"KK 造的技能适用"，2026-08-28 升级为**所有新建无例外**的硬纪律。

**为何硬**：
- SkillHub / 本地 plugins 多源共存，无前缀易与其他作者同名 skill 冲突（触发 409 或静默覆盖）。
- 前缀即"出处标签"，便于跨设备同步、审计、撤销时一眼识别归属。

**边界**：仅约束**新建**。历史已存在的非 `unclekk-` 技能不强制改名（除非发布冲突）。

---

## 铁律 2：发布前展示对外信息 | Show Public Info Before Publish

**规则**：每次 `skillhub publish` 前，先把 `displayName` / `summary` / `description`（中英双语）/ `slug` / `version` / `license` / `tags` 整理给用户确认，**用户不点头不发布**。

**来源**：2026-08-28 用户明确要求"每次推上 skillhub 前必须向我展示 skill 的对外展示信息"。

**为何硬**：
- SkillHub 列表页/详情页直接呈现这些字段，发错元数据（错别字、误导 summary、错误 license）更正成本高、且已公开。
- 双语字段易在迭代中漂移，发布前一次人工核对能拦截"代码改了文档没改"的脱节。

**边界**：仅 `publish`（真实外发）需要确认；`--dry-run`（本地格式校验）不需要用户确认，但建议顺带展示。

---

## 铁律 3：弃用 cache 工作依赖，全走实盘 | No Cache as Work Dependency

**规则**：所有 skill 的创建/修改/审查只在**实盘文件**（如 `<实盘根>\<slug>\` 这个 git 仓库，实盘根由环境变量 `SKILL_DEV_REALDISK` 指定）做；cache 实例降格为"由实盘派生的运行时产物"，绝不手改。

**来源**：2026-08-28 用户质疑"利用 cache 实例是否会带来太多不确定性"，结论为**会**——cache 是 host 托管目录、非 git、host 可能随时覆盖、版本标签易与内容脱钩。遂定为硬纪律。

**为何硬**（三个不确定性根源）：
1. **cache 不在版本控制**：手改只活在隐藏目录，host 重装/覆盖即蒸发，无从追溯。
2. **host 随时覆盖**：`installed_plugins.json` 把 `installPath` 写死，cache 被视为"从源派生"。marketplaces 源不存在时当下风险低，但一旦"更新插件"/从 SkillHub 重同步即被 canonical 包覆盖，修复蒸发甚至复活坏版本。
3. **版本标签脱钩**：目录标 `1.0.0`、内容却 `1.2.0` 时，任何"按版本判断要不要更新"的机制会误判"已最新"而跳过你的修复。

**正确架构**：
- `<实盘根>\<slug>\` = 唯一真相源（git 管，所有改动在此）
- cache = 纯运行时产物，由 `sync-to-cache.ps1` 重新生成，永不手改
- hooks.json 统一用 `${CODEBUDDY_PLUGIN_ROOT}`（本地与安装后都能跑，摆脱 SkillHub 平台 `__FILE_PATH__` 替换依赖——那正是原始 P0 的祸根）

**边界**：审查第三方 skill（如 `skill-auditor` 审计他人包）时可只读 cache/已检副本，但**产出修复**必须落回实盘真相源。

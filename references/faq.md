# 常见问题速查 | FAQ

> 按症状索引。先在这里找，找不到再翻 [env-constraints.md](env-constraints.md) 与 [sync-reference.md](sync-reference.md)。
> Indexed by symptom; check here first, then the constraint and sync reference docs.

---

## Q1. sync 一上来就报「未指定实盘根」 | "Real-disk root not specified"

**现象**：`sync-to-cache.ps1` / `.sh` 启动即报错退出，提示设置 `SKILL_DEV_REALDISK`。
**原因**：v1.2.1 起脚本不再猜测默认盘符路径（规则 14）——实盘根必须显式给出。
**修复**：设一次环境变量，之后所有命令直接可用：

```bash
# Git Bash
export SKILL_DEV_REALDISK='<你的实盘根>'      # 例：export SKILL_DEV_REALDISK='/d/your-repo-root'
# PowerShell
$env:SKILL_DEV_REALDISK = '<你的实盘根>'
```

**坑点**：早期版本回退到写死的盘符路径，换机器后静默指向不存在的目录——看起来"能跑"，实际源是空的。宁可报错，不要猜。

---

## Q2. 报「实盘目录不存在」 | "Real-disk directory not found"

**现象**：`实盘目录不存在: <路径>` 后退出 1。
**原因**：`$SKILL_DEV_REALDISK/<slug>` 拼出来的路径不通——变量值不对，或该 slug 目录还没建。
**修复**（三步排查）：

```bash
echo "$SKILL_DEV_REALDISK"        # ① 变量是否指向实盘根（不是实盘根/<slug>）
ls "$SKILL_DEV_REALDISK"          # ② <slug> 目录是否在列表里
bash sync-to-cache.sh -Slug <slug> -DryRun   # ③ 先 DryRun 预览两个路径再真跑
```

**坑点**：变量应指向**实盘根**（仓库们的父目录），脚本自己拼 `/<slug>`。把变量设成了 `.../<slug>` 会导致双重拼接。

---

## Q3. 报「缺少必需文件: package.json」 | "Missing required file"

**现象**：sync 中途打印 `ERROR: 缺少必需文件: .../package.json`，退出 1。
**原因**：实盘形态里 `SKILL.md` 与 `package.json` 是**必需源**（版本号以 package.json 为准）。用户级 `~/.workbuddy/skills/<slug>/` 下的散装 skill 往往没有这个文件。
**修复**：在实盘根补一个最小 `package.json`：

```json
{ "name": "unclekk-xxx", "version": "1.0.0", "description": "一句话简介", "license": "MIT" }
```

**坑点**：`version` 是 cache 内容版本的唯一权威——只改 SKILL.md 不升 package.json 的 version，`.codebuddy-plugin/plugin.json` 的版本标签就会落后（见 Q7）。

---

## Q4. 第二次 sync 报 SAFE_DELETE_BULK_GUARD_ERROR，但退出码是 0 | Silent failure

**现象**：首次 sync 正常，第二次起整段抛 `SAFE_DELETE_BULK_GUARD_ERROR`，**一个文件都没写**，可退出码仍是 0。
**原因**：WorkBuddy 的 safe-delete 对 cache 路径内的批量删除硬拦截（清空步骤被拦），而脚本没把拦截翻译成非零退出码。
**修复**：sync 后**必须 `diff -r` 比对**（步骤 4B），不一致就改用手动覆盖复制绕过（[env-constraints.md](env-constraints.md) 第 7 节的 `cp -f` 五连）。
**坑点**：只看退出码会误判成功——这是本 skill 反例黑名单第 9 条。

---

## Q5. 改了 skill，但怎么都不生效 | "Edit didn't take effect"

**原因**：host 加载的是 cache 实例，且**元数据改动必须重启 host**。改动没生效通常是三环断了一环。
**修复**（顺序排查）：

```bash
# ① 实盘 vs cache 内容一致吗？（无输出 = 一致）
diff -r "$SKILL_DEV_REALDISK/<slug>/scripts" "$SKILL_DEV_CACHEROOT/<cache-plugin-id>/1.0.0/scripts" --exclude=__pycache__
```

② 不一致 → 重跑 sync（注意 Q4 的假成功）；③ 一致 → **完全退出并重开 WorkBuddy**（改的是 `hooks.json` / `package.json` / `plugin.json` 等元数据就必须重启；只有 `scripts/*.py` 是例外，改完即时生效）。

---

## Q6. cache 目录下的 .bak 备份删不掉 | Backups cannot be deleted

**现象**：手动 `rm` / `Remove-Item` cache 路径下的 `<cache-plugin-id>.bak-*` 静默失败。
**原因**：safe-delete 对 cache 路径内**所有**删除操作硬拦截（含 .NET 层）。
**修复**：仅在脚本打印「safe-delete 拦截」提示时，用文件管理器手动清。脚本默认自动保留最新 3 个，多数时候不用管。
**坑点**：备份与插件目录**平级**（`<cache-plugin-id>.bak-<时间戳>`），不是 `1.0.0` 里面的东西。

---

## Q7. plugin.json 的 version 落后于 package.json | Version label drift

**现象**：步骤 4B 比对发现 `.codebuddy-plugin/plugin.json` 的 `version` ≠ 实盘 `package.json` 的 `version`。
**原因**：上次 sync 之后 package.json 又升了版，cache 还是旧派生。
**修复**：重跑一次 sync 即可，无需手改 cache。若注册表 `installed_plugins.json` 的 version 也脱钩，按 [env-constraints.md](env-constraints.md) 第 8 节对齐。

---

## Q8. hook 型护栏装好后一直不触发 | Hook never fires

**原因**：只改 `installed_plugins.json` 不够——host 认识插件但**不加载其 hooks**，还差 `settings.json` 的 `enabledPlugins` 一步。
**修复**：两步都做（见 [env-constraints.md](env-constraints.md) 第 9 节），改完完全重启。验证是否真的被调用：给 gate 脚本加执行留痕（append 到临时 trace 文件）再触发一次写操作查留痕——report-only 的 systemMessage 走 UI 通道、不进 Agent 上下文，"看不到"≠"没执行"。

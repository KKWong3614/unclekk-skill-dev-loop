# sync-to-cache 参数与行为 | Sync Script Reference

> 本文件是 [../SKILL.md](../SKILL.md) 步骤 2 的展开。主文件只留最短可执行命令。
> Expands step 2 of [../SKILL.md](../SKILL.md); the main file keeps only the runnable commands.

## 权威脚本位置 | Authoritative script

```
<用户主目录>\.workbuddy\skills\unclekk-skill-dev-loop\scripts\sync-to-cache.ps1
```

实盘项目根可有同名副本（分发用），但必须与权威副本**同源**；不同源时以权威副本为准，直接覆盖：
```bash
copy "%USERPROFILE%\.workbuddy\skills\unclekk-skill-dev-loop\scripts\sync-to-cache.ps1" "%SKILL_DEV_REALDISK%\<slug>\"
```

## 可选参数 | Options

| 参数 | 作用 |
|------|------|
| `-DryRun` | 只打印映射与校验清单，不写任何文件 |
| `-VerifyFiles "scripts/a.py,hooks/hooks.json"` | 显式指定校验清单（默认自动推导：复制了什么就校验什么） |
| `-NoBackup` | 跳过备份 |
| `-KeepBackups N` | 备份保留个数，默认 3（超量自动清理，被 safe-delete 拦截时降级为警告） |
| `-RealDiskRoot` / `-CacheRoot` | 覆盖默认路径；也可用环境变量 `SKILL_DEV_REALDISK` / `SKILL_DEV_CACHEROOT` |

## 脚本做了什么 | What it does

备份旧 cache（`<cache-plugin-id>.bak-<时间戳>`，保留最新 3 个）→ 清空可变内容 → 按映射**条件**覆盖复制
（源不存在则跳过，仅 `SKILL.md` / `package.json` 缺失才报错）→ 生成 `.codebuddy-plugin/plugin.json`
（字段取自 `package.json` 的 name/version/description/url.repository）→ 清 `__pycache__` → 校验。

## Linux / Git Bash

```bash
bash sync-to-cache.sh -Slug <slug> [-DryRun]
```

注意 Git Bash 下删除会被 safe-delete 拦截（见 `env-constraints.md` 第 7 节）；Windows 下优先用 `.ps1`。

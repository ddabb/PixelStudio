# AGENTS.md — AI 代理协作规则（PixelStudio）

本文件是 AI 编码代理在本仓库工作时的持久规则，每次会话自动生效。

## 语言（用户明确要求，长期有效）

- **始终使用中文与用户交流**：所有回复、说明、提问、确认、总结一律使用中文，不切换到英文。
- 代码注释、文档、提交信息沿用仓库现有中文风格。

## 每次会话必做的项目约定

- 护栏脚本必须全绿后再结束任务：
  - `py -3 scripts/check_strings.py --check`（base/en 字符串键一致）
  - `py -3 scripts/code_stats.py --check`（entry/src/main/ets 行数 ≤900，白名单只减不增）
- 任务结束前必须 `build_project` 成功。
- 单测在模拟器运行：
  `hdc shell aa test -b com.ddabb.pixelstudio -m entry_test -s unittest OpenHarmonyTestRunner -s timeout 15000`

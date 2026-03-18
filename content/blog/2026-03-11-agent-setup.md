+++
title = 'Claude Code 项目配置完整手册'
date = 2026-03-11T10:51:47+08:00
draft = false
tags = ["Tooling"]
+++
# Claude Code 项目配置完整手册

> 从零开始配置 Claude Code 项目：目录结构、CLAUDE.md、Skills、Memory、Subagents 一站式指南。

---

## 目录

1. [项目初始化 Checklist](#1-项目初始化-checklist)
2. [目录结构模板](#2-目录结构模板)
3. [CLAUDE.md 配置](#3-claudemd-配置)
4. [Settings 配置](#4-settings-配置)
5. [Skills 配置](#5-skills-配置)
6. [Memory 持久记忆系统](#6-memory-持久记忆系统)
7. [Subagents 配置](#7-subagents-配置)
8. [MCP Servers 配置](#8-mcp-servers-配置)
9. [Hooks 生命周期钩子](#9-hooks-生命周期钩子)
10. [示例 Subagents](#10-示例-subagents)
11. [团队协作最佳实践](#11-团队协作最佳实践)

---

## 1. 项目初始化 Checklist

按照以下顺序完成项目配置，每一步完成后打勾：

### 第一阶段：基础配置

- [ ] 创建项目目录结构（参照 [第 2 节](#2-目录结构模板)）
- [ ] 编写根目录 `CLAUDE.md`（项目级指令，团队共享）
- [ ] 编写个人 `~/.claude/CLAUDE.md`（用户级偏好，不入版本控制）
- [ ] 创建 `.claude/settings.json`（hooks、权限、环境变量）

### 第二阶段：Skills 与 Memory

- [ ] 创建项目级 Skills 目录 `.claude/skills/`
- [ ] 编写所需 Skill 的 `SKILL.md`（参照 [第 5 节](#5-skills-配置)）
- [ ] 确认 Auto Memory 已启用（运行 `/memory` 查看）
- [ ] 如需要，创建 `.claude/rules/` 下的模块化规则文件

### 第三阶段：Subagents

- [ ] 创建项目级 Subagents 目录 `.claude/agents/`
- [ ] 编写自定义 Subagent `.md` 文件（参照 [第 7 节](#7-subagents-配置)）
- [ ] 如有 Subagent 使用 hooks，编写并测试验证脚本
- [ ] 配置 Subagent 的 memory 范围（user / project / local）

### 第四阶段：集成与验证

- [ ] 配置 `.mcp.json`（如需外部工具集成）
- [ ] 将需要团队共享的文件加入版本控制
- [ ] 启动 Claude Code 会话，运行 `/agents` 确认 subagents 加载
- [ ] 运行 `/memory` 确认 memory 系统正常
- [ ] 测试各 Skill 和 Subagent 是否按预期触发

---

## 2. 目录结构模板

```
my-project/
├── CLAUDE.md                          # 项目级指令（团队共享，入版本控制）
├── .mcp.json                          # MCP Server 配置（入版本控制）
│
├── .claude/
│   ├── settings.json                  # Hooks、权限、环境变量
│   ├── settings.local.json            # 个人本地设置（不入版本控制）
│   │
│   ├── agents/                        # 项目级 Subagents
│   │   ├── code-reviewer.md
│   │   ├── debugger.md
│   │   └── data-scientist.md
│   │
│   ├── skills/                        # 项目级 Skills
│   │   ├── testing-patterns/
│   │   │   └── SKILL.md
│   │   ├── api-conventions/
│   │   │   ├── SKILL.md
│   │   │   └── references/
│   │   │       └── api-schema.md
│   │   └── deploy/
│   │       ├── SKILL.md
│   │       └── scripts/
│   │           └── deploy.sh
│   │
│   ├── rules/                         # 模块化规则文件（按 glob 匹配）
│   │   ├── typescript.md              # 匹配 *.ts, *.tsx
│   │   ├── testing.md                 # 匹配 *.test.*, *.spec.*
│   │   └── api-routes.md             # 匹配 src/api/**
│   │
│   ├── agent-memory/                  # Subagent 项目级 memory（可入版本控制）
│   │   └── code-reviewer/
│   │       └── MEMORY.md
│   │
│   └── agent-memory-local/            # Subagent 本地 memory（不入版本控制）
│       └── debugger/
│           └── MEMORY.md
│
├── scripts/                           # Hook 和 Subagent 使用的脚本
│   ├── validate-readonly-query.sh
│   ├── validate-command.sh
│   └── run-linter.sh
│
└── src/                               # 项目源代码
    └── ...
```

### 用户级目录（不在项目中，全局生效）

```
~/.claude/
├── CLAUDE.md                          # 用户级指令（所有项目生效）
├── agents/                            # 用户级 Subagents
│   └── general-reviewer.md
├── skills/                            # 用户级 Skills
│   └── explain-code/
│       └── SKILL.md
├── agent-memory/                      # 用户级 Subagent memory
│   └── general-reviewer/
│       └── MEMORY.md
└── projects/
    └── <project-hash>/
        └── memory/                    # Auto Memory 存储位置
            ├── MEMORY.md              # 主入口（前 200 行自动加载）
            ├── debugging.md           # Claude 自动创建的主题文件
            └── api-conventions.md
```

### `.gitignore` 建议

```gitignore
# Claude Code 本地配置（不入版本控制）
.claude/settings.local.json
.claude/agent-memory-local/
```

---

## 3. CLAUDE.md 配置

CLAUDE.md 是 Claude Code 的持久记忆文件，每次会话启动时自动加载到系统提示中。

### 层级与优先级

| 层级 | 文件位置 | 范围 | 是否入版本控制 |
|------|---------|------|-------------|
| 用户级 | `~/.claude/CLAUDE.md` | 所有项目 | 否 |
| 项目级 | `项目根/CLAUDE.md` | 当前项目 | 是 |
| 模块化规则 | `.claude/rules/*.md` | 按 glob 匹配 | 是 |

### 项目级 CLAUDE.md 模板

```markdown
# 项目名称

## 快速信息
- **技术栈**: React, TypeScript, Node.js
- **测试命令**: `npm run test`
- **Lint 命令**: `npm run lint`
- **构建命令**: `npm run build`

## 关键目录
- `src/components/` - React 组件
- `src/api/` - API 层
- `src/utils/` - 工具函数
- `tests/` - 测试文件

## 代码风格
- TypeScript strict 模式
- 优先使用 interface 而非 type
- 禁止使用 any，用 unknown 替代
- 使用 arrow function
- 导入始终使用 @company/utils-v2，不要用 @company/utils

## 架构约束
- 不要修改 /generated/ 目录下的文件
- API 端点遵循 RESTful 命名规范
- 返回一致的错误格式

## Git 工作流
- 分支命名：feature/<ticket>, fix/<ticket>
- Conventional Commits 格式
- PR 必须经过 review 才能合并
```

### 用户级 CLAUDE.md 模板

```markdown
# 个人偏好

## 语言与风格
- 回复使用中文
- 代码注释使用英文
- 偏好简洁直接的解释

## 工具偏好
- 使用 pnpm 而非 npm
- 偏好 Vitest 做测试
- 使用 2 空格缩进
```

### 模块化规则文件示例

`.claude/rules/typescript.md`：

```markdown
---
globs: "**/*.ts,**/*.tsx"
---

# TypeScript 规则

- 所有函数必须有明确的返回类型
- 使用 strict 模式的所有特性
- enum 用 const enum 替代
- 禁止 any 类型
```

### CLAUDE.md 最佳实践

- 保持简洁，50 行 CLAUDE.md 约消耗 2,000 context tokens（不到可用窗口的 1%）
- 超过 200 行时考虑拆分到 `.claude/rules/` 或使用 `@path` 导入
- 定期让 Claude 审查和优化你的 CLAUDE.md
- CLAUDE.md 在 `/compact` 压缩后会从磁盘重新读取并注入，内容不会丢失

---

## 4. Settings 配置

`.claude/settings.json` 用于配置 hooks、权限和环境变量。

### 基础模板

```json
{
  "permissions": {
    "allow": [
      "Read",
      "Glob",
      "Grep",
      "Bash(npm run test:*)",
      "Bash(npm run lint)",
      "Bash(npm run build)"
    ],
    "deny": [
      "Bash(rm -rf *)",
      "Agent(Explore)"
    ]
  },
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Edit|Write",
        "hooks": [
          {
            "type": "command",
            "command": "[ \"$(git branch --show-current)\" != \"main\" ] || { echo '{\"block\": true, \"message\": \"Cannot edit on main branch\"}' >&2; exit 2; }",
            "timeout": 5
          }
        ]
      }
    ]
  },
  "autoMemoryEnabled": true
}
```

---

## 5. Skills 配置

Skills 是可重用的行为包，按需加载到 Claude 的上下文中。

### Skill 文件结构

```
skill-name/
├── SKILL.md                # 必需：frontmatter + 指令
└── 可选资源/
    ├── scripts/            # 可执行脚本
    ├── references/         # 参考文档（按需加载）
    └── assets/             # 模板、图标、字体等
```

### SKILL.md 格式

```markdown
---
name: testing-patterns
description: 项目测试模式和规范。当编写测试、修改测试文件或讨论测试策略时使用此 skill。即使用户没有明确要求，只要涉及测试相关话题就应该使用。
---

# 测试模式

## 框架
使用 Vitest + React Testing Library

## 文件命名
- 单元测试：`*.test.ts`
- 集成测试：`*.integration.test.ts`
- E2E 测试：`*.e2e.test.ts`

## 测试结构
每个测试文件遵循 Arrange-Act-Assert 模式：

...（详细指令）
```

### Skill 存储位置与范围

| 位置 | 范围 | 使用场景 |
|------|------|---------|
| `.claude/skills/<name>/SKILL.md` | 当前项目 | 项目特定的规范和工作流 |
| `~/.claude/skills/<name>/SKILL.md` | 所有项目 | 个人通用 skill |

### Frontmatter 关键字段

| 字段 | 必需 | 说明 |
|------|------|------|
| `name` | 是 | Skill 名称，同时作为 `/slash-command` |
| `description` | 是 | 触发描述（200 字符以内），Claude 根据此决定何时调用 |
| `disable-model-invocation` | 否 | 设为 `true` 则只能手动调用（适合 deploy 等有副作用的操作） |
| `user-invocable` | 否 | 设为 `false` 则只有 Claude 自动调用（适合背景知识类 skill） |
| `dependencies` | 否 | 所需的软件包 |

### Skill 编写最佳实践

- **SKILL.md 控制在 500 行以内**，详细参考材料放到单独文件中
- **描述要"推动性"**：不要写 "API 设计规范"，而要写 "API 设计规范。当用户提到 API、端点、路由、REST、GraphQL 或任何后端开发时都使用此 skill"
- **渐进式披露**：frontmatter 提供最小元数据 → SKILL.md 提供核心指令 → references/ 按需加载详细内容
- 使用 `/skill-name` 可手动调用，Claude 也会根据上下文自动触发

### Skill 与 Subagent 的结合

在 Subagent 的 frontmatter 中使用 `skills` 字段预加载 Skill 内容：

```yaml
---
name: api-developer
description: Implement API endpoints following team conventions
skills:
  - api-conventions
  - testing-patterns
---

Implement API endpoints. Follow the conventions and patterns from the preloaded skills.
```

注意：Skill 的完整内容会被注入到 subagent 上下文中，subagent 不继承父对话中的 skill，必须明确列出。

---

## 6. Memory 持久记忆系统

Claude Code 有两套互补的记忆系统，每次会话启动时都会加载。

### 6.1 CLAUDE.md 手动记忆

你手动编写的 CLAUDE.md 文件，详见 [第 3 节](#3-claudemd-配置)。

### 6.2 Auto Memory 自动记忆

Claude 在工作中自动积累的知识：构建命令、调试见解、架构笔记、代码风格偏好等。

**存储位置：**

```
~/.claude/projects/<project-hash>/memory/
├── MEMORY.md              # 主入口文件（前 200 行自动加载到每个会话）
├── debugging.md           # 主题文件（Claude 按需加载）
├── api-conventions.md     # 主题文件
└── ...                    # Claude 自动创建的其他主题
```

**关键特性：**

- 同一 git 仓库的所有 worktree 和子目录共享一个 Auto Memory 目录
- MEMORY.md 前 200 行自动注入每个会话，超过 200 行的部分需要 Claude 主动查阅
- 主题文件（debugging.md 等）按需加载
- Auto Memory 是机器本地的，不随版本控制

**管理命令：**

- `/memory` — 查看和管理 Auto Memory（含开关切换）
- 对话中说 "Remember that..."  或 "Don't forget..." — 触发 Claude 写入 MEMORY.md
- "Update your memory files with what you learned today" — 会话结束时手动触发保存

**开启/关闭：**

```json
// .claude/settings.json
{
  "autoMemoryEnabled": true
}
```

或在会话中运行 `/memory` 使用 toggle 开关。

### 6.3 Subagent 持久 Memory

Subagent 可以拥有独立的持久记忆目录，跨会话积累领域知识。

在 subagent 的 frontmatter 中配置 `memory` 字段：

```yaml
---
name: code-reviewer
description: Reviews code for quality and best practices
memory: user
---

You are a code reviewer. As you review code, update your agent memory with
patterns, conventions, and recurring issues you discover.
```

**三种范围：**

| 范围 | 存储位置 | 使用场景 |
|------|---------|---------|
| `user` | `~/.claude/agent-memory/<agent-name>/` | 所有项目通用的学习（推荐默认） |
| `project` | `.claude/agent-memory/<agent-name>/` | 项目特定知识，可通过版本控制共享 |
| `local` | `.claude/agent-memory-local/<agent-name>/` | 项目特定但不入版本控制 |

**启用 memory 后的行为：**

- Subagent 的系统提示会包含 `MEMORY.md` 的前 200 行
- Read、Write、Edit 工具自动启用（即使 tools 字段未列出）
- Subagent 可以在 memory 目录中读写文件

**Subagent Memory 使用技巧：**

1. 工作前让 subagent 查阅记忆：

   ```text
   Review this PR, and check your memory for patterns you've seen before.
   ```

2. 工作后让 subagent 保存学习：

   ```text
   Now that you're done, save what you learned to your memory.
   ```

3. 在 subagent 的系统提示中加入主动维护指令：

   ```markdown
   Update your agent memory as you discover codepaths, patterns, library
   locations, and key architectural decisions. Write concise notes about
   what you found and where.
   ```

### 6.4 Memory 系统全景图

```
┌─────────────────────────────────────────────────────────────┐
│                     会话启动时自动加载                         │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  ~/.claude/CLAUDE.md           用户级指令（全局）               │
│  项目根/CLAUDE.md              项目级指令（团队共享）            │
│  .claude/rules/*.md            模块化规则（按 glob 匹配）      │
│  Auto Memory MEMORY.md         自动记忆（前 200 行）           │
│                                                             │
├─────────────────────────────────────────────────────────────┤
│                     按需加载                                  │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  Skills (SKILL.md)             用户调用或 Claude 自动触发      │
│  Auto Memory 主题文件            Claude 需要时查阅              │
│  Subagent Memory               Subagent 启动时加载             │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

---

## 7. Subagents 配置

Subagent 是在独立 context window 中运行的专门 AI 助手，具有自定义系统提示、工具限制和独立权限。

### 7.1 内置 Subagents

| Subagent | Model | Tools | 用途 |
|----------|-------|-------|------|
| **Explore** | Haiku | 只读 | 文件发现、代码搜索、代码库探索 |
| **Plan** | 继承 | 只读 | Plan mode 下的代码库研究 |
| **General-purpose** | 继承 | 所有 | 复杂研究、多步骤操作、代码修改 |
| Bash | 继承 | — | 在独立上下文中运行终端命令 |
| Claude Code Guide | Haiku | — | 回答 Claude Code 功能问题 |

### 7.2 创建 Subagent

**方式一：交互式创建（推荐）**

```text
/agents → Create new agent → 选择范围 → Generate with Claude 或手动编写
```

**方式二：手动创建文件**

在 `.claude/agents/`（项目级）或 `~/.claude/agents/`（用户级）创建 `.md` 文件。

**方式三：CLI 标志（临时会话）**

```bash
claude --agents '{
  "code-reviewer": {
    "description": "Expert code reviewer. Use proactively after code changes.",
    "prompt": "You are a senior code reviewer...",
    "tools": ["Read", "Grep", "Glob", "Bash"],
    "model": "sonnet"
  }
}'
```

### 7.3 Subagent 范围与优先级

| 位置 | 范围 | 优先级 | 是否入版本控制 |
|------|------|--------|-------------|
| `--agents` CLI 标志 | 当前会话 | 1（最高） | 否 |
| `.claude/agents/` | 当前项目 | 2 | 是 |
| `~/.claude/agents/` | 所有项目 | 3 | 否 |
| 插件 `agents/` 目录 | 启用插件的位置 | 4（最低） | — |

### 7.4 Subagent 文件格式

```markdown
---
name: code-reviewer
description: Reviews code for quality and best practices. Use proactively after code changes.
tools: Read, Glob, Grep, Bash
disallowedTools: Write, Edit
model: sonnet
permissionMode: default
maxTurns: 20
memory: project
skills:
  - api-conventions
  - testing-patterns
background: false
---

你的系统提示写在这里。这部分 Markdown 内容会成为 subagent 的系统提示。

Subagent 只接收此系统提示和基本环境信息，不会收到完整的 Claude Code 系统提示。
```

### 7.5 Frontmatter 完整字段

| 字段 | 必需 | 说明 |
|------|------|------|
| `name` | 是 | 唯一标识符（小写字母和连字符） |
| `description` | 是 | Claude 何时应委托给此 subagent |
| `tools` | 否 | 可使用的工具列表，省略则继承所有工具 |
| `disallowedTools` | 否 | 要拒绝的工具 |
| `model` | 否 | `sonnet`、`opus`、`haiku` 或 `inherit`（默认） |
| `permissionMode` | 否 | `default` / `acceptEdits` / `dontAsk` / `bypassPermissions` / `plan` |
| `maxTurns` | 否 | 最大代理轮数 |
| `skills` | 否 | 启动时预加载的 Skills |
| `mcpServers` | 否 | 可用的 MCP servers |
| `hooks` | 否 | 限定于此 subagent 的生命周期 hooks |
| `memory` | 否 | 持久内存范围：`user` / `project` / `local` |
| `background` | 否 | `true` = 始终后台运行（默认 `false`） |
| `isolation` | 否 | `worktree` = 在临时 git worktree 中运行 |

### 7.6 工具控制

**允许列表：**

```yaml
tools: Read, Grep, Glob, Bash
```

**拒绝列表：**

```yaml
disallowedTools: Write, Edit
```

**限制可生成的 Subagent 类型：**

```yaml
tools: Agent(worker, researcher), Read, Bash
```

- `Agent`（不带括号）= 允许生成任何 subagent
- 省略 `Agent` = 无法生成任何 subagent
- Subagent 无法嵌套生成其他 subagent

**权限模式：**

| 模式 | 行为 |
|------|------|
| `default` | 标准权限检查与提示 |
| `acceptEdits` | 自动接受文件编辑 |
| `dontAsk` | 自动拒绝权限提示 |
| `bypassPermissions` | 跳过所有权限检查（⚠️ 谨慎使用） |
| `plan` | Plan mode（只读探索） |

### 7.7 前台与后台运行

- **前台**：阻塞主对话，权限提示传递给用户
- **后台**：并发运行，启动前预授权，运行后自动拒绝未批准的操作

操作方式：要求 "run this in the background" 或按 **Ctrl+B**。

设置 `CLAUDE_CODE_DISABLE_BACKGROUND_TASKS=1` 可禁用所有后台任务。

### 7.8 恢复 Subagent

```text
Continue that code review and now analyze the authorization logic
```

恢复的 subagent 保留完整的对话历史。转录存储在 `~/.claude/projects/{project}/{sessionId}/subagents/agent-{agentId}.jsonl`，根据 `cleanupPeriodDays` 设置清理（默认 30 天）。

### 7.9 自动压缩

Subagent 在约 95% 容量时自动压缩。可通过 `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE` 调整（如设为 `50` 更早触发）。

---

## 8. MCP Servers 配置

MCP (Model Context Protocol) 让 Claude Code 连接外部工具。

### 配置文件

`.mcp.json`（项目根目录，入版本控制）：

```json
{
  "mcpServers": {
    "slack": {
      "command": "npx",
      "args": ["-y", "@anthropic/mcp-server-slack"],
      "env": {
        "SLACK_BOT_TOKEN": "${SLACK_BOT_TOKEN}"
      }
    },
    "github": {
      "command": "npx",
      "args": ["-y", "@anthropic/mcp-server-github"],
      "env": {
        "GITHUB_TOKEN": "${GITHUB_TOKEN}"
      }
    }
  }
}
```

### Subagent 中使用 MCP

在 subagent frontmatter 中引用已配置的 MCP server：

```yaml
---
name: ticket-worker
description: Reads JIRA tickets and implements changes
mcpServers:
  - jira
---
```

或内联定义：

```yaml
mcpServers:
  custom-db:
    command: "node"
    args: ["./mcp-servers/db-server.js"]
```

---

## 9. Hooks 生命周期钩子

### 9.1 Subagent Frontmatter 中的 Hooks

仅在该 subagent 活动时运行：

```yaml
---
name: safe-coder
hooks:
  PreToolUse:
    - matcher: "Bash"
      hooks:
        - type: command
          command: "./scripts/validate-command.sh"
  PostToolUse:
    - matcher: "Edit|Write"
      hooks:
        - type: command
          command: "./scripts/run-linter.sh"
---
```

| 事件 | Matcher | 触发时机 |
|------|---------|---------|
| `PreToolUse` | Tool name | 工具执行前 |
| `PostToolUse` | Tool name | 工具执行后 |
| `Stop` | — | Subagent 完成时 |

### 9.2 项目级 Hooks（settings.json）

响应 subagent 生命周期事件：

```json
{
  "hooks": {
    "SubagentStart": [
      {
        "matcher": "db-agent",
        "hooks": [
          { "type": "command", "command": "./scripts/setup-db-connection.sh" }
        ]
      }
    ],
    "SubagentStop": [
      {
        "hooks": [
          { "type": "command", "command": "./scripts/cleanup.sh" }
        ]
      }
    ]
  }
}
```

### 9.3 Hook 退出代码

| 退出代码 | 行为 |
|---------|------|
| 0 | 继续执行 |
| 2 | 阻止操作（PreToolUse），stderr 消息反馈给 Claude |
| 其他 | 视为错误 |

### 9.4 验证脚本示例

`./scripts/validate-readonly-query.sh`：

```bash
#!/bin/bash
INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

if [ -z "$COMMAND" ]; then
  exit 0
fi

if echo "$COMMAND" | grep -iE '\b(INSERT|UPDATE|DELETE|DROP|CREATE|ALTER|TRUNCATE|REPLACE|MERGE)\b' > /dev/null; then
  echo "Blocked: Write operations not allowed. Use SELECT queries only." >&2
  exit 2
fi

exit 0
```

```bash
chmod +x ./scripts/validate-readonly-query.sh
```

---

## 10. 示例 Subagents

### 代码审查者（只读 + Memory）

```markdown
---
name: code-reviewer
description: Expert code review specialist. Proactively reviews code for quality, security, and maintainability. Use immediately after writing or modifying code.
tools: Read, Grep, Glob, Bash
model: sonnet
memory: project
skills:
  - api-conventions
---

You are a senior code reviewer ensuring high standards of code quality and security.

Before starting, check your agent memory for patterns and conventions you've seen before in this codebase.

When invoked:
1. Run git diff to see recent changes
2. Focus on modified files
3. Begin review immediately

Review checklist:
- Code is clear and readable
- Functions and variables are well-named
- No duplicated code
- Proper error handling
- No exposed secrets or API keys
- Input validation implemented
- Good test coverage
- Performance considerations addressed

Provide feedback organized by priority:
- Critical issues (must fix)
- Warnings (should fix)
- Suggestions (consider improving)

Include specific examples of how to fix issues.

After completing the review, update your agent memory with any new patterns, conventions, or recurring issues you discovered.
```

### 调试器

```markdown
---
name: debugger
description: Debugging specialist for errors, test failures, and unexpected behavior. Use proactively when encountering any issues.
tools: Read, Edit, Bash, Grep, Glob
memory: local
---

You are an expert debugger specializing in root cause analysis.

Check your memory for debugging patterns you've seen before in this project.

When invoked:
1. Capture error message and stack trace
2. Identify reproduction steps
3. Isolate the failure location
4. Implement minimal fix
5. Verify solution works

For each issue, provide:
- Root cause explanation
- Evidence supporting the diagnosis
- Specific code fix
- Testing approach
- Prevention recommendations

Focus on fixing the underlying issue, not the symptoms.

Save debugging insights and discovered codepaths to your agent memory.
```

### 数据科学家

```markdown
---
name: data-scientist
description: Data analysis expert for SQL queries, BigQuery operations, and data insights. Use proactively for data analysis tasks and queries.
tools: Bash, Read, Write
model: sonnet
---

You are a data scientist specializing in SQL and BigQuery analysis.

When invoked:
1. Understand the data analysis requirement
2. Write efficient SQL queries
3. Use BigQuery command line tools (bq) when appropriate
4. Analyze and summarize results
5. Present findings clearly

Always ensure queries are efficient and cost-effective.
```

### 数据库查询验证器（Hook 限制写操作）

```markdown
---
name: db-reader
description: Execute read-only database queries. Use when analyzing data or generating reports.
tools: Bash
hooks:
  PreToolUse:
    - matcher: "Bash"
      hooks:
        - type: command
          command: "./scripts/validate-readonly-query.sh"
---

You are a database analyst with read-only access. Execute SELECT queries to answer questions about the data.

You cannot modify data. If asked to INSERT, UPDATE, DELETE, or modify schema, explain that you only have read access.
```

---

## 11. 团队协作最佳实践

### 版本控制策略

**入版本控制（团队共享）：**

- `CLAUDE.md`（项目根目录）
- `.claude/settings.json`
- `.claude/agents/*.md`
- `.claude/skills/*/SKILL.md`
- `.claude/rules/*.md`
- `.claude/agent-memory/`（项目级 subagent memory）
- `.mcp.json`
- `scripts/`（hook 脚本）

**不入版本控制（个人本地）：**

- `~/.claude/CLAUDE.md`
- `~/.claude/agents/`
- `~/.claude/skills/`
- `.claude/settings.local.json`
- `.claude/agent-memory-local/`

### CLAUDE.md 变更流程

像对待关键配置文件一样对待 CLAUDE.md 的修改，使用专门的 PR 进行 review。

### 设计原则

- **每个 subagent 专注一件事** — 不要创建"万能"subagent
- **描述要详尽且推动性** — Claude 根据 description 决定何时委托
- **最小工具权限** — 只给 subagent 完成任务所需的权限
- **善用 memory** — 让 subagent 积累领域知识，越用越聪明
- **善用 skills** — 将可重用的规范抽取为 skill，在多个 subagent 间共享
- **定期审查** — 定期运行 `/memory` 和 `/agents` 检查配置状态

---

## 相关资源

- [Skills 文档](https://code.claude.com/docs/zh-CN/skills)
- [Memory 文档](https://code.claude.com/docs/en/memory)
- [Subagents 文档](https://code.claude.com/docs/zh-CN/sub-agents)
- [Hooks 文档](https://code.claude.com/docs/zh-CN/hooks)
- [Permissions 文档](https://code.claude.com/docs/zh-CN/permissions)
- [MCP Servers 文档](https://code.claude.com/docs/zh-CN/mcp)
- [Plugins 文档](https://code.claude.com/docs/zh-CN/plugins)
- [Agent Teams 文档](https://code.claude.com/docs/zh-CN/agent-teams)
- [Headless Mode 文档](https://code.claude.com/docs/zh-CN/headless)
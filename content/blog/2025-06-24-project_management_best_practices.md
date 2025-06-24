+++
title = 'GitHub私有仓库协同开发指南'
date = 2024-10-16T02:04:51+08:00
draft = false
tags = ["project management"]
+++
## 目录
1. [简介](#简介)
2. [仓库结构和分支策略](#仓库结构和分支策略)
3. [协作者权限管理](#协作者权限管理)
4. [保护主分支](#保护主分支)
5. [Pull Request 和代码审查流程](#pull-request-和代码审查流程)
6. [持续集成与部署 (CI/CD)](#持续集成与部署-cicd)
7. [文档和沟通](#文档和沟通)
8. [最佳实践和注意事项](#最佳实践和注意事项)

## 简介
在没有高级 GitHub 功能的私有仓库中进行协同开发可能具有挑战性，但通过正确的实践和工具，我们可以建立一个高效、安全的开发环境。本指南总结了我们讨论的主要策略和技术。

## 仓库结构和分支策略
- **主分支**：`main`（稳定、可部署的代码）
- **开发分支**：`main_for_dev`（日常开发工作）
- **特性分支**：从 `main_for_dev` 分出，用于开发新功能

工作流程：
1. 从 `main_for_dev` 创建特性分支
2. 在特性分支上开发
3. 完成后，创建 Pull Request 到 `main_for_dev`
4. 代码审查和测试
5. 合并到 `main_for_dev`
6. 定期将 `main_for_dev` 合并到 `main`

## 协作者权限管理
GitHub 私有仓库提供以下权限级别：
- Read
- Triage
- Write
- Maintain
- Admin

设置步骤：
1. 进入仓库 "Settings" > "Collaborators and teams"
2. 点击 "Add people" 或 "Add teams"
3. 输入用户名并选择适当的权限级别

最佳实践：
- 遵循最小权限原则
- 定期审查和更新权限

## 保护主分支
由于缺乏高级分支保护功能，我们采用以下策略：

1. **团队约定**：
   - 禁止直接推送到 `main` 分支
   - 所有更改通过 PR 进行

2. **Git Hooks**：
   创建 pre-push hook（`.git/hooks/pre-push`）：

   ```bash
   #!/bin/sh
   branch=$(git rev-parse --abbrev-ref HEAD)
   if [ "$branch" = "main" ]; then
     echo "Direct push to main branch is not allowed. Please create a Pull Request."
     exit 1
   fi
   ```

   设置权限：`chmod +x .git/hooks/pre-push`

3. **GitHub Actions**：
   创建 `.github/workflows/protect-main.yml`：

   ```yaml
   name: Protect Main Branch
   on:
     push:
       branches:
         - main
   jobs:
     check_push:
       runs-on: ubuntu-latest
       steps:
         - uses: actions/checkout@v2
         - name: Check if push was direct
           run: |
             if [[ $(git log --format=%B -n 1 ${{ github.sha }}) != *"Merge pull request"* ]]; then
               echo "::error::Direct push to main branch detected. Please use Pull Requests."
               exit 1
             fi
   ```

## Pull Request 和代码审查流程
1. **创建 PR 模板**：
   在 `.github/pull_request_template.md` 中定义模板。

2. **审查流程**：
   - 至少一名审查者批准
   - 通过所有自动化测试
   - 遵循团队定义的代码规范

3. **合并策略**：
   使用 "Squash and merge" 或 "Rebase and merge" 保持清晰的提交历史。

## 持续集成与部署 (CI/CD)
使用 GitHub Actions 进行 CI/CD：

1. 在 PR 中运行测试和代码质量检查
2. 只从 `main` 分支进行部署
3. 自动化版本标记和发布流程

## 文档和沟通
1. **README.md**：项目概述和快速开始指南
2. **CONTRIBUTING.md**：详细的贡献指南
3. **代码注释**：保持代码自文档化
4. **定期团队会议**：讨论项目进展和问题

## 最佳实践和注意事项
1. 定期培训团队成员，确保everyone遵循协作流程
2. 使用 GitHub Issues 进行任务跟踪和 bug 报告
3. 考虑使用项目看板（Project Boards）进行任务管理
4. 定期审查和更新工作流程，适应团队需求
5. 鼓励知识共享和对等编程
6. 重视代码质量，包括单元测试和文档
7. 考虑实施持续反馈机制，不断改进协作流程

通过实施这些策略和最佳实践，即使在私有仓库的限制下，也能建立一个高效、安全的协作环境。记住，成功的协作不仅依赖于工具和流程，更依赖于团队的沟通和相互信任。
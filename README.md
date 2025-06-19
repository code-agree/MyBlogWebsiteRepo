# MyBlogWebsiteRepo

## 项目结构
- `/WebsiteRepo`: 包含Hugo博客网站的源文件
- `/.github/workflows`: 包含GitHub Actions工作流配置

## 重要提示

### 正确的提交和推送流程
1. **始终在主目录进行Git操作**
   ```bash
   cd /Users/yuwenjun/git_repo/MyBlogWebsiteRepo
   # 而不是 cd /Users/yuwenjun/git_repo/MyBlogWebsiteRepo/WebsiteRepo
   ```

2. **添加和提交更改**
   ```bash
   git add .
   git commit -m "你的提交信息"
   git push origin main
   ```

3. **注意事项**
   - 不要在`WebsiteRepo`子目录中执行Git命令
   - 确保YAML文件（如`.github/workflows/gh-pages.yml`）格式正确，不包含多余空格
   - 所有提交应该在主目录进行，以确保GitHub Actions正确触发

### GitHub Actions自动部署
- 每次推送到`main`分支时，GitHub Actions会自动构建并部署网站
- 部署目标: `code-agree/code-agree.github.io`
- 确保`ACTIONS_DEPLOY_KEY`密钥已正确配置

## 本地开发
```bash
cd WebsiteRepo
hugo server -D  # 启动本地开发服务器，包含草稿
```

## 创建新文章
```bash
cd WebsiteRepo
hugo new Blog/YYYY-MM-DD-title.md
```
# MyBlogWebsiteRepo

这是一个使用Hugo构建的个人博客网站仓库。

## 项目结构

- `/archetypes`: Hugo内容模板
- `/assets`: 网站资源文件
- `/config`: Hugo配置文件
- `/content`: 博客内容
- `/layouts`: 布局模板
- `/static`: 静态文件
- `/themes`: 主题文件（使用Congo主题）
- `/.github/workflows`: GitHub Actions工作流配置

## 使用方法

### 快速命令

项目提供了一个简单的脚本来管理博客操作：

```bash
# 创建新文章
./blog.sh new Blog/YYYY-MM-DD-title.md

# 本地预览网站
./blog.sh preview

# 提交并发布更改
./blog.sh publish "提交信息"
```

### 手动操作

#### 创建新文章

```bash
hugo new content/Blog/YYYY-MM-DD-title.md
```

#### 本地预览

```bash
hugo server -D  # 包含草稿
```

#### 提交和部署

```bash
git add .
git commit -m "你的提交信息"
git push origin main
```

## GitHub Actions自动部署

每次推送到`main`分支时，GitHub Actions会自动构建并部署网站：

1. 检出代码和子模块
2. 设置Node.js和Hugo环境
3. 构建网站
4. 部署到`code-agree/code-agree.github.io`仓库

## 注意事项

- 确保YAML文件（如`.github/workflows/gh-pages.yml`）格式正确，不包含多余空格
- 确保`ACTIONS_DEPLOY_KEY`密钥已正确配置
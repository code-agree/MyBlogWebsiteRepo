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

## 在文章中引用其他文章

在博客文章中，你可以使用Hugo的内置shortcode `ref` 或 `relref` 来引用其他文章。这比直接使用Markdown链接更可靠，因为即使文章路径或URL结构发生变化，链接也不会失效。

### 基本用法

```markdown
<!-- 基本引用，生成指向目标文章的链接 -->
{{< ref "文章路径" >}}

<!-- 带文本的链接 -->
[链接文本]({{< ref "文章路径" >}})

<!-- 例如引用memory_order文章 -->
[查看内存序详情]({{< ref "2025-06-24-memory_ordering_in_cpp" >}})
```

### 高级用法

```markdown
<!-- 跨语言引用 -->
{{< ref path="文章路径" lang="zh" >}}

<!-- 引用特定标题 -->
{{< ref "文章路径#标题ID" >}}

<!-- 引用其他部分的内容 -->
{{< ref "blog/other-post" >}}
```

### 路径说明

- 如果引用同一目录下的文章，直接使用文件名（不含扩展名）
- 如果引用其他目录的文章，使用相对路径，如 `blog/article-name`
- 不需要包含文件扩展名（.md）

## 注意事项

- 确保YAML文件（如`.github/workflows/gh-pages.yml`）格式正确，不包含多余空格
- 确保`ACTIONS_DEPLOY_KEY`密钥已正确配置
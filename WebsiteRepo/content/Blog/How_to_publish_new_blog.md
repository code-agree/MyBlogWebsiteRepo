+++
title = 'How to publish new blog'
date = 2024-09-02T12:36:27+08:00
draft = false
+++

### workflow
目前已经实现GitHub Action，自动编译静态文件, Push到GitHub Page。

### 具体流程
1. 在仓库 `git@github.com:code-agree/MyBlogWebsiteRepo.git`  MyBlogWebsiteRepo/WebsiteRepo 使用
hugo命令 `hugo new content ./content/blog/How_to_publish_new_blog.md` 新增blog
2. 将当前仓库的变更push到远端
3. 由配置的GitHub action 自动触发 构建静态文件->push到GitHub Page仓库
4. 成功发布

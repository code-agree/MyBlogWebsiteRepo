#!/bin/bash

# blog.sh - 博客管理脚本
# 用法: ./blog.sh [命令] [参数]

case "$1" in
  new)
    # 创建新文章
    if [ -z "$2" ]; then
      echo "请提供文章路径，例如: ./blog.sh new Blog/2023-01-01-title.md"
      exit 1
    fi
    hugo new content/$2
    echo "文章已创建: content/$2"
    ;;
    
  preview)
    # 本地预览
    hugo server -D
    ;;
    
  publish)
    # 提交并发布
    if [ -z "$2" ]; then
      echo "请提供提交信息，例如: ./blog.sh publish \"添加新文章\""
      exit 1
    fi
    git add .
    git commit -m "$2"
    git push origin main
    echo "更改已提交并推送到GitHub。GitHub Actions将自动构建并部署您的网站。"
    ;;
    
  *)
    # 帮助信息
    echo "博客管理脚本"
    echo "用法:"
    echo "  ./blog.sh new [文章路径]    - 创建新文章"
    echo "  ./blog.sh preview          - 本地预览网站"
    echo "  ./blog.sh publish \"消息\"   - 提交并发布更改"
    ;;
esac

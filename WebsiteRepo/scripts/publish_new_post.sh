#!/bin/bash

# 获取当前日期
DATE=$(date +"%Y-%m-%d")

# 检查参数
if [ $# -eq 0 ]; then
    echo "请提供文章名称"
    echo "用法: ./new-post.sh 文章名称"
    exit 1
fi

# 提取文件名（移除路径部分）
FILENAME=$(basename "$1" .md)

# 创建带日期前缀的文件路径
NEW_PATH="./content/blog/${DATE}-${FILENAME}.md"

# 调用Hugo创建文章
hugo new content "$NEW_PATH"

echo "created: $NEW_PATH"
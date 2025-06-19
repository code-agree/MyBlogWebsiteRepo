#!/bin/bash

# blog.sh - Blog Management Script
# Usage: ./blog.sh [command] [arguments]

case "$1" in
  new)
    # Create new article
    if [ -z "$2" ]; then
      echo "Please provide article path, e.g.: ./blog.sh new Blog/2023-01-01-title.md"
      exit 1
    fi
    hugo new content/$2
    echo "Article created: content/$2"
    ;;
    
  preview)
    # Local preview
    hugo server -D
    ;;
    
  publish)
    # Commit and publish
    if [ -z "$2" ]; then
      echo "Please provide commit message, e.g.: ./blog.sh publish \"Add new article\""
      exit 1
    fi
    git add .
    git commit -m "$2"
    git push origin main
    echo "Changes committed and pushed to GitHub. GitHub Actions will automatically build and deploy your site."
    ;;
    
  *)
    # Help information
    echo "Blog Management Script"
    echo "Usage:"
    echo "  ./blog.sh new [article_path]  - Create new article"
    echo "  ./blog.sh preview             - Preview site locally"
    echo "  ./blog.sh publish \"message\"   - Commit and publish changes"
    ;;
esac

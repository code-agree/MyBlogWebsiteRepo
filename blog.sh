#!/bin/bash

# blog.sh - Blog Management Script
# Usage: ./blog.sh [command] [arguments]

case "$1" in
  new)
    # Create new article
    if [ -z "$2" ]; then
      echo "Please provide article title, e.g.: ./blog.sh new my-new-post"
      exit 1
    fi
    
    # Generate filename with current date and time (hour level)
    DATE_PREFIX=$(date +"%Y-%m-%d")
    FILENAME="${DATE_PREFIX}-$2.md"
    
    # Create the article in the correct directory (blog, lowercase)
    hugo new content/blog/$FILENAME
    echo "Article created: content/blog/$FILENAME"
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
    echo "  ./blog.sh new [title]         - Create new article with auto-generated timestamp"
    echo "  ./blog.sh preview             - Preview site locally"
    echo "  ./blog.sh publish \"message\"   - Commit and publish changes"
    ;;
esac

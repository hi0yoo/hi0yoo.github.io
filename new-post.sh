#!/usr/bin/env bash

TITLE=$1
CATEGORY_PATH=$2

if [ -z "$TITLE" ] || [ -z "$CATEGORY_PATH" ]; then
  echo "❌ Usage: ./new-post.sh <title> <category-path>"
  echo "   Example: ./new-post.sh hello-world dev/blog"
  exit 1
fi

DATE=$(date +%Y-%m-%d)
POST_DIR="_posts/$CATEGORY_PATH"
FILENAME="${POST_DIR}/${DATE}-${TITLE}.md"

# 디렉토리 자동 생성
mkdir -p "$POST_DIR"

# 카테고리 경로를 슬래시(/) 기준으로 분할해서 배열로 만듦
IFS='/' read -r -a CATEGORIES <<< "$CATEGORY_PATH"

# 카테고리 YAML 포맷 만들기
CATEGORY_YAML=""
for category in "${CATEGORIES[@]}"; do
  CATEGORY_YAML+="  - $category"$'\n'
done

# YAML 파일 생성
{
  echo "---"
  echo "title: $TITLE"
  echo "author: hi0yoo"
  echo "date: $(date "+%Y-%m-%d %H:%M:%S %z")"
  echo "categories:"
  printf "%s" "$CATEGORY_YAML"
  echo "tags:"
  echo "  -"
  echo "render_with_liquid: false"
  echo "---"
} > "$FILENAME"

echo "✅ Created $FILENAME"

#!/bin/bash
# Notion API パターン集（curl）
# 使用方法: このファイルはリファレンスとして読み取る。直接実行しない。
# 前提: 環境変数 NOTION_TOKEN が設定済みであること

NOTION_API="https://api.notion.com/v1"
NOTION_VERSION="2022-06-28"

# 共通ヘッダー
# -H "Authorization: Bearer $NOTION_TOKEN"
# -H "Content-Type: application/json"
# -H "Notion-Version: $NOTION_VERSION"

# --- 1. StorageDB から未処理アイテムを取得 ---

curl -s -X POST "$NOTION_API/databases/49998bb8988d44b083e816f939d9d018/query" \
  -H "Authorization: Bearer $NOTION_TOKEN" \
  -H "Content-Type: application/json" \
  -H "Notion-Version: $NOTION_VERSION" \
  -d '{
  "filter": {
    "property": "Status",
    "select": {
      "equals": "未処理"
    }
  },
  "page_size": 10
}'

# --- 2. StorageDB の分析結果を更新（最重要パターン） ---

PAGE_ID="xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"

curl -s -X PATCH "$NOTION_API/pages/$PAGE_ID" \
  -H "Authorization: Bearer $NOTION_TOKEN" \
  -H "Content-Type: application/json" \
  -H "Notion-Version: $NOTION_VERSION" \
  -d '{
  "properties": {
    "Category": {
      "select": {"name": "AI・機械学習"}
    },
    "SubCategory": {
      "multi_select": [
        {"name": "Agent"},
        {"name": "LLM"}
      ]
    },
    "Tags": {
      "multi_select": [
        {"name": "技術解説"},
        {"name": "日本"}
      ]
    },
    "Companies": {
      "multi_select": [
        {"name": "OpenAI"},
        {"name": "Anthropic"}
      ]
    },
    "Relevance": {
      "select": {"name": "高"}
    },
    "Summary": {
      "rich_text": [{"text": {"content": "[概要] ... [主要内容] ... [意義・影響] ..."}}]
    },
    "KeyPoints": {
      "rich_text": [{"text": {"content": "• ポイント1\n• ポイント2\n• ポイント3"}}]
    },
    "OriginalDate": {
      "date": {"start": "2026-02-15"}
    },
    "Status": {
      "select": {"name": "完了"}
    },
    "ProcessedAt": {
      "date": {"start": "'"$(date -u +%Y-%m-%d)"'"}
    }
  }
}'

# --- 3. ページの内容（ブロック）を追加 ---

curl -s -X PATCH "$NOTION_API/blocks/$PAGE_ID/children" \
  -H "Authorization: Bearer $NOTION_TOKEN" \
  -H "Content-Type: application/json" \
  -H "Notion-Version: $NOTION_VERSION" \
  -d '{
  "children": [
    {
      "object": "block",
      "type": "heading_2",
      "heading_2": {
        "rich_text": [{"type": "text", "text": {"content": "要約"}}]
      }
    },
    {
      "object": "block",
      "type": "paragraph",
      "paragraph": {
        "rich_text": [{"type": "text", "text": {"content": "要約テキストをここに"}}]
      }
    }
  ]
}'

# --- 4. ページを取得 ---

curl -s "$NOTION_API/pages/$PAGE_ID" \
  -H "Authorization: Bearer $NOTION_TOKEN" \
  -H "Notion-Version: $NOTION_VERSION"

# --- 5. レスポンスの HTTP ステータスコード取得パターン ---

RESPONSE=$(curl -s -w "\n%{http_code}" -X PATCH "$NOTION_API/pages/$PAGE_ID" \
  -H "Authorization: Bearer $NOTION_TOKEN" \
  -H "Content-Type: application/json" \
  -H "Notion-Version: $NOTION_VERSION" \
  -d '{ ... }')

HTTP_CODE=$(echo "$RESPONSE" | tail -1)
BODY=$(echo "$RESPONSE" | sed '$d')

if [ "$HTTP_CODE" = "200" ]; then
  echo "成功"
  echo "$BODY" | python3 -c "import sys, json; data=json.load(sys.stdin); print(data['id'])"
else
  echo "エラー: HTTP $HTTP_CODE"
  echo "$BODY" | python3 -m json.tool
fi

# --- 6. rich_text の 2000文字制限への対応 ---
# Notion の rich_text は1ブロックあたり2000文字制限がある。
# 長いテキストは複数の rich_text オブジェクトに分割する。
#
# "Summary": {
#   "rich_text": [
#     {"text": {"content": "最初の2000文字..."}},
#     {"text": {"content": "次の2000文字..."}}
#   ]
# }

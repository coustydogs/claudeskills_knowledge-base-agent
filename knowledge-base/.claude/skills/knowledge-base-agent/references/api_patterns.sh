#!/bin/bash
# Notion API パターン集（プラグインモード / MCP+curlモード 両対応）
# 使用方法: このファイルはリファレンスとして読み取る。直接実行しない。

# ============================================================
# プラグインモード（iOS/macOS共通、推奨）
# ============================================================
# Notionマーケットプレイスプラグインのツールを使用。
# 認証はプラグインが管理するため、NOTION_TOKEN は不要。

# --- 1. StorageDB から未処理アイテムを検索 ---
# notion-search:
#   query: "未処理"
#   data_source_url: "collection://48887d97-0f04-4c52-9f44-0b77fd8cf4f1"
#
# 検索結果の各ページを notion-fetch で Status を確認:
# notion-fetch:
#   id: "{page_id}"

# --- 2. ページのプロパティを更新（分析結果の書き込み） ---
# notion-update-page:
#   data:
#     page_id: "ページID"
#     command: "update_properties"
#     properties:
#       Category: "AI・機械学習"
#       SubCategory: ["Agent", "LLM"]
#       Tags: ["技術解説", "日本"]
#       Companies: ["OpenAI", "Anthropic"]
#       Relevance: "高"
#       Summary: "要約テキスト"
#       KeyPoints: "• ポイント1\n• ポイント2"
#       Status: "完了"
#       date:OriginalDate:start: "2026-02-15"
#       date:OriginalDate:is_datetime: 0
#       date:ProcessedAt:start: "2026-02-21"
#       date:ProcessedAt:is_datetime: 0

# --- 3. ページコンテンツに追記 ---
# notion-update-page:
#   data:
#     page_id: "ページID"
#     command: "insert_content_after"
#     selection_with_ellipsis: "最後のコンテンツ...の末尾"
#     new_str: |
#       ## 要約
#       要約テキストをここに

# --- 4. ページ情報を取得 ---
# notion-fetch:
#   id: "ページID"

# --- 5. データベース内を検索 ---
# notion-search:
#   query: "検索キーワード"
#   data_source_url: "collection://48887d97-0f04-4c52-9f44-0b77fd8cf4f1"

# ============================================================
# MCP+curlモード（macOSのみ、フォールバック）
# ============================================================
# 前提: 環境変数 NOTION_TOKEN が設定済みであること

NOTION_API="https://api.notion.com/v1"
NOTION_VERSION="2022-06-28"

# 共通ヘッダー
# -H "Authorization: Bearer $NOTION_TOKEN"
# -H "Content-Type: application/json"
# -H "Notion-Version: $NOTION_VERSION"

# --- 1. StorageDB から未処理アイテムを取得 ---
# MCP の API-query-data-source でも可（filter パラメータは型定義済みで動作する）

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
# MCP の API-patch-page でも可（properties パラメータは型定義済みで動作する）

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
# MCP の API-patch-block-children でも可

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

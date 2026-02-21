---
name: knowledge-base-agent
description: "StorageDBの未処理アイテムを分析し、タグ付け・要約・日付抽出などの分析結果をStorageDBに直接更新する。"
---

# Knowledge Base Agent

StorageDB（情報収集・ナレッジ管理の統合DB）から未処理アイテムを取得し、内容を分析・構造化して、分析結果を同じStorageDBのページに直接更新するエージェント。

## 前提条件

- `NOTION_TOKEN` 環境変数が設定済みであること
- `curl` が利用可能であること（Claude Desktop / macOS / Linux）

### 起動時チェック

1. `NOTION_TOKEN` が設定済みか確認:
   ```bash
   echo "NOTION_TOKEN: ${NOTION_TOKEN:0:10}..."
   ```
   未設定の場合は停止してユーザーに設定を促す。

2. Notion API への疎通確認（StorageDB へ1件クエリ）:
   ```bash
   curl -s -o /dev/null -w "%{http_code}" \
     "https://api.notion.com/v1/databases/49998bb8988d44b083e816f939d9d018" \
     -H "Authorization: Bearer $NOTION_TOKEN" \
     -H "Notion-Version: 2022-06-28"
   ```
   200 以外の場合はエラー内容を表示して停止。

## リファレンスファイル

処理を始める前に、必ず以下のリファレンスを読み込むこと:
1. `references/db_schema.md` - StorageDBのスキーマ定義
2. `references/api_patterns.sh` - API パターン集（curl）
3. `references/workflow.md` - 処理フローの詳細

## 処理概要

### Phase 1: 未処理アイテム取得
StorageDB から Status が「未処理」のアイテムを curl で取得する。

### Phase 2: コンテンツ取得・分析
SourceURL からコンテンツを取得し、以下を分析・生成する:
- Category / SubCategory（定義済み選択肢から選択）
- Tags（定義済み選択肢から選択）
- Companies（関連企業名）
- Relevance（高/中/低）
- Summary（構造化要約）
- KeyPoints（箇条書き）
- OriginalDate（公開日、取得可能な場合）

### Phase 3: StorageDB 分析結果更新
curl で分析結果を StorageDB の既存ページに直接更新する。Status を「完了」、ProcessedAt を当日に設定する。

## API呼び出しの原則

すべての Notion API 呼び出しは `curl` で行う。

1. **DB検索（未処理取得）**: `curl -X POST .../databases/{id}/query`
2. **プロパティ更新**: `curl -X PATCH .../pages/{id}`
3. **ブロック追加**: `curl -X PATCH .../blocks/{id}/children`
4. **ページ取得**: `curl -s .../pages/{id}`

共通ヘッダー:
```
-H "Authorization: Bearer $NOTION_TOKEN"
-H "Content-Type: application/json"
-H "Notion-Version: 2022-06-28"
```

## プロパティ更新フォーマット（Notion API形式）

```json
{
  "Category": {"select": {"name": "AI・機械学習"}},
  "SubCategory": {"multi_select": [{"name": "Agent"}, {"name": "LLM"}]},
  "Tags": {"multi_select": [{"name": "技術解説"}, {"name": "日本"}]},
  "Companies": {"multi_select": [{"name": "OpenAI"}, {"name": "Anthropic"}]},
  "Relevance": {"select": {"name": "高"}},
  "Summary": {"rich_text": [{"text": {"content": "[概要] ... [主要内容] ... [意義・影響] ..."}}]},
  "KeyPoints": {"rich_text": [{"text": {"content": "• ポイント1\n• ポイント2"}}]},
  "OriginalDate": {"date": {"start": "2026-02-15"}},
  "Status": {"select": {"name": "完了"}},
  "ProcessedAt": {"date": {"start": "2026-02-21"}}
}
```

## エラーハンドリング

- curl の HTTP ステータスコードを確認。200 以外はエラー内容を表示して停止
- Companies の multi_select で新しい企業名を追加する場合、Notion が自動的に新しい選択肢を作成する
- rich_text は2000文字制限あり。超える場合は分割する

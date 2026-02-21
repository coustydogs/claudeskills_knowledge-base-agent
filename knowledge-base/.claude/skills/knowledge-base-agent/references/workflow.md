# 処理フロー詳細

## 起動時チェック

### ステップ1: NOTION_TOKEN 確認

```bash
echo "NOTION_TOKEN: ${NOTION_TOKEN:0:10}..."
```

未設定の場合は停止してユーザーに設定を促す:
> `NOTION_TOKEN` が設定されていません。`~/.zshrc` または Claude Desktop の設定ファイルに `NOTION_TOKEN=secret_xxx...` を追加してください。

### ステップ2: リファレンスファイルの読み込み

`db_schema.md` と `api_patterns.sh` を読み込む。

### ステップ3: StorageDB への接続テスト（1件クエリ）

```bash
RESPONSE=$(curl -s -w "\n%{http_code}" \
  "https://api.notion.com/v1/databases/49998bb8988d44b083e816f939d9d018" \
  -H "Authorization: Bearer $NOTION_TOKEN" \
  -H "Notion-Version: 2022-06-28")

HTTP_CODE=$(echo "$RESPONSE" | tail -1)
if [ "$HTTP_CODE" != "200" ]; then
  echo "接続エラー: HTTP $HTTP_CODE"
  echo "$RESPONSE" | sed '$d'
fi
```

200 以外の場合はエラーを表示して停止。

## Phase 1: 未処理アイテム取得

### 手順
1. StorageDB を Status = 「未処理」でフィルタしてクエリ
2. 取得したアイテムのリストを表示
3. ユーザーに処理対象を確認（全件 or 選択）

```bash
curl -s -X POST "https://api.notion.com/v1/databases/49998bb8988d44b083e816f939d9d018/query" \
  -H "Authorization: Bearer $NOTION_TOKEN" \
  -H "Content-Type: application/json" \
  -H "Notion-Version: 2022-06-28" \
  -d '{
  "filter": {
    "property": "Status",
    "select": {
      "equals": "未処理"
    }
  },
  "page_size": 10
}'
```

## Phase 2: コンテンツ取得・分析

### 手順
1. SourceURL からコンテンツを取得
   - Web記事: `WebFetch` ツールで取得
   - YouTube: URLからメタデータ取得（トランスクリプトは取れない場合あり）
   - テキスト: StorageDB の RawContent から取得
2. コンテンツを分析して以下を生成:

### 分析項目

| 項目 | 生成方法 |
|------|---------|
| Category | 定義済み7カテゴリから最適なものを1つ選択 |
| SubCategory | 定義済みリストから該当するものを複数選択 |
| Tags | 定義済みリストから該当するものを複数選択 |
| Companies | 記事に登場する企業名を抽出（新規追加可） |
| Relevance | ユーザーの関心分野との関連度を 高/中/低 で判定 |
| Summary | 構造化要約フォーマットに従って生成 |
| KeyPoints | 3-5個の要点を箇条書きで生成 |
| OriginalDate | 元記事の公開日（取得可能な場合） |

### ユーザーの関心分野（Relevance 判定基準）
- 世界・日本の経済/ビジネス動向
- 生成AIと最先端技術のビジネス活用事例
- 半導体・GPU・エネルギーなどAI関連技術・資源

### 分析結果の確認
分析結果をユーザーに提示し、修正があれば反映してから次フェーズへ進む。

## Phase 3: StorageDB 分析結果更新

curl で PATCH リクエストを送信:

```bash
PAGE_ID="xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
TODAY=$(date -u +%Y-%m-%d)

curl -s -w "\n%{http_code}" -X PATCH "https://api.notion.com/v1/pages/$PAGE_ID" \
  -H "Authorization: Bearer $NOTION_TOKEN" \
  -H "Content-Type: application/json" \
  -H "Notion-Version: 2022-06-28" \
  -d '{
  "properties": {
    "Category": {"select": {"name": "AI・機械学習"}},
    "SubCategory": {"multi_select": [{"name": "Agent"}, {"name": "LLM"}]},
    "Tags": {"multi_select": [{"name": "技術解説"}, {"name": "日本"}]},
    "Companies": {"multi_select": [{"name": "OpenAI"}, {"name": "Anthropic"}]},
    "Relevance": {"select": {"name": "高"}},
    "Summary": {"rich_text": [{"text": {"content": "[概要] ... [主要内容] ... [意義・影響] ..."}}]},
    "KeyPoints": {"rich_text": [{"text": {"content": "• ポイント1\n• ポイント2\n• ポイント3"}}]},
    "OriginalDate": {"date": {"start": "2026-02-15"}},
    "Status": {"select": {"name": "完了"}},
    "ProcessedAt": {"date": {"start": "'"$TODAY"'"}}
  }
}'
```

### 注意事項
- multi_select は `[{"name": "値1"}, {"name": "値2"}]` 形式
- rich_text は2000文字制限あり。超える場合は分割
- ProcessedAt には処理実行日（当日）を設定
- Companies で DB に存在しない企業名を指定すると、自動的に新しい選択肢が作成される

## エラー時の対応

| エラー | 対応 |
|--------|------|
| 401 Unauthorized | NOTION_TOKEN の値を確認 |
| 404 Not Found | ページ/DB の ID を確認。インテグレーションの共有設定を確認 |
| 400 Validation Error | プロパティ名やフォーマットを確認 |
| rich_text 2000文字超 | テキストを分割して複数の rich_text オブジェクトに |
| SourceURL アクセス不可 | StorageDB の RawContent を代替ソースとして使用 |

## 処理完了後

処理結果のサマリーを表示:
```
処理完了:
  - StorageDB: [タイトル] → Status: 完了
  - Category: AI・機械学習
  - Tags: 技術解説, 日本
  - Relevance: 高
```

# 処理フロー詳細

## 起動時チェック

```
1. 利用可能なNotionツールを検出し、動作モードを決定
   - notion-fetch, notion-search, notion-update-page が使える → プラグインモード
   - API-query-data-source, API-patch-page が使える + NOTION_TOKEN あり → MCP+curlモード
2. リファレンスファイルの読み込み（db_schema.md, api_patterns.sh）
3. StorageDB への接続テスト（1件クエリ）
```

## Phase 1: 未処理アイテム取得

### 手順
1. StorageDB を Status = 「未処理」でフィルタしてクエリ
2. 取得したアイテムのリストを表示
3. ユーザーに処理対象を確認（全件 or 選択）

### プラグインモードの場合

1. `notion-search` で StorageDB データソース内を検索:
   - `query`: `"未処理"`
   - `data_source_url`: `collection://48887d97-0f04-4c52-9f44-0b77fd8cf4f1`
2. 検索結果の各ページを `notion-fetch` で取得し、Status プロパティが「未処理」であることを確認
3. Status が「未処理」でないページは除外

```
notion-search:
  query: "未処理"
  data_source_url: "collection://48887d97-0f04-4c52-9f44-0b77fd8cf4f1"

# 各結果に対して:
notion-fetch:
  id: "{page_id}"
# → Status プロパティを確認
```

### MCP+curlモードの場合

```bash
curl -s -X POST "https://api.notion.com/v1/databases/49998bb8988d44b083e816f939d9d018/query" \
  -H "Authorization: Bearer $NOTION_TOKEN" \
  -H "Content-Type: application/json" \
  -H "Notion-Version: 2022-06-28" \
  -d '{"filter":{"property":"Status","select":{"equals":"未処理"}},"page_size":10}'
```

または MCP `API-query-data-source`:
```
API-query-data-source:
  data_source_id: "48887d97-0f04-4c52-9f44-0b77fd8cf4f1"
  filter:
    property: "Status"
    select:
      equals: "未処理"
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

### プラグインモードの場合

`notion-update-page` の `update_properties` コマンドを使用:

```
notion-update-page:
  data:
    page_id: "ページID"
    command: "update_properties"
    properties:
      Category: "AI・機械学習"
      SubCategory: ["Agent", "LLM"]
      Tags: ["技術解説", "日本"]
      Companies: ["OpenAI", "Anthropic"]
      Relevance: "高"
      Summary: "要約テキスト"
      KeyPoints: "• ポイント1\n• ポイント2"
      Status: "完了"
      date:OriginalDate:start: "2026-02-15"
      date:OriginalDate:is_datetime: 0
      date:ProcessedAt:start: "2026-02-21"
      date:ProcessedAt:is_datetime: 0
```

### MCP+curlモードの場合

MCP `API-patch-page`:
```
API-patch-page:
  page_id: "ページID"
  properties:
    Category:
      select:
        name: "AI・機械学習"
    SubCategory:
      multi_select:
        - name: "Agent"
        - name: "LLM"
    Tags:
      multi_select:
        - name: "技術解説"
        - name: "日本"
    Companies:
      multi_select:
        - name: "OpenAI"
        - name: "Anthropic"
    Relevance:
      select:
        name: "高"
    Summary:
      rich_text:
        - text:
            content: "[概要] ... [主要内容] ... [意義・影響] ..."
    KeyPoints:
      rich_text:
        - text:
            content: "• ポイント1\n• ポイント2\n• ポイント3"
    OriginalDate:
      date:
        start: "2026-02-15"
    Status:
      select:
        name: "完了"
    ProcessedAt:
      date:
        start: "2026-02-21"
```

### 注意事項
- プラグインモード: multi_select は JSON配列で指定（例: `["Agent", "LLM"]`）
- MCP+curlモード: multi_select は `[{"name": "値1"}, {"name": "値2"}]` 形式
- rich_text は2000文字制限あり。超える場合は分割
- ProcessedAt には処理実行日（当日）を設定
- Companies で DB に存在しない企業名を指定すると、自動的に新しい選択肢が作成される

## エラー時の対応

| エラー | 対応 |
|--------|------|
| 401 Unauthorized | NOTION_TOKEN の値を確認（MCP+curlモード時） |
| 404 Not Found | ページ/DB の ID を確認。インテグレーションの共有設定を確認 |
| 400 Validation Error | プロパティ名やフォーマットを確認 |
| rich_text 2000文字超 | テキストを分割して複数の rich_text オブジェクトに |
| SourceURL アクセス不可 | StorageDB の RawContent を代替ソースとして使用 |
| プラグインツール未検出 | MCP+curlモードにフォールバック。NOTION_TOKEN の設定を確認 |

## 処理完了後

処理結果のサマリーを表示:
```
処理完了:
  - StorageDB: [タイトル] → Status: 完了
  - Category: AI・機械学習
  - Tags: 技術解説, 日本
  - Relevance: 高
```

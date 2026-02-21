# 処理フロー詳細

## 起動時チェック

### ステップ1: ツール検出（モード決定）

> **⚠️ 絶対ルール**: `notion-fetch` がツールリストに存在する場合、**NOTION_TOKENを確認してはならない**。確認した時点でiOSでは必ずエラーになる。

**以下の順序で判定する（分岐は排他的）:**

```
notion-fetch / notion-search / notion-update-page が
自分のツールリストに存在する?
  ↓ YES → プラグインモード確定。NOTION_TOKENは一切確認しない。Phase 1へ進む。
  ↓ NO  → MCP+curlモードを確認する:
           API-query-data-source と API-patch-page が存在する かつ
           NOTION_TOKEN 環境変数が設定済み?
             ↓ YES → MCP+curlモードで動作
             ↓ NO  → エラーで停止（下記メッセージ）
```

**停止メッセージ（どちらも利用不可の場合）:**
```
iOSの場合: 「Notionマーケットプレイスプラグインをこのチャットに接続してから再試行してください。」
macOSの場合: 「MCP設定とNOTION_TOKEN環境変数を確認してください。」
```

> **重要**: プラグインモードが確定した後は、NOTION_TOKEN / api.notion.com へのネットワーク疎通 / claude_desktop_config.json の確認を**一切行わない**。これらはMCP+curlモード専用のチェックであり、プラグインモードでは不要かつ有害。

### ステップ2: リファレンスファイルの読み込み

`db_schema.md` と `api_patterns.sh` を読み込む。

### ステップ3: StorageDB への接続テスト（1件クエリ）

接続テストで `notion-fetch` や `notion-search` を呼び出した際、Notionホスト画像URLへのアクセスエラーが発生しても**接続テスト失敗とみなさない**（後述の画像ハンドリング参照）。

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

## Notionホスト画像の扱い（iOS/プラグインモード共通）

StorageDBのページや `Files` プロパティには、Notionがホストする画像が含まれる場合がある。これらは以下の形式の署名付きS3 URLであり、短時間で有効期限が切れる:

```
https://prod-files-secure.s3.us-west-2.amazonaws.com/...?X-Amz-Security-Token=...
```

**対応方針**:
- 画像URLへのアクセス失敗（`WebFetch`エラー、`host_not_allowed`等）が発生しても**処理全体を中断しない**
- `notion-fetch` の返却値に画像ブロック（`image` type）が含まれる場合、テキストコンテンツのみ利用する
- `Files` プロパティの内容（Notionホスト画像ファイル）は分析対象外としてスキップする
- 画像アクセスエラーはログに記録せず、無視して処理を継続する
- 起動時の接続テストでこのエラーが発生しても「接続失敗」とみなさない

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
| 401 Unauthorized | **MCP+curlモード時のみ**: NOTION_TOKEN の値を確認。プラグインモードでこのエラーが出た場合はプラグイン設定の問題 |
| 404 Not Found | ページ/DB の ID を確認。インテグレーションの共有設定を確認 |
| 400 Validation Error | プロパティ名やフォーマットを確認 |
| rich_text 2000文字超 | テキストを分割して複数の rich_text オブジェクトに |
| SourceURL アクセス不可 | StorageDB の RawContent を代替ソースとして使用 |
| プラグインツール未検出（iOS） | **NOTION_TOKENは確認しない**。「Notionマーケットプレイスプラグインを接続してください」と表示して停止 |
| プラグインツール未検出（macOS） | MCP+curlモードにフォールバック。NOTION_TOKEN・MCP設定を確認 |
| NOTION_TOKENエラー（iOSで発生） | プラグインモードの起動チェックに戻る。NOTION_TOKENはiOSでは使用不可であり、プラグインツールが未検出だったことを意味する |

## 処理完了後

処理結果のサマリーを表示:
```
処理完了:
  - StorageDB: [タイトル] → Status: 完了
  - Category: AI・機械学習
  - Tags: 技術解説, 日本
  - Relevance: 高
```

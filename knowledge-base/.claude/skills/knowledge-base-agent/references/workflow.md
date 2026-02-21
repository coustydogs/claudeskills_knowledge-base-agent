# 処理フロー詳細

## 起動時チェック

```
1. NOTION_TOKEN の存在確認
2. リファレンスファイルの読み込み（db_schema.md, api_patterns.sh）
3. StorageDB への接続テスト（1件クエリ）
```

## Phase 1: 未処理アイテム取得

### 手順
1. StorageDB を Status = null（未処理）でフィルタしてクエリ
2. 取得したアイテムのリストを表示
3. ユーザーに処理対象を確認（全件 or 選択）

### 使用ツール
- **推奨**: `curl` で直接クエリ
- **代替**: MCP `API-query-data-source`（filter パラメータは動作する）

### クエリ例（curl）
```bash
curl -s -X POST "https://api.notion.com/v1/databases/49998bb8988d44b083e816f939d9d018/query" \
  -H "Authorization: Bearer $NOTION_TOKEN" \
  -H "Content-Type: application/json" \
  -H "Notion-Version: 2022-06-28" \
  -d '{"filter":{"property":"Status","select":{"is_empty":true}},"page_size":10}'
```

## Phase 2: コンテンツ取得・分析

### 手順
1. SourceURL からコンテンツを取得
   - Web記事: `WebFetch` ツールまたは `curl` で取得
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

### 手順
1. Phase 2 の分析結果から、StorageDB の既存ページのプロパティを更新
2. `API-patch-page`（MCP）または `curl` で `PATCH /v1/pages/{page_id}` を実行
3. レスポンスを確認して成功を記録

### 使用ツール
- **推奨**: MCP `API-patch-page`（properties パラメータは型定義済みで動作する）
- **代替**: `curl` で `PATCH /v1/pages/{page_id}`

### 更新するプロパティ
- Category, SubCategory, Tags, Companies, Relevance
- Summary, KeyPoints
- OriginalDate
- Status: 「完了」
- ProcessedAt: 当日日付

### MCP 使用時の例
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
        start: "2026-02-17"
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
| curl HTTP 000 / proxy 403 | ネットワークプロキシが api.notion.com をブロックしている。ローカルまたはMOBILE環境で実行すること |
| NOTION_TOKEN 未設定 | `export NOTION_TOKEN=ntn_xxxxx` で設定。GitHub Actions の場合はリポジトリの Secrets に登録 |

## 実行環境の要件

このスキルは以下の環境で正常動作する:

| 環境 | 状態 | 備考 |
|------|------|------|
| ローカル Mac/Linux | ✅ 推奨 | `export NOTION_TOKEN=...` で設定可能 |
| iOS Claude Code (モバイル) | ✅ 推奨 | ローカルリポジトリ接続時、NOTION_TOKEN が必要 |
| GitHub Actions / CI | ⚠️ 要設定 | NOTION_TOKEN を Secrets に登録 + api.notion.com のアクセス許可が必要 |
| Claude Code Web (リモート) | ❌ 非推奨 | ネットワークプロキシが api.notion.com・note.com をブロックするため動作しない |

### GitHub Actions で使う場合

```yaml
env:
  NOTION_TOKEN: ${{ secrets.NOTION_TOKEN }}
```

リポジトリの Settings → Secrets and variables → Actions に `NOTION_TOKEN` を登録すること。

## 処理完了後

処理結果のサマリーを表示:
```
処理完了:
  - StorageDB: [タイトル] → Status: 完了
  - Category: AI・機械学習
  - Tags: 技術解説, 日本
  - Relevance: 高
```

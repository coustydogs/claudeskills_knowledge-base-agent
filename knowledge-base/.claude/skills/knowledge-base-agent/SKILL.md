---
name: knowledge-base-agent
description: "StorageDBの未処理アイテムを分析し、タグ付け・要約・日付抽出などの分析結果をStorageDBに直接更新する。"
---

# Knowledge Base Agent

StorageDB（情報収集・ナレッジ管理の統合DB）から未処理アイテムを取得し、内容を分析・構造化して、分析結果を同じStorageDBのページに直接更新するエージェント。

## 前提条件

- Notion MCPプラグイン（マーケットプレイス版）が有効であること
- macOS / iOS のどちらでも動作する

### 起動時のツール検出

> **⚠️ iOS必読 — NOTION_TOKENは絶対に確認しない**
> iOSのClaude Codeでは、`NOTION_TOKEN` の存在確認・参照・チェックを**一切行わない**。
> `notion-fetch` / `notion-search` / `notion-update-page` がツールリストに存在する場合は**即座にプラグインモードで開始**し、それ以外のチェックはすべてスキップする。

起動時に**ツールリスト**を確認し、動作モードを決定する:

| モード | 条件 | 利用ツール |
|--------|------|------------|
| **プラグインモード**（iOS/macOS共通） | `notion-fetch`, `notion-search`, `notion-update-page` がツールリストに存在する | Notionマーケットプレイスプラグイン |
| **MCP+curlモード**（macOSのみ） | 上記が存在しない かつ `API-query-data-source`, `API-patch-page` が存在する かつ `NOTION_TOKEN` 環境変数あり | MCP標準ツール + curl |

**プラグインモードを最優先する。** プラグインツールがツールリストに存在した時点で確定し、NOTION_TOKEN・ネットワーク疎通・設定ファイルの確認は一切行わずにPhase 1へ進む。

### iOS での注意事項

iOSのClaude Codeでは以下の制約がある:

- `NOTION_TOKEN` 環境変数は利用不可
- `api.notion.com` へのネットワーク直接アクセスはブロックされる（MCP+curlモード不可）
- **→ Notionマーケットプレイスプラグインを接続することでプラグインモードが利用可能になる**

また、Notionがホストする画像（`Files` プロパティや埋め込み画像）のURLは署名付きS3 URLのため、iOSのClaude Codeコンテナ環境からアクセスできない場合がある。これらの画像はスキップして処理を継続する。

## リファレンスファイル

処理を始める前に、必ず以下のリファレンスを読み込むこと:
1. `references/db_schema.md` - StorageDBのスキーマ定義
2. `references/api_patterns.sh` - API パターン集（プラグイン/curl両対応）
3. `references/workflow.md` - 処理フローの詳細

## 処理概要

### Phase 1: 未処理アイテム取得
StorageDB から Status が「未処理」のアイテムを取得する。

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
分析結果を StorageDB の既存ページに直接更新する。Status を「完了」、ProcessedAt を当日に設定する。

## API呼び出しの原則

### プラグインモード（推奨）

1. **DB検索（未処理取得）**: `notion-search` で `data_source_url: collection://48887d97-0f04-4c52-9f44-0b77fd8cf4f1` を指定して「未処理」を検索。取得後、各ページを `notion-fetch` で Status プロパティを確認する。
2. **プロパティ更新**: `notion-update-page` の `update_properties` コマンドを使用。SQLite形式でプロパティ値を指定する。
3. **読み取り**: `notion-fetch` でページ/DBのコンテンツを取得
4. **コンテンツ編集**: `notion-update-page` の `insert_content_after` / `replace_content` コマンドを使用

### MCP+curlモード（フォールバック）

1. **DB検索**: `API-query-data-source` で構造化フィルタ、または `curl` で直接クエリ
2. **プロパティ更新**: `API-patch-page`（MCP）推奨。`curl` でも可。
3. **読み取り・検索**: MCP ツール（`notion-fetch`, `notion-search`, `API-query-data-source`）
4. **ブロック操作**: `API-patch-block-children`, `API-get-block-children`

## プロパティ更新フォーマット

### プラグインモード（SQLite形式）

```json
{
  "Category": "AI・機械学習",
  "SubCategory": ["Agent", "LLM"],
  "Tags": ["技術解説", "日本"],
  "Companies": ["OpenAI", "Anthropic"],
  "Relevance": "高",
  "Summary": "要約テキスト",
  "KeyPoints": "• ポイント1\n• ポイント2",
  "Status": "完了",
  "date:OriginalDate:start": "2026-02-15",
  "date:OriginalDate:is_datetime": 0,
  "date:ProcessedAt:start": "2026-02-21",
  "date:ProcessedAt:is_datetime": 0
}
```

### MCP+curlモード（Notion API形式）

```json
{
  "Category": {"select": {"name": "AI・機械学習"}},
  "Status": {"select": {"name": "完了"}},
  "ProcessedAt": {"date": {"start": "2026-02-21"}}
}
```

## MCP標準ツールの既知の問題

以下のパラメータは JSON Schema に `"type": "object"` が未宣言のため、文字列としてシリアライズされるバグがある（MCP+curlモード時のみ該当）:

| ツール | パラメータ | 状態 |
|--------|-----------|------|
| `API-post-page` | `parent` | ❌ 使用不可 |
| `API-move-page` | `parent` | ❌ 使用不可 |
| `API-patch-page` | `properties` | ✅ 正常（型定義あり） |
| `API-query-data-source` | `filter` | ✅ 正常（型定義あり） |

## エラーハンドリング

- プラグインモード: ツールのエラーメッセージを確認して対応
- MCP+curlモード: curl の HTTP ステータスコードを確認。200 以外はエラー内容を表示して停止
- Companies の multi_select で新しい企業名を追加する場合、Notion が自動的に新しい選択肢を作成する
- rich_text は2000文字制限あり。超える場合は分割する

| エラー | 対応 |
|--------|------|
| プラグインツール未検出（iOS） | **NOTION_TOKENは確認しない**。処理を停止して表示:「Notionマーケットプレイスプラグインを接続してから再試行してください」 |
| プラグインツール未検出（macOS） | MCP+curlモードにフォールバック。NOTION_TOKEN・MCP設定を確認 |
| NOTION_TOKENエラー | MCP+curlモード専用の問題。iOSでこのエラーが出た場合はプラグインツールが未検出のため、プラグインを接続すること |

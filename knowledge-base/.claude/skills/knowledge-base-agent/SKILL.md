---
name: knowledge-base-agent
description: "StorageDBの未処理アイテムを分析し、タグ付け・要約・日付抽出などの分析結果をStorageDBに直接更新する。"
---

# Knowledge Base Agent

StorageDB（情報収集・ナレッジ管理の統合DB）から未処理アイテムを取得し、内容を分析・構造化して、分析結果を同じStorageDBのページに直接更新するエージェント。

## 前提条件

- 環境変数 `NOTION_TOKEN` が設定されていること
- ローカル・iOS Claude Code（リモートリポジトリ接続）いずれでも動作する

起動時に必ず以下を確認:
```bash
echo "NOTION_TOKEN: ${NOTION_TOKEN:0:10}..."
```

トークンが未設定の場合、ユーザーに以下を案内:
```
export NOTION_TOKEN=ntn_xxxxx
```

## リファレンスファイル

処理を始める前に、必ず以下のリファレンスを読み込むこと:
1. `references/db_schema.md` - StorageDBのスキーマ定義
2. `references/api_patterns.sh` - Notion API の curl パターン集
3. `references/workflow.md` - 処理フローの詳細

## 処理概要

### Phase 1: 未処理アイテム取得
StorageDB から Status が空（未処理）のアイテムを取得する。

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

1. **プロパティ更新（分析結果の書き込み）**: `API-patch-page`（MCP）推奨。`curl` でも可。
2. **読み取り・検索**: MCP ツール（`notion-fetch`, `notion-search`, `API-query-data-source`）を使ってよい
3. **ブロック操作**: `API-patch-block-children`, `API-get-block-children` は正常動作する

## MCP ツールの既知の問題（重要）

以下のパラメータは JSON Schema に `"type": "object"` が未宣言のため、文字列としてシリアライズされるバグがある:

| ツール | パラメータ | 状態 |
|--------|-----------|------|
| `notion-create-pages` | `parent` | ❌ 使用不可 |
| `notion-move-pages` | `new_parent` | ❌ 使用不可 |
| `notion-update-page` | `data` | ❌ 使用不可 |
| `API-post-page` | `parent` | ❌ 使用不可 |
| `API-move-page` | `parent` | ❌ 使用不可 |
| `API-patch-page` | `properties` | ✅ 正常（型定義あり） |
| `API-query-data-source` | `filter` | ✅ 正常（型定義あり） |

## エラーハンドリング

- curl の HTTP ステータスコードを必ず確認する
- 200 以外の場合はエラー内容を表示して処理を停止する
- Companies の multi_select で新しい企業名を追加する場合、Notion が自動的に新しい選択肢を作成する

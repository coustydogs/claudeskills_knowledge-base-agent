# Claude Code 引き継ぎプロンプト

以下をClaude Codeにコピー＆ペーストしてください。

---

```
## タスク: knowledge-base-agent スキルのセットアップとテスト実行

### 背景
StorageDBを情報収集・分析・ナレッジ管理の統合DBとして使用する設計に変更済み。
ResearchDBは廃止し、分析結果（タグ付け、要約、日付抽出等）はStorageDBの既存ページに直接更新する。
Notion MCPツールのparentパラメータにバグがあるため、ページ作成が必要な場合はcurlを使用するが、
プロパティ更新（API-patch-page）はMCPで正常動作する。

### やること（3ステップ）

#### Step 1: スキルファイルの配置
`.claude/skills/knowledge-base-agent/` にスキルファイルを配置する。
以下の構造になっているか確認:

```
.claude/skills/knowledge-base-agent/
├── SKILL.md
└── references/
    ├── db_schema.md
    ├── api_patterns.sh
    └── workflow.md
```

#### Step 2: NOTION_TOKEN の確認
以下のコマンドでトークンが利用可能か確認:
```bash
echo "NOTION_TOKEN: ${NOTION_TOKEN:0:10}..."
```
未設定の場合、claude_desktop_config.json から取得するか、export で設定する。

#### Step 3: テスト処理の実行
StorageDBの未処理アイテム1件を分析し、分析結果をStorageDBに直接更新するテストを実行する。

**処理フロー:**
1. StorageDBから未処理アイテムを取得
2. SourceURLからコンテンツを取得・分析（Category, Tags, Summary等を生成）
3. 分析結果をStorageDBの同じページに更新（API-patch-page推奨）
   - 分析プロパティ: Category, SubCategory, Tags, Companies, Relevance, Summary, KeyPoints, OriginalDate
   - Status: `完了`
   - ProcessedAt: 当日日付
4. 結果サマリーを表示

### DB情報

| DB | Database ID | Data Source ID |
|----|-------------|----------------|
| StorageDB | `49998bb8988d44b083e816f939d9d018` | `48887d97-0f04-4c52-9f44-0b77fd8cf4f1` |

### 重要な注意事項
- 分析結果はStorageDBの既存ページを直接更新する（ResearchDBへの登録は不要）
- プロパティ更新はMCP API-patch-page推奨（正常動作する）
- curlでも可（api_patterns.sh のパターン2を参照）
```

---

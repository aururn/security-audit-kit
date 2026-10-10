# 検証の記録

キットを実際のリポジトリとエージェントで動かして確かめたことの記録です。非公開のリポジトリは名前を出さず、構成だけを書きます。見つかった脆弱性の詳細は、ここには書きません（[AGENTS.md](../AGENTS.md) の基本原則 5）。

## 2026-10-10

### スキャナ

- Windows（Docker Desktop）で `tests/run-canary.sh` が合格（5 つのツールすべてが検出、47 秒）
- 5 つのリポジトリで、どのツールも error なしで完走した（どれも 1 分前後）
  - vercel/ai-chatbot（Next.js、pnpm、648 commits）
  - 非公開の Next.js アプリ（npm、Postgres）
  - 非公開の Astro と Vercel Functions のアプリ（npm、Supabase）
  - 非公開の skill 集（lockfile なし）
  - このキット（CI、amd64・arm64）
- 使って見つかったスキャナの不具合は直した：ワークフローの YAML での誤った scan errors（[#47](https://github.com/aururn/security-audit-kit/issues/47)）、開発用の依存の区別（[#59](https://github.com/aururn/security-audit-kit/issues/59)）、semgrep のルールの取得の一時的な失敗（[#57](https://github.com/aururn/security-audit-kit/issues/57)）

### security-audit を通したアプリ

1. **非公開の Next.js アプリ（Postgres と RLS、Drizzle、LLM、Google ログイン）**
   - 手順 0〜3 と手順 4。使い捨ての Postgres をプロジェクトの手順で用意し、権限を落としたロールでテスト 809 件が通った。入口 8 本を localhost で確かめた
   - Critical・High は 0 件。Low が数件
   - キットに返したもの：サーバーが RLS をすり抜けるロールで DB につなぐ件（[#51](https://github.com/aururn/security-audit-kit/issues/51)）、DB が要るアプリを手元で動かす手順（[#53](https://github.com/aururn/security-audit-kit/issues/53)）
2. **非公開の Astro と Vercel Functions のアプリ（Supabase、API 25 本、関数 15 個、テーブル 19 個、AI が記事を書く GitHub Actions）**
   - 手順 0〜3。Next.js 用のチェックリストが当たらない構成で、言語に依存しないチェックリストとスキャナで進めた。実行環境は用意していない
   - Medium 1 件、Low が数件。スキャナの指摘 76 件のうち、誤検出は根拠を添えて除外した
   - キットに返したもの：Supabase の関数を rpc から呼べる件（[#63](https://github.com/aururn/security-audit-kit/issues/63)）、gitleaks が空の値の次の行を鍵として拾う誤検出の見分け方（[#61](https://github.com/aururn/security-audit-kit/issues/61)）
3. **キットの初版を作る元になった、LLM を中継する Next.js のアプリ**（作者が実施。[#9](https://github.com/aururn/security-audit-kit/issues/9)）

### cost-abuse-review

- 非公開の Astro アプリ：記事の生成を起動できるのは編集者以上、1 記事と月額の費用の上限、静的な出力、`robots.txt` を確かめた。上限の値とホスティングの支出上限はダッシュボードにしかないので、未確認として分けた

### pre-publish-secret-scan

- 公開版がある非公開のリポジトリ：非公開にだけあるコミットは 2 件。gitleaks は履歴・作業ツリーとも 0 件。コミットと差分に、社内の URL・メールアドレス・顧客名は無かった。「公開してよい」の判断まで進めた（push はしていない）

### skill の選ばれ方

[`evals/skill-triggers.sh`](../evals/skill-triggers.sh)。Claude Code 2.1.289 で、plugin を `--plugin-dir` で読み込んだ。使える道具は Skill だけで、MCP は読み込まない。数えるのはこの plugin の skill（`security-audit-kit:<skill>`）だけで、成功で終わらなかった回は不合格にする。

- 9 件中 9 件で、期待した skill が選ばれた（日本語 7 件、英語 1 件、どの skill も選ばれるべきでない頼み方 1 件）。同じ 9 件を別々に 3 回実行し、どれも 9/9
- 判定の仕組みは、偽の `claude` コマンドで確かめた：無関係の skill は対象外の判定に影響しない。単独で入れた skill の写しは数えない。実行が失敗した回は不合格になる

### URL を貼る入口

頼み方：「https://github.com/aururn/security-audit-kit を使って、このリポジトリの脆弱性を調べて」に、手順 0 で止める指示を足した。対象は vercel/ai-chatbot。

- Codex 0.160.0：キットを一時フォルダに取得し、`skills/security-audit/SKILL.md` に従って手順 0 を行った。デプロイ元・支出上限などを未確認として分け、レポートを対象の外に置いて止まった
- Claude Code 2.1.289：キットを一時フォルダに取得し、`AGENTS.md` の「このキットの URL を渡されたとき」と `skills/security-audit/SKILL.md` に従って手順 0 を行った。6 つの問いに `file:line` 付きで答え、デプロイ元などを未確認として分け、scope の承認を求めて止まった

### plugin

- `claude plugin validate .`：警告 1 件（ルートの `CLAUDE.md` は plugin の文脈として読まれない。意図どおり。[0007](decisions/0007-plugin-distribution.md)）
- README の 2 行を、隔離した設定ディレクトリで実行した：4 つの skill と `scripts/run-scan.sh` が入った

### まだ確かめていないこと

- macOS での `run-scan.sh` とカナリア
- Codex での手順 1 以降と、`security-fix-workflow`
- semgrep の registry の一時的な失敗からの回復（失敗したときに止まることだけを確かめた）

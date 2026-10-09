# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

@AGENTS.md

## Claude Code 固有の補足

- skills は `skills/` にある。リポジトリ全体が Claude Code の plugin（`.claude-plugin/`）でもある。
  plugin として入れるか、`scripts/install-skills.sh` で `~/.claude/skills`（と `~/.codex/skills`）に入れて使う。
- `.claude-plugin/` を変えたら `claude plugin validate .` で確かめる。version を書かない、ルートの
  CLAUDE.md は読まれない、の 2 件の警告は意図どおり（`docs/decisions/0006-plugin-distribution.md`）。
- 差分のセキュリティレビューには組み込みの `/security-review` を使える。対象は「現在のブランチの差分」なので、
  修正前のコミットを base にしたブランチで実行する。
- 並列でサブエージェントを使う場合:
  - 変更するファイルが重ならない単位でレーンを分ける。
  - E2E などポートを固定して使うテストは、1つのレーンだけでローカル実行し、他は CI に任せる。
  - Windows ではパスの大文字・小文字（`documents` と `Documents`）の違いで、組み込みの worktree 分離が
    失敗することがある。その場合は `git worktree add` で自分で作った worktree のパスを渡す。
  - サブエージェントのマージは権限チェックで止まることがある。止まったら回避させず、メインのセッションが
    状態（CI・レビュー・コンフリクト）を確認してからマージする。
- 長いコマンド（ビルド、E2E、`codex review`）はバックグラウンドで実行し、その間に他の確認を進める。

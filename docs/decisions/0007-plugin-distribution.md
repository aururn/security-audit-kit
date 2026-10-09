# 0007 Claude Code の plugin として配る

- 状態: 採用
- 日付: 2026-10-10

## 背景

skills は `scripts/install-skills.sh` で `~/.claude/skills` にコピーして使っていた。この形には次の問題があった。

- 利用者が clone してスクリプトを実行するまで使えない。URL を貼って頼まれたエージェントがこの順に従うと、利用者の環境への書き込みから始まり、auto mode では止められることがある
- コピーした skill からは、キットの `scripts/run-scan.sh` の場所が分からない
- 更新は `git pull` と `--force` での入れ直しが要る

## 決定

- リポジトリ全体を 1 つの plugin にする（`.claude-plugin/marketplace.json` の `source` を `"./"` にする）。`scripts/` と `docker/` も一緒に入るので、skill は `${CLAUDE_PLUGIN_ROOT}/scripts/run-scan.sh` でスキャナを呼べる
- `plugin.json` に `version` を書かない。書くと、その文字列を変えるまで利用者の更新が止まる。書かなければ、コミットごとに新しい版として届く
- `install-skills.sh` は残す。Codex と、plugin を使わない利用者のため。入れた skill の `.kit-version` の 3 行目に clone の場所を書き、skill はそこからスキャナを見つける
- skill は、plugin・clone・`.kit-version`・一時ディレクトリへの clone の順でキットの場所を探す。どれでも同じ手順で動く

## 結果

- `claude plugin marketplace add aururn/security-audit-kit` と `claude plugin install security-audit-kit@security-audit-kit` の 2 行で使える。skill は `security-audit-kit:security-audit` のように plugin 名が付く
- `claude plugin validate .` は 2 件の警告を出す。`version` がないこと（上の理由で意図どおり）と、ルートの `CLAUDE.md` が plugin の文脈として読まれないこと（キットを開発する人向けの文書なので問題ない）
- 第三者の marketplace は既定で自動更新されない。利用者は `claude plugin marketplace update` と `claude plugin update` で更新する

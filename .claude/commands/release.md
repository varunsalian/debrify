---
description: Cut an alpha/beta release (bump → merge → tag → GitHub release) and auto-announce to Discord when the builds finish
argument-hint: <alpha|beta> <version>   e.g. /release beta 0.6.1
allowed-tools: Bash, Read, Edit, Write
---

You are running the Debrify release procedure.

Raw arguments: `$ARGUMENTS`

## Parse the arguments FIRST — do NOT trust numbered positional placeholders

**Numbered argument placeholders are unreliable here and have misfired in practice** (they once produced `base = dont` from a guidance word, which would have created a garbage `vdont-alpha.1` tag). Ignore them entirely. Derive everything yourself from the raw argument string above, order-independently:

- **CHANNEL** = the token equal to `alpha` or `beta`
- **VERSION** = the token matching `X.Y.Z` (e.g. `0.6.1`)
- **GUIDANCE** = every remaining word — optional free-form drafting instructions

So `/release alpha 0.6.1`, `/release 0.6.1 alpha`, and `/release beta 0.7.0 keep it short` all parse correctly. If CHANNEL or VERSION can't be found, stop and ask.

Treat GUIDANCE as **binding** when writing the notes — e.g. "don't mention MDBList", "keep it short", "lead with Simkl", "skip the Fixes section". If told to exclude a topic, it must appear in **neither** the GitHub nor the Discord notes, and you must `grep -i` both files afterwards to prove it's absent.

Throughout this playbook, `<CHANNEL>`, `<VERSION>`, `<N>`, `<BUILD>` and `<TAG>` mean the values **you computed** — substitute them literally into every command you run. **Never paste a numbered argument placeholder into a shell command.**

Repo: `varunsalian/debrify`. Build workflow: `.github/workflows/build.yml`, triggered on `release: published`, builds 6 assets (Android APK, macOS DMG, Windows setup.exe, iOS IPA, Linux x86_64 + arm64 AppImage) and attaches them to the release. Discord routing/secrets live in `.release/discord-webhooks.json` (gitignored); the poster is `.release/post_discord.py`.

Do everything in order. **There is exactly ONE approval gate (Stage B).** Nothing is pushed, published, or posted before the user approves.

## Stage A — Prepare (read-only, no mutations)

1. **Preflight.** Check `git status --short`. You will only ever `git add pubspec.yaml`, so unrelated unstaged WIP is fine — but if `pubspec.yaml` already has unstaged edits, or something is already staged, surface it and ask before continuing.
2. **Compute the version.** Read the current `version:` line in `pubspec.yaml` (format `X.Y.Z-<channel>.N+BUILD`). Then:
   - `<N>` = highest existing counter for this version+channel, plus 1 (else 1). Compute from `git tag --list "v<VERSION>-<CHANNEL>.*"`.
   - `<BUILD>` = current build number + 1 (Android versionCode — it must always increase).
   - New pubspec version = `<VERSION>-<CHANNEL>.<N>+<BUILD>`. New tag `<TAG>` = `v<VERSION>-<CHANNEL>.<N>`.
   - **Sanity check — do not skip:** `<TAG>` must match `v<digits>.<digits>.<digits>-(alpha|beta).<digits>` (e.g. `v0.6.1-alpha.1`). If it contains a stray word from the guidance text, you mis-parsed — stop and re-parse.
3. **Find the changelog base:** `PREV_TAG=$(git describe --tags --abbrev=0)`. Show it to the user; they may override.
4. **Read the commits:** `git log $PREV_TAG..HEAD --pretty=format:'%s'` (commits are `Area: description` style). Group them into the established emoji-section format used by prior releases (check `gh release view $PREV_TAG` for the exact tone/sections: `### 🏠`, `### 🎬`, `### 📺`, `### ☁️`, `### 📡`, `### 📊`, `### 💬`, etc., bold feature names, bullets). Drop noise: pure refactors, version bumps, and internal release-tooling commits.
5. **Draft two renditions** and write them to the session scratchpad:
   - **GitHub notes** (`gh-notes.md`): the emoji `###` sections. If CHANNEL is `alpha`, prepend the `> ⚠️ **Alpha build** — …early testers only…` blockquote (see `gh release view v0.6.0-alpha.1`). Beta gets no warning blockquote.
   - **Discord notes** (`discord-notes.md`): same content, Discord-flavored — convert `### Header` to `**Header**` (embeds don't render `###`), keep bullets, keep it tight (embed description cap is 4096 chars — check with `wc -c`). Do NOT add the @everyone line or the alpha warning here; the poster adds those to the message content automatically.
   - If GUIDANCE excluded a topic, `grep -ic` it in both files and confirm the count is 0.

## Stage B — Approval gate (STOP)

Show the user, in one message:
- New pubspec version, `<TAG>`, PREV_TAG, current branch, and whether it's alpha (`--prerelease`) or beta.
- The full **GitHub notes** draft.
- The full **Discord notes** draft, noting it posts to the `<CHANNEL>` channel with **@everyone** (+ the auto-added alpha warning if alpha).
- Confirmation that any GUIDANCE exclusions were verified absent.

Then ask for explicit approval. **Do not proceed until the user says go.** The user can add or change drafting guidance here too (e.g. "drop the MDBList lines", "make it punchier") — apply it, update the scratchpad files, and re-show. Only after they confirm the shown drafts do you move on.

## Stage C — Execute (only after approval)

Let `BR` = current branch (`git branch --show-current`).

1. **Bump + commit + push branch:**
   - Edit only the `version:` line in `pubspec.yaml` to the new string.
   - `git add pubspec.yaml && git commit -m "Version bump: <VERSION>-<CHANNEL>.<N> (+<BUILD>)"`
   - `git push origin "$BR"`
2. **Merge to main** (skip this whole step if `BR` is already `main`):
   - `git checkout main && git pull --ff-only origin main`
   - `git merge --no-ff "$BR" -m "Merge $BR for <TAG>"`
   - `git push origin main`
3. **Tag on main + push:**
   - `git tag -a "<TAG>" -m "<TAG>"`
   - `git push origin "<TAG>"`
4. **Create the GitHub release (publishes → triggers the build):**
   - `gh release create "<TAG>" --title "<TAG>" --notes-file <scratch>/gh-notes.md` — append `--prerelease` **iff** CHANNEL is `alpha`.

## Stage D — Wait for the build, then announce

5. **Find the run:** `gh run list --workflow=build.yml --event=release --limit 3 --json databaseId,status,createdAt,displayTitle`. Pick the one whose `displayTitle` is `<TAG>`. It may take a few seconds to appear after publishing — retry if absent.
6. **Watch it in the background:** run `gh run watch <RUN_ID> --exit-status` with `run_in_background: true` (generous timeout), so you're re-invoked when the build finishes (~20–30 min). Tell the user you're watching and they can leave the window open. Meanwhile `git checkout "$BR"` so they aren't parked on `main`.
7. **When the run finishes:**
   - If it **failed** (non-zero exit / `conclusion != success`): **DO NOT post to Discord.** Report which job failed with a link (`gh run view <RUN_ID>`), and stop.
   - If it **succeeded**: verify with `gh run view <RUN_ID> --json conclusion,jobs` and confirm all 6 assets are attached — `gh release view "<TAG>" --json assets -q '.assets[].name'` should include `debrify-<TAG>.apk` plus the other 5. Then post:
     `python3 .release/post_discord.py --repo varunsalian/debrify --channel "<CHANNEL>" --tag "<TAG>" --notes-file <scratch>/discord-notes.md`
   - (Add `--dry-run` first if you want to eyeball the exact payload.)
8. **Report:** the release URL, the Discord message id, and the direct APK link. Confirm the working branch is restored.

## Guardrails
- One approval gate only (Stage B). After "go", run C→D straight through — but **never** post to Discord if the build failed.
- Only ever `git add pubspec.yaml` — never `git add -A` — so unrelated WIP is never swept into the bump commit.
- The webhook file is a secret; never print its contents or commit it.
- Never paste numbered argument placeholders into shell commands; always use the values you parsed.
- Per project rule: do not push anything the user hasn't reviewed. The Stage B approval covers the whole C→D chain.

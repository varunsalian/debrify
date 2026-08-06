---
description: Cut an alpha/beta release (bump → merge → tag → GitHub release) and auto-announce to Discord when the builds finish
argument-hint: <alpha|beta> <version>   e.g. /release beta 0.6.1
allowed-tools: Bash, Read, Edit, Write
---

You are running the Debrify release procedure.

Raw arguments: `$ARGUMENTS`

Parse the arguments **order-independently**: the **channel** is whichever token equals `alpha` or `beta`; the **version** is whichever token matches `X.Y.Z` (e.g. `0.6.1`). So `/release alpha 0.6.1`, `/release 0.6.1 alpha`, and `/release beta 0.7.0 keep it short` all parse correctly. **Every remaining word is optional free-form drafting guidance** for the changelog — e.g. "don't mention MDBList", "keep it short", "lead with Simkl", "skip the Fixes section". Treat any such guidance as **binding** when writing the notes: if told to exclude a topic, it must appear in **neither** the GitHub nor the Discord notes. If the channel or version can't be found, stop and ask.

Repo: `varunsalian/debrify`. Build workflow: `.github/workflows/build.yml`, triggered on `release: published`, builds 6 assets (Android APK, macOS DMG, Windows setup.exe, iOS IPA, Linux x86_64 + arm64 AppImage) and attaches them to the release. Discord routing/secrets live in `.release/discord-webhooks.json` (gitignored); the poster is `.release/post_discord.py`.

Do everything in order. **There is exactly ONE approval gate (Stage B).** Nothing is pushed, published, or posted before the user approves.

## Stage A — Prepare (read-only, no mutations)

1. **Preflight.** Confirm the working tree has no unexpected staged changes (`git status --short`). You will only ever `git add pubspec.yaml`, so unrelated unstaged WIP is fine — but if `pubspec.yaml` already has unstaged edits, or something is already staged, surface it and ask before continuing.
2. **Compute the version.** Read the current `version:` line in `pubspec.yaml` (format `X.Y.Z-<channel>.N+BUILD`). Then:
   - `base` = `$2`, `channel` = `$1`.
   - `N` = highest existing counter for this base+channel, plus 1 (else 1). Compute from `git tag --list "v$2-$1.*"`.
   - `BUILD` = current build number + 1 (this is the Android versionCode; it must always increase).
   - New pubspec version string = `$2-$1.N+BUILD`. New tag = `v$2-$1.N`.
   - **Sanity-check `$2` against the convention** (the user supplies it, but a wrong number is hard to walk back once tagged): an **alpha bumps the patch** — `0.6.9` → `0.6.10`; a **beta bumps the minor and resets the patch**, because it consolidates the whole alpha run behind it — `0.6.0-beta.1`, then alphas `0.6.1`…`0.6.10`, then `0.7.0-beta.1`. If the requested version doesn't fit that shape, say so at the approval gate rather than silently tagging it.
3. **Find the changelog base — it depends on the channel.** The notes must cover everything *this channel's* audience hasn't seen yet, which is not the same span for both:
   - `channel == beta` → the last **beta** tag: `PREV_TAG=$(git tag --list "v*-beta.*" --sort=-creatordate | head -1)`. Beta users never received the alphas in between, so basing a beta on the last alpha tag silently drops every feature shipped since the last beta — after a run of 9 alphas that is ~230 commits of work reduced to ~5.
   - `channel == alpha` → the last tag of **any** channel: `PREV_TAG=$(git tag --list "v*" --sort=-creatordate | head -1)`. Alpha users get every build, so whichever release came last — alpha or beta — is what they already have.
   - If no tag matches (first release on that channel), fall back to the last tag of any channel and say so in the approval message.

   Do **not** use `git describe --tags --abbrev=0` here. Release branches fork from the previous release branch's tip while tags land on `main`'s merge commits, so the newest tags frequently aren't ancestors of HEAD; `describe` then reaches further back than it should and replays already-shipped notes. Sorting tags by creation date is ancestry-independent, which is what this flow needs.

   Show the user the resolved base, its date, and the commit count it spans (`git log $PREV_TAG..HEAD --oneline --no-merges | wc -l`) — a count wildly larger or smaller than the release feels is the signal the base is wrong. They may override.
4. **Read the commits:** `git log $PREV_TAG..HEAD --pretty=format:'%s'` (their commits are `Area: description` style). Group them into the established emoji-section format used by prior releases — read the **most recent** release for the current tone/sections (`gh release view "$(git tag --list "v*" --sort=-creatordate | head -1)"`): `### 🏠`, `### 🎬`, `### 📺`, `### ☁️`, `### 📡`, `### 📊`, `### 💬`, etc., bold feature names, bullets. Drop noise (pure refactors, version-bump commits).
   - A **beta following a run of alphas spans hundreds of commits**. Don't transcribe the log: group by theme, lead with the headline features, and fold small related commits into one line — the reader is meeting all of it for the first time, and a 200-bullet wall reads as noise. The alpha-by-alpha notes already published are a good source for what each chunk was about.
5. **Draft two renditions** and write them to the session scratchpad:
   - **GitHub notes** (`gh-notes.md`): the emoji `###` sections. If `channel == alpha`, prepend the `> ⚠️ **Alpha build** — …early testers only…` blockquote (see `gh release view v0.6.0-alpha.1`). Beta gets no warning blockquote.
   - **Discord notes** (`discord-notes.md`): the SAME content but Discord-flavored — convert `### Header` to `**Header**` (embeds don't render `###`), keep bullets. Do NOT add the @everyone line or the alpha warning here — the poster script adds those to the message content automatically.
     - **Discord hard-caps an embed description at 4096 characters**, and the poster truncates silently past it — the announcement everyone reads gets cut mid-list with a "… full release notes" link. An alpha never gets near that; a beta consolidating a run of alphas will sail past it. Write the Discord rendition to *fit*: headline features only, fewer bullets than the GitHub notes, detail left to the link. Verify before the gate with `wc -c <scratch>/discord-notes.md` and say the number in the approval message.

## Stage B — Approval gate (STOP)

Show the user, in one message:
- New pubspec version, new tag, prev tag **and the commit count it spans**, current branch, whether alpha (`--prerelease`) or beta.
- The full **GitHub notes** draft.
- The full **Discord notes** draft **with its character count against the 4096 cap**, and a note that the post goes to the `$1` channel with **@everyone** (+ the auto-added alpha warning if alpha).

Then ask for explicit approval. **Do not proceed until the user says go.** The user can add or change drafting guidance here too (e.g. "drop the MDBList lines", "make it punchier") — apply it, update the scratchpad files, and re-show. Only after they confirm the shown drafts do you move on.

## Stage C — Execute (only after approval)

Let `BR` = current branch (`git branch --show-current`).

1. **Bump + commit + push branch:**
   - Edit only the `version:` line in `pubspec.yaml` to the new string.
   - `git add pubspec.yaml && git commit -m "Version bump: $2-$1.N (+BUILD)"`
   - `git push origin "$BR"`
2. **Merge to main** (skip this whole step if `BR == main`):
   - `git checkout main && git pull --ff-only origin main`
   - `git merge --no-ff "$BR" -m "Merge $BR for v$2-$1.N"`
   - `git push origin main`
3. **Tag on main + push:**
   - `git tag -a "v$2-$1.N" -m "v$2-$1.N"`
   - `git push origin "v$2-$1.N"`
4. **Create the GitHub release (publishes → triggers the build):**
   - `gh release create "v$2-$1.N" --title "v$2-$1.N" --notes-file <scratch>/gh-notes.md` — append `--prerelease` **iff** `channel == alpha`.

## Stage D — Wait for the build, then announce

5. **Find the run:** `gh run list --workflow=build.yml --event=release --limit 1 --json databaseId,status,createdAt`. It may take a few seconds to appear after the release publishes — retry the list if empty.
6. **Watch it in the background:** run `gh run watch <RUN_ID> --exit-status` with `run_in_background: true`, so you're re-invoked when the build finishes (~20–30 min). Tell the user you're watching and they can leave the window open.
7. **When the run finishes:**
   - If it **failed** (non-zero exit / `conclusion != success`): DO NOT post to Discord. Report which job failed with a link (`gh run view <RUN_ID>`), then skip straight to step 9.
   - If it **succeeded**: verify the assets are attached — `gh release view "v$2-$1.N" --json assets -q '.assets[].name'` should include `debrify-v$2-$1.N.apk` and the other 5. Then post:
     `python3 .release/post_discord.py --repo varunsalian/debrify --channel "$1" --tag "v$2-$1.N" --notes-file <scratch>/discord-notes.md`
   - (Tip: run the same command with `--dry-run` first if you want to eyeball the exact payload.)
8. **Report:** the release URL, the Discord message result, and the direct APK link.
9. **Open the next cycle's branch.** Do this even if the build failed or Discord was skipped — the release commit is already on main either way.
   - `NEXT` = `$2` with the patch component incremented, suffixed **`_alpha`** — releasing `0.6.6` gives `0.6.7_alpha`, and releasing beta `0.7.0` gives `0.7.1_alpha`. Always `_alpha` regardless of the channel just shipped: development continues on alphas, and a beta is the consolidation of the alpha run before it, not the start of a beta series. If the user named a different next version in their arguments, use theirs.
   - `git checkout main && git pull --ff-only origin main`
   - `git checkout -b "$NEXT"` — local only; don't push an empty branch. If it already exists, just check it out and say so.
   - This replaces returning to `$BR`: the user ends the command on the fresh branch, ready for the next cycle's work. Tell them which branch they're on.

## Guardrails
- One approval gate only (Stage B). After "go", run C→D straight through, but never post to Discord if the build failed.
- Only ever `git add pubspec.yaml` — never `git add -A` — so unrelated WIP is never swept into the bump commit.
- The webhook file is a secret; never print its contents or commit it.
- Per project rule: do not push anything the user hasn't reviewed. The Stage B approval covers the whole C→D chain.

---
name: sc:crud
description: Create, update, or import a skill. Use when the user says "make a new skill", "add a skill for X", "update the X skill", "edit the Y skill", "remove this skill", "import these skills", "register this folder of skills", "figure out what skills are in <dir> and register them", or describes a workflow they want captured as a skill. The procedure first searches for existing skills that might already cover the user's intent (so we update rather than duplicate), then presents the candidates or — if the user named a specific skill — goes straight to it. Soft-delete via mv to ~/.sc/trash/, name-derivation rule: first '-' becomes ':' (e.g. my-cool-tool → my:cool-tool).
user_invocable: true
---

# sc:crud — lifecycle for skills (procedural, no CLI)

This skill is **a procedure**, not a shell command. You (the agent) execute the steps below using `Read`, `Edit`, `Write`, `Bash`. There is no `sc/crud/action` script — the procedure runs entirely in-agent.

## Triggers

User says any of: "make a new skill", "add a skill for X", "create a skill that …", "update the X skill", "edit the Y skill", "fix Z in the Z skill", "remove the X skill", "delete X skill", "import these skills", "register this folder", "add this skills repo", "figure out what skills are in <dir> and register them", or describes a workflow / habit / task they want captured as a reusable skill.

## Procedure

### Step 1 — Did the user name a specific skill?

A user message **names a skill** if it contains an explicit skill reference: a frontmatter name like `s:commit` or `sc:search`, a dirname like `s-commit` or `git-rebase`, or an unambiguous "the X skill" phrasing where X is a known existing skill.

- **Yes, named** → skip to Step 4 (Update) with that skill. No candidate search.
- **No, not named** → continue to Step 2.

### Step 2 — Search for candidates that might already cover the intent

Distil the user's request into 3 axis queries (literal / synonym / intent) — same shape as `sc:search`. Then call:

```sh
sh ~/.sc/search/action "<literal>" "<synonym>" "<intent>" --limit 8
```

Look at the **Convergence** section. Skills with `axes=3` (or `axes=2` with a high score) are candidates worth proposing as updates instead of creating a new one.

If Convergence is empty AND no Single-axis hit scores above ~0.10, skip to Step 3 (Create new). Otherwise continue.

### Step 3 — Present candidates to the user (or skip to create)

If Step 2 surfaced candidates, present them to the user as a short numbered list and ask:

> I found existing skills that look related:
>
> 1. `<name>` — `<one-line description>` (at `<full path>`)
> 2. `<name>` — `<description>` (at `<path>`)
> 3. …
>
> Update one of these, or create a new skill?

Wait for the user's answer. If they pick (N) → go to Step 4 (Update) with that skill. If they say "new" / "create new" / "none of these" → go to Step 5 (Create).

If Step 2 found nothing worth proposing, **don't bother asking** — just confirm the create intent in one sentence and go to Step 5.

### Step 4 — Update an existing skill

1. `Read` the skill's `SKILL.md`.
2. Discuss the change with the user if needed. Otherwise apply directly.
3. Use `Edit` to make targeted changes. Preserve the existing frontmatter `name:` exactly — never rename via update; the user must rename the directory if they want a different `name:` (see "Rename" below).
4. If the change affects the `description:` field, front-load it with trigger phrases users would type when looking for the skill.
5. Run `sh ~/.sc/search/action reindex --full` to refresh the FTS5 index.
6. Confirm to the user: "Updated `<name>` at `<path>`."

### Step 5 — Create a new skill

1. **Resolve the target repo.**
   - If the user passed a `--repo` style instruction or specified a repo, use it.
   - Otherwise read `~/.sc/default_repo` (single line, abs path). Use it.
   - Otherwise read `~/.sc/repos.patterns` and check if there is exactly one root. Use it.
   - Otherwise ask the user which repo, listing the roots from `repos.patterns`.

2. **Pick a directory name.** Conventionally kebab-case with a clear namespace prefix (e.g. `git-bisect`, `aws-s3-sync`). The first `-` becomes the `:` in the frontmatter name (see "Name derivation" below).

3. **Collision check.** Discover skills via:
   ```sh
   sh ~/.sc/search/action list-roots
   ```
   then for each root, `find <root> -name SKILL.md` and check no directory has the chosen basename anywhere. If a collision is found, propose a renamed variant and ask the user.

4. **Scaffold.** Compute `<target> = <resolved-repo-skills-dir>/<dirname>`. (For repos with a `skills/` layout, this is `<repo>/skills/<dirname>`.) `Write` the following two files:

   `<target>/SKILL.md`:
   ```markdown
   ---
   name: <derived-name>
   description: <one trigger-style sentence — what the skill does + WHEN to use it. Front-load synonyms.>
   user_invocable: true
   ---

   # <derived-name>

   <body — describe the procedure. Include concrete CLI examples, use WHEN / do NOT use WHEN guidance, related skills.>
   ```

   `<target>/skill.sh` (optional, only if the skill needs a helper):
   ```sh
   #!/bin/sh
   set -eu
   # TODO — implement the skill's helper logic, or delete this file.
   echo "$(basename "$0"): TODO implement"
   ```
   `chmod +x <target>/skill.sh` if you wrote it.

5. **Reindex:**
   ```sh
   sh ~/.sc/search/action reindex --full
   ```

6. **Confirm to the user:** "Created `<name>` at `<target>`."

### Step 6 — Delete a skill (when user asks)

Soft-delete by default. Hard-delete only if user explicitly says "purge", "permanently delete", or "rm -rf".

Soft-delete procedure:

1. Find the skill source dir (use `sc:search` to look it up, or `find` if user gave an exact dirname).
2. Build a timestamp: `ts=$(date -u +%Y-%m-%dT%H-%M-%SZ)`.
3. `mkdir -p ~/.sc/trash/${ts}-<dirname>`.
4. `mv <source-dir> ~/.sc/trash/${ts}-<dirname>` (the trash dir takes over the source dir path).

   Actually simpler — just rename the source into trash:
   ```sh
   ts=$(date -u +%Y-%m-%dT%H-%M-%SZ)
   mv "<source-dir>" "$HOME/.sc/trash/${ts}-<dirname>"
   ```
5. `Write` `~/.sc/trash/${ts}-<dirname>/.sc-trash-meta.json` with the original path so restore is possible:
   ```json
   {
     "name": "<dirname>",
     "orig_path": "<source-dir>",
     "deleted_at": "<ISO-8601 Z>"
   }
   ```
6. Reindex.
7. Confirm: "Soft-deleted `<name>`. Restore with: `mv ~/.sc/trash/${ts}-<dirname> <orig_path>` (or read the meta JSON)."

Hard-delete (`--purge` / "permanently") skips the trash:
```sh
rm -rf "<source-dir>"
```
Reindex. Confirm.

### Step 7 — Import / register existing skills

Use when the user points at a directory that already contains one or more `SKILL.md` files but isn't yet discoverable by `sc:search`. Trigger phrases: "import these skills", "register this folder", "add this skills repo", "figure out what skills are in `<dir>` and register them".

> **Terminology note:** "Register" here means register the *source root* with `sc:search`'s discovery config (`~/.sc/repos.patterns`) and refresh the FTS5 index. It does NOT install the skill into the agent harness — `sc:search` and `sc:crud` are the bootstrap harness entries skill-core itself adds; everything else stays path-based and is consumed by reading the SKILL.md at its full path.

1. **Resolve the source root.** Use the absolute path the user supplied. If they pointed at a single skill dir (one containing `SKILL.md`), use its parent as the root.

2. **Check whether the root is already covered.** Read `~/.sc/repos.patterns`. If any existing `<abs-root>` line equals the target root — or is an ancestor of it (the target lives inside an already-listed root) — the root is already registered. Skip to step 5.

3. **Append the root.** Add a single line to `~/.sc/repos.patterns`:
   ```
   <abs-root>	*
   ```
   Use a literal TAB as the separator; pattern `*` matches every skill dir basename. For a subset, use a glob (e.g. `s-*`) or `re:<regex>`.

4. **Validate the config:**
   ```sh
   sh ~/.sc/search/action doctor
   ```
   Fix any errors surfaced before continuing.

5. **Discover what's under the root** (so the confirmation in step 7 is accurate):
   ```sh
   find "<abs-root>" -name SKILL.md
   ```
   For each result, read the first ~6 lines to confirm valid frontmatter (`name:`, `description:`). Note any SKILL.md missing required fields — surface those to the user so they can fix.

6. **Reindex:**
   ```sh
   sh ~/.sc/search/action reindex --full
   ```

7. **Confirm to the user.** Report how many SKILL.md files were discovered under the root and list their derived names, e.g.:
   > Imported 5 skills under `<root>`: `s:audit`, `s:commit`, `s:diagram`, `s:servers`, `s:team`.

   If the root was already covered in step 2, say so explicitly: "Root already registered; reindexed and `<N>` skills are discoverable."

### Rename

A rename = move the directory + update the frontmatter `name:`:

```sh
mv "<source>/<old-dirname>" "<source>/<new-dirname>"
```
Then `Edit` `<source>/<new-dirname>/SKILL.md` to update the `name:` field (apply the derivation rule below).
Reindex.

### Restore from trash

```sh
ls ~/.sc/trash/
```
Find the entry. Read `.sc-trash-meta.json` (via awk if needed) to recover `orig_path`. Then:
```sh
mv "~/.sc/trash/<entry>" "<orig_path>"
rm -f "<orig_path>/.sc-trash-meta.json"
```
Reindex.

## Name derivation (canonical)

The frontmatter `name:` is the directory basename with **only the first `-` replaced by `:`**. All other hyphens stay.

| dirname            | derived `name:`                       |
|--------------------|---------------------------------------|
| `my-skill`         | `my:skill`                            |
| `my-cool-tool`     | `my:cool-tool`  (NOT `my:cool:tool`)  |
| `sc-search`        | `sc:search`                           |
| `sc-crud`          | `sc:crud`                             |
| `git-rebase`       | `git:rebase`                          |
| `alpha-beta-gamma` | `alpha:beta-gamma`                    |
| `noskill`          | `noskill` (no dash → unchanged)       |

This is **different from the old `s:create`**, which converted every `-`. If the user is migrating an old skill, ask them whether they want `every-dash:as-colon` (old) or `first-only:as-colon` (current convention) — the current convention is recommended.

## Always after a mutation

A reindex runs automatically on the next `sc:search` invocation when the skill set drifts (hash-based change detection). An explicit `sh ~/.sc/search/action reindex --full` only forces an immediate rebuild — useful when you want to confirm right away.

If the user adds a brand-new repo root to `~/.sc/repos.patterns`, run `doctor` first:
```sh
sh ~/.sc/search/action doctor
```
to catch malformed config before reindexing.

## Path / patterns / config files (reference)

- `~/.sc/repos.patterns` — one `<abs-root><TAB><pattern>` per line. Pattern is a glob over directory basenames; `re:` prefix for regex.
- `~/.sc/default_repo` — single-line file with the abs path used when the user doesn't specify a repo on create.
- `~/.sc/trash/<ISO-Z-ts>-<dirname>/` — soft-deleted skills with `.sc-trash-meta.json`.
- Skills you create with this procedure are **not** registered with the agent harness — they live in a source repo and are discovered by `sc:search`. The only harness entries skill-core adds are `sc:search` and `sc:crud` themselves; anything else already in the harness is left alone.

## Edge cases

- **User asks for a skill that already exists with the exact same name**: in Step 2 the candidate will be the exact-match skill. Default to **update** unless the user explicitly says "create new with a different name".
- **User asks to "delete X" but X doesn't exist**: tell them so. Offer to `sc:search` for X to see if it has a different name.
- **Source repo isn't writable** (permission denied): tell the user, suggest a different `--repo` or a `chmod`.
- **Reindex fails** (sqlite error, missing repos.patterns): surface the exact stderr; suggest `doctor`.
- **The skill's body references other skills**: link by full path (`/Users/me/Projects/.../skill-name`), not by slash-command — slash-commands don't work for non-bootstrap skills.

## Related

- `sc:search` — search engine. Used in Step 2 of this procedure.
- `~/.sc/search/action` — the search shell CLI (the only remaining CLI in this system).
- `/Users/coding/Projects/skill-core/INSTALL.md` — one-time bootstrap.

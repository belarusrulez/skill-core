---
name: sc:crud
description: Create, update, or import a skill. Use when the user says "make a new skill", "add a skill for X", "update the X skill", "edit the Y skill", "remove this skill", "import these skills", "register this folder of skills", "figure out what skills are in <dir> and register them", or describes a workflow they want captured as a skill. The procedure first searches for existing skills that might already cover the user's intent (so we update rather than duplicate), then presents the candidates or — if the user named a specific skill — goes straight to it. Soft-delete via mv to ~/.sc/trash/, name-derivation rule: first '-' becomes ':' (e.g. my-cool-tool → my:cool-tool). After any create or update, the procedure runs an integrity check (frontmatter present, name/description non-empty, helper scripts executable).
user_invocable: true
disable-model-invocation: true
---

# sc:crud — lifecycle for skills

`sc:crud` is a **mixed procedure**:

- You (the agent) own the *judgment* steps — deciding update-vs-create, choosing the target repo, writing the description prose, recognizing when a candidate from `sc:search` is the right update target.
- The deterministic filesystem operations are delegated to **`sh ~/.sc/crud/action <subcommand>`**, so the result is identical every time and costs zero LLM tokens.

```sh
sh ~/.sc/crud/action help
# collision-check <dirname>     exit 0=ok, 1=collision (prints colliding paths)
# scaffold <target-dir>         write SKILL.md + executable action stub
# validate <skill-dir>          check structure; exit 0=ok, 1=issues
# trash <source-dir>            soft-delete to ~/.sc/trash/; prints trash path
# restore <trash-entry>         move back to orig_path from meta JSON
# import-preview <root>         emit TSV: path<TAB>name<TAB>description<TAB>issues
```

## Integrity rule — ALWAYS validate after create or update

After **every** Step 4 (Update) and Step 5 (Create), and after a Step 7 (Import) of any skill you just touched, run:

```sh
sh ~/.sc/crud/action validate <skill-dir>
```

It checks: SKILL.md exists, has a frontmatter block, `name` and `description` fields are non-empty, and any `action` / `*.sh` files are executable. If validate exits non-zero, fix the issues it reports **before** confirming the create/update to the user. A skill that fails validate is broken for downstream consumers (`sc:search` indexing, `sc:list` enumeration, agents reading the SKILL.md).

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

If Step 2 surfaced candidates, present them as a short numbered list and ask:

> I found existing skills that look related:
>
> 1. `<name>` — `<one-line description>` (at `<full path>`)
> 2. `<name>` — `<description>` (at `<path>`)
> 3. …
>
> Update one of these, or create a new skill?

Wait for the user's answer. If they pick (N) → Step 4 (Update). If they say "new" / "create new" / "none of these" → Step 5 (Create).

If Step 2 found nothing worth proposing, **don't bother asking** — confirm the create intent in one sentence and go to Step 5.

### Step 4 — Update an existing skill

1. `Read` the skill's `SKILL.md`.
2. Discuss the change with the user if needed. Otherwise apply directly.
3. Use `Edit` to make targeted changes. Preserve the existing frontmatter `name:` exactly — never rename via update; the user must rename the directory if they want a different `name:` (see "Rename" below).
4. If the change affects the `description:` field, front-load it with trigger phrases users would type when looking for the skill.
5. **Validate** (mandatory):
   ```sh
   sh ~/.sc/crud/action validate <skill-dir>
   ```
   If non-zero, fix the reported issues and re-run.
6. Run `sh ~/.sc/search/action reindex --full` to refresh the FTS5 index.
7. Confirm to the user: "Updated `<name>` at `<path>`."

### Step 5 — Create a new skill

1. **Resolve the target repo.**
   - If the user passed a `--repo` style instruction or specified a repo, use it.
   - Otherwise read `~/.sc/default_repo` (single line, abs path). Use it.
   - Otherwise read `~/.sc/repos.patterns` and check if there is exactly one root. Use it.
   - Otherwise ask the user which repo, listing the roots from `repos.patterns`.

2. **Pick a directory name.** Conventionally kebab-case with a clear namespace prefix (e.g. `git-bisect`, `aws-s3-sync`). The first `-` becomes the `:` in the frontmatter name (see "Name derivation" below).

3. **Collision check:**
   ```sh
   sh ~/.sc/crud/action collision-check <dirname>
   ```
   Exits 0 if the basename is free, 1 if a skill with that basename already exists (printed paths go to stderr). On collision, propose a renamed variant and ask the user.

4. **Scaffold:**
   ```sh
   sh ~/.sc/crud/action scaffold <target-dir>
   ```
   Writes a `SKILL.md` template (with the derived name pre-filled) and an executable `action` stub. Edit both to replace TODOs:
   - Replace the frontmatter `description:` with one trigger-style sentence; front-load the synonyms users will type.
   - Replace the body with the actual procedure.
   - If the skill is procedural-only and needs no helper, delete the `action` stub.

5. **Validate** (mandatory):
   ```sh
   sh ~/.sc/crud/action validate <target-dir>
   ```
   If non-zero, fix the reported issues and re-run.

6. **Reindex:**
   ```sh
   sh ~/.sc/search/action reindex --full
   ```

7. **Confirm to the user:** "Created `<name>` at `<target>`."

### Step 6 — Delete a skill (when user asks)

Soft-delete by default. Hard-delete only if user explicitly says "purge", "permanently delete", or "rm -rf".

```sh
sh ~/.sc/crud/action trash <source-dir>
# prints: /Users/.../.sc/trash/<ISO-ts>-<dirname>
```

The action handles timestamping, the `mv`, and the `.sc-trash-meta.json` atomically. Then:

```sh
sh ~/.sc/search/action reindex --full
```

Confirm: "Soft-deleted `<name>`. Restore with: `sh ~/.sc/crud/action restore <trash-path>`."

Hard-delete (`--purge` / "permanently") skips the trash:
```sh
rm -rf "<source-dir>"
sh ~/.sc/search/action reindex --full
```

### Step 7 — Import / register existing skills

Use when the user points at a directory that already contains one or more `SKILL.md` files but isn't yet discoverable by `sc:search`. Trigger phrases: "import these skills", "register this folder", "add this skills repo", "figure out what skills are in `<dir>` and register them".

> **Terminology note:** "Register" here means register the *source root* with `sc:search`'s discovery config (`~/.sc/repos.patterns`) and refresh the FTS5 index. It does NOT install the skill into the agent harness — `sc:search`, `sc:crud`, and `sc:list` are the bootstrap harness entries skill-core itself adds; everything else stays path-based and is consumed by reading the SKILL.md at its full path.

1. **Resolve the source root.** Use the absolute path the user supplied. If they pointed at a single skill dir (one containing `SKILL.md`), use its parent as the root.

2. **Check whether the root is already covered.** Read `~/.sc/repos.patterns`. If any existing `<abs-root>` line equals the target root — or is an ancestor of it — the root is already registered. Skip to step 5.

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

5. **Preview what's under the root:**
   ```sh
   sh ~/.sc/crud/action import-preview <abs-root>
   ```
   Emits TSV: `path<TAB>name<TAB>description<TAB>issues` per discovered SKILL.md. The `issues` column flags `missing-name`, `missing-description`, or `no-frontmatter` so you can surface broken skills to the user before they're indexed.

6. **Reindex:**
   ```sh
   sh ~/.sc/search/action reindex --full
   ```

7. **Confirm to the user.** Report how many SKILL.md files were discovered under the root and list their derived names, e.g.:
   > Imported 5 skills under `<root>`: `s:audit`, `s:commit`, `s:diagram`, `s:servers`, `s:team`.

   If the root was already covered in step 2, say so explicitly: "Root already registered; reindexed and `<N>` skills are discoverable."

### Rename

A rename = move the directory + update the frontmatter `name:` + validate:

```sh
mv "<source>/<old-dirname>" "<source>/<new-dirname>"
```
Then `Edit` `<source>/<new-dirname>/SKILL.md` to update the `name:` field (apply the derivation rule below), run `validate`, then reindex.

### Restore from trash

```sh
ls ~/.sc/trash/
sh ~/.sc/crud/action restore ~/.sc/trash/<entry>
sh ~/.sc/search/action reindex --full
```

The action reads `.sc-trash-meta.json`, moves the dir back to `orig_path`, and removes the meta file.

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

Note: this convention covers the **flat** layout (`<repo>/skills/<dirname>/SKILL.md`). Some repos use a **nested** namespace layout (e.g. skill-core puts `sc:list` at `sc/list/` rather than `sc/sc-list/`); in that case the author picks `name:` directly and `validate` doesn't second-guess it.

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
- `~/.sc/crud/action` — the CLI this skill delegates deterministic work to. Symlinked from `<repo>/sc/crud/action`.
- Skills you create with this procedure are **not** registered with the agent harness — they live in a source repo and are discovered by `sc:search` and `sc:list`. The only harness entries skill-core adds are `sc:search`, `sc:crud`, and `sc:list` themselves; anything else already in the harness is left alone.

## Edge cases

- **User asks for a skill that already exists with the exact same name**: in Step 2 the candidate will be the exact-match skill. Default to **update** unless the user explicitly says "create new with a different name".
- **User asks to "delete X" but X doesn't exist**: tell them so. Offer to `sc:search` for X to see if it has a different name.
- **Source repo isn't writable** (permission denied): tell the user, suggest a different `--repo` or a `chmod`.
- **Reindex fails** (sqlite error, missing repos.patterns): surface the exact stderr; suggest `doctor`.
- **`validate` fails after a create/update**: do NOT confirm success to the user. Fix the reported issues (most common: empty `description:` or non-executable `action`), re-run validate, then continue.
- **The skill's body references other skills**: link by full path (`/Users/me/Projects/.../skill-name`), not by slash-command — slash-commands only work for harness-registered skills.

## Related

- `sc:search` — search engine. Used in Step 2 of this procedure.
- `sc:list` — flat inventory; useful for "show me what's in this root" before bulk edits.
- `~/.sc/crud/action` — the deterministic helper this procedure delegates to.
- `~/.sc/search/action` — search/reindex/doctor CLI.
- `/Users/coding/Projects/skill-core/INSTALL.md` — one-time bootstrap.

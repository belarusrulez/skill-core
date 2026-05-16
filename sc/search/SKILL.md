---
name: sc:search
description: Search across all registered skill repos for a skill that matches the user's intent. Use when the user asks "do I have a skill for X", "which skill does Y", "find a skill that …", "is there a skill to …", "list my skills", or any "find/locate/search for a skill" phrasing. The script takes THREE positional queries (literal phrase, synonym/jargon, intent/goal) and merges results across axes via Reciprocal Rank Fusion (RRF) so skills matching 2+ axes surface in a "Convergence" section — the strongest signal.
user_invocable: true
---

# sc:search — multi-axis skill search

Skill sources live in directories listed in `~/.sc/repos.patterns` (one `<abs-root><TAB><pattern>` per line). The search action discovers every `SKILL.md` under those roots, maintains a SQLite FTS5 index at `~/.sc/search/index.db`, and answers multi-axis queries.

## CRITICAL — pass THREE queries

When invoking `sc:search`, **always pass three positional query strings**, each capturing a different axis of what the user is asking for:

1. **literal** — words/phrases the user actually used (or might have used)
2. **synonym / jargon** — domain-specific terms for the same concept
3. **intent / goal** — what the user is trying to *accomplish*, phrased differently

The script merges the three rankings via **Reciprocal Rank Fusion (RRF, k=10)** with each per-query result capped at top-5 before fusion. Skills that match 2+ axes are grouped in a **Convergence** section — that's the strongest signal and where the right answer almost always lives. Skills matching only one axis appear under **Single-axis hits**.

If you call the action with fewer than 3 queries, you'll get a `WARN:` on stderr and weaker results. Don't do that.

### Why three axes

The caller (you) doesn't know exactly what vocabulary the skill author used. Three rephrasings hedge against vocabulary mismatch — and convergence across axes is a much stronger ranking signal than any single bm25 score, since bm25 magnitudes don't compare cleanly across different queries.

## How to invoke

```sh
# 3-axis search (the common case):
sh ~/.sc/search/action search "<axis-1: literal>" "<axis-2: synonym>" "<axis-3: intent>"

# Shorthand — bare positional args route to `search`:
sh ~/.sc/search/action "<axis-1>" "<axis-2>" "<axis-3>"

# Options:
sh ~/.sc/search/action search "<q1>" "<q2>" "<q3>" --limit 30 --format json

# Maintenance:
sh ~/.sc/search/action reindex          # rebuild FTS5 index (atomic)
sh ~/.sc/search/action list-roots       # print resolved roots from repos.patterns
sh ~/.sc/search/action doctor           # validate config
sh ~/.sc/search/action doctor --write-sample   # seed a starter ~/.sc/repos.patterns
```

`--format`: `text` (default — two sections: Convergence + Single-axis, with a `→ <full path>` line under each hit), `tsv` (one row per hit: `path<TAB>name<TAB>dirname<TAB>description<TAB>score<TAB>axes`), or `json`.

`--limit`: cap on returned rows (default 20).

## How skills are used (CRITICAL)

**Skills are NOT registered with the agent harness** — `sc:search` and `sc:crud` are the two bootstrap skills skill-core itself adds. Everything `sc:search` returns is a *file you read*, not a slash-command you invoke.

The workflow:
1. Run `sc:search` with 3 queries.
2. Pick the top hit from Convergence (or the top Single-axis if Convergence is empty).
3. **Read the `SKILL.md` at the full path shown after `→`** (`<path>/SKILL.md`) and **immediately start following its instructions** to complete the user's task.
4. If, after reading, that skill is clearly not the right fit for the user's intent, fall back to the next-ranked hit and repeat — **up to 3 candidates total**. Only if all 3 are wrong, tell the user and ask how to proceed.

There is no slash-command activation, no `/<skill-name>` invocation. The path IS the skill.

### Do NOT ask before using the top hit

Once `sc:search` returns a top hit, **do not ask the user for permission to read it or run it** (e.g. don't say "Want me to read it and run it?"). Reading the SKILL.md and executing its instructions IS the job — asking first is friction the user has explicitly rejected. The only reasons to pause:

- All 3 top candidates have been read and none fit → tell the user, ask what to do.
- The skill's own instructions require confirmation for a destructive/irreversible step (commits, pushes, deletes, etc.) — in that case follow the skill's own guidance, not a generic "should I start?" prompt.

Phrase status updates as actions ("Reading `s:commit` and applying it now."), not as offers ("Want me to…?").

## Example

User asks: "do I have a skill to put together a commit message?"

```sh
sh ~/.sc/search/action "commit message" "git commit author" "save changes describe diff"
```

Output:

```
## Convergence (matched 2+ axes — strongest signal)
  s:commit               axes=3 score=0.2727  Review all changes, generate commit message, …
           → /Users/me/Projects/my-skills/s-commit
  s:audit                axes=2 score=0.1548  Audit all plans, project docs, Mermaid …
           → /Users/me/Projects/my-skills/s-audit
```

Then: `Read /Users/me/Projects/my-skills/s-commit/SKILL.md` and follow its instructions.

## Exit codes

| code | meaning                                              |
|------|------------------------------------------------------|
| 0    | hits returned                                        |
| 1    | no skills matched                                    |
| 2    | config error (missing/invalid `~/.sc/repos.patterns`)|
| 3    | index error (sqlite/FTS5 failure)                    |

## When you can't find anything

- Try broader / more synonymous queries — the user may have phrased the intent very differently from the skill description.
- Run `sh ~/.sc/search/action list-roots` to confirm the expected repo is registered.
- A reindex runs automatically on every action invocation when the indexed skill set drifts (SHA-256 of `<path>+<content>` for every SKILL.md is cached at `~/.sc/search/.index_hash`); manual `reindex` is only needed to force a rebuild.
- If still nothing, say so explicitly and offer to either (a) `list-roots` and have the user add the missing repo, or (b) create a new skill with `sc:crud` (follow its procedure).
- DO NOT try `/<skill-name>` slash-commands; they aren't registered. Always go through `sc:search` → path → read SKILL.md.

## Related

- `sc:crud` — create / edit / delete / restore skills across registered repos. Like `sc:search`, it operates on source-of-truth dirs, NOT on the agent's skill-registration dir — no symlinks.
- `~/.sc/repos.patterns` — user-edited list of source roots; each line is `<abs-root><TAB><pattern>`. Pattern matches the skill *directory basename*; prefix with `re:` for an extended regex (default is a POSIX glob, `*` = all).
- See `/Users/coding/Projects/skill-core/INSTALL.md` for the one-time setup (skill-core registers `sc:search` and `sc:crud` with the agent; everything else is path-based).

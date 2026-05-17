---
name: sc:list
description: List every registered skill across the roots in ~/.sc/repos.patterns. Use when the user asks "list my skills", "what skills do I have", "show all skills", "enumerate skills", "skill inventory", "skills installed", or wants a flat catalog rather than a ranked search. Unlike sc:search (which ranks by query relevance), sc:list returns the full set — optionally filtered by root or skill-name pattern — with one row per skill (name, dirname, description, full path).
user_invocable: true
---

# sc:list — enumerate every registered skill

Skill sources live in directories listed in `~/.sc/repos.patterns` (one `<abs-root><TAB><pattern>` per line). `sc:list` walks every registered root, discovers every `SKILL.md` under it, and prints one row per skill.

This is the **inventory** view. Use `sc:search` when you want ranked relevance for a specific intent; use `sc:list` when you want the whole catalog.

## How to invoke

```sh
sh ~/.sc/list/action                         # list every skill, text format
sh ~/.sc/list/action --format tsv            # one row per skill, tab-separated
sh ~/.sc/list/action --format json           # JSON array
sh ~/.sc/list/action --root <abs-root>       # restrict to one registered root
sh ~/.sc/list/action --match '<glob>'        # filter by skill DIRNAME glob (e.g. 's-*')
sh ~/.sc/list/action --match 're:<regex>'    # POSIX extended regex over dirname
sh ~/.sc/list/action --names-only            # emit just the frontmatter `name:` per line
sh ~/.sc/list/action --count                 # print total count and exit
```

Flags compose: `sh ~/.sc/list/action --root /Users/me/Projects/my-skills --match 's-*' --format tsv`.

## Output formats

- **text** (default) — aligned table grouped by root:

  ```
  /Users/me/Projects/my-skills (5 skills)
    s:audit                Audit all plans, CLAUDE.md files, Mermaid diagrams, …
             → /Users/me/Projects/my-skills/s-audit
    s:commit               Review all changes, generate commit message, …
             → /Users/me/Projects/my-skills/s-commit
    …

  /Users/me/Projects/skill-core/sc (3 skills)
    sc:crud                Create, update, or import a skill. …
             → /Users/me/Projects/skill-core/sc/crud
    …

  total: 8 skill(s) across 2 root(s)
  ```

- **tsv** — one row per skill: `name<TAB>dirname<TAB>description<TAB>path<TAB>root`. Stable column order; safe to pipe to `awk`, `cut`, etc.

- **json** — `{"results":[{"name":..., "dirname":..., "description":..., "path":..., "root":...}, ...], "count": N}`. Hand-rolled (no jq dependency).

## Exit codes

| code | meaning                                              |
|------|------------------------------------------------------|
| 0    | listed at least one skill                            |
| 1    | no skills discovered (config valid but empty)        |
| 2    | config error (missing/invalid `~/.sc/repos.patterns`)|

## Implementation notes

- POSIX `sh` only, macOS-stock binaries (`awk`, `sed`, `find`, `sort`). No Python, no SQLite, no third-party tools — same constraint as `sc:search`.
- Reuses `~/.sc/lib/discover.sh` for skill discovery, frontmatter parsing, and root expansion — the action is a thin formatter on top of `sc_discover_skills`, `sc_fm_field`, `sc_parse_patterns`.
- No index, no cache — `sc:list` re-walks the filesystem each call. Fast for typical skill counts (~10²); if you regularly query a huge corpus, use `sc:search --format tsv` against the FTS5 index instead.

## When NOT to use sc:list

- The user is looking for a skill that *does X* — use `sc:search` (ranked, multi-axis).
- The user wants to create/edit/delete a skill — use `sc:crud`.
- The user wants config diagnostics (which roots are registered, are they valid) — use `sh ~/.sc/search/action list-roots` or `doctor`.

## Related

- `sc:search` — ranked multi-axis search over the same corpus.
- `sc:crud` — create / update / delete / import skills.
- `~/.sc/repos.patterns` — the source list `sc:list` walks.
- `~/.sc/lib/discover.sh` — shared helpers (frontmatter parsing, root expansion, skill discovery).

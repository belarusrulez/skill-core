# skill-core

**One skill to rule them all.** A tiny meta-skill system that indexes every skill folder you point it at and auto-finds the right one whenever your agent needs it. LLM-agnostic — works with anything that loads `SKILL.md` files (Claude Code, Cursor, you name it).

⭐ Star the repo if it saved you some pain. Open an issue if it glitches anywhere.

## TL;DR

You have skills / prompts / extensions scattered across folders. Half of them you didn't write, half you don't remember, none are searchable. skill-core registers exactly **two** skills with your agent and lets every other skill stay wherever you keep it — a git repo, a notes folder, anywhere on disk:

- **`sc:search`** — a multi-axis search that finds the right `SKILL.md` for what the user is trying to do, across every repo you've pointed it at.
- **`sc:crud`** — a procedural skill for creating, updating, deleting, and importing other skills.

`sc:search` returns the **full path** to the matching `SKILL.md`. The agent reads that file and follows it. No agent-side registration, no slash-command sprawl, no shadow registry — your skills are just files on disk.

## Why this exists

If you use more than one LLM coding tool, you've probably watched your agents' "skills" / "extensions" / "prompts" lists turn into a graveyard. Each tool wants its own registration layer, each one nags you for a fresh round of YAML, and over time you end up with dozens of half-working snippets cluttering whatever directory your agent reads from. Most of them you didn't write, most of them you don't remember, none of them are searchable.

skill-core throws that out. Two skills register with the agent. Everything else stays on disk and gets discovered by full-path lookup at the moment of need.

The search is intentionally simple: pass three queries (literal phrase, synonym/jargon, intent/goal), it merges them with Reciprocal Rank Fusion, and surfaces skills that match across multiple axes. The vocabulary mismatch between "how the user phrased it" and "how the skill author phrased it" is the main failure mode in agent skill discovery; three axes hedges against it cheaply.

## Install

Paste this into a fresh agent session:

> Bootstrap skill-core on this machine: ask the user where to clone `git@github.com:belarusrulez/skill-core.git` (suggest the directory where the LLM started as the default), then execute the steps under "Bootstrap on a fresh machine" in INSTALL.md in order. In steps 5 and 6 you register the two bootstrap skills with your harness — use whatever mechanism your harness expects for installing a skill from a SKILL.md file; you know how. In step 9 you install the task-intake global rule into the harness's global rules file. After step 8, confirm `sc:search` and `sc:crud` are registered; after step 9, confirm the task-intake rule is in place. Do not commit anything.

See [INSTALL.md](INSTALL.md) for the annotated walkthrough with rationale, the full layout diagram, and notes on each step.

## Uninstall

Paste this into an agent session:

> Uninstall skill-core on this machine: unregister `sc:search` and `sc:crud` from your harness — use whatever mechanism your harness expects to remove a skill from a SKILL.md registration; you know how. Then remove the runtime tree: `rm -rf ~/.sc/`. The cloned source repo is left alone — ask me whether to delete it too before doing so. Source repos listed in `~/.sc/repos.patterns` are not touched at any point; only the runtime state and the two harness entries go away.

## Day-to-day usage

When the user asks "do I have a skill for X", invoke `sc:search` with three queries:

```sh
sh ~/.sc/search/action "<literal phrase>" "<synonym/jargon>" "<intent/goal>"
```

Results include a `→ <full path>` line under each hit. Read the `SKILL.md` at that path and follow its instructions.

To add, edit, delete, or import skills, use `sc:crud` (see `sc/crud/SKILL.md`).

## Requirements

- **macOS** — the only platform this has been tested on so far. Everything in the bootstrap (`/bin/sh`, `sqlite3`, `find`, `grep`, `awk`, `sed`, `readlink`, `ln -s`, `mktemp`) is preinstalled on macOS 14+.
- **Linux** — should work out of the box; the script is POSIX `sh` + standard coreutils, all of which Linux distros ship. Requires `sqlite3` ≥ 3.20 for FTS5 (Ubuntu 18.04+, Debian 10+, and equivalents). Untested in CI — if you hit a portability bug, open an issue.
- **Windows** — port in development. The current shell-only implementation won't run natively; for now use WSL or wait for the Windows-friendly version.
- An agent that loads skills from a per-skill `SKILL.md` file.

## Repo layout

| Path | What |
|---|---|
| `sc/search/action` | The only shell CLI — search, reindex, list-roots, doctor |
| `sc/search/SKILL.md` | `sc:search` skill doc (loaded by the agent) |
| `sc/crud/SKILL.md` | `sc:crud` procedural skill doc (no CLI) |
| `sc/lib/discover.sh` | Shared shell helpers |
| `test/run-tests.sh` | Test harness |
| `INSTALL.md` | Detailed bootstrap walkthrough |
| `docs/architecture.mmd` | Architecture diagram |

## Contributing

Star the repo, open issues for glitches, send PRs for fixes. Skills you write are yours — they don't live in this repo, they live wherever you keep them. skill-core just finds them.

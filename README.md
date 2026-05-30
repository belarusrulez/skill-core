# skill-core

**One skill to rule them all.** (Plus a few helpers, working in service of one idea.) `skill-core` registers a small set of meta-skills shipped under `sc/` — `sc:search`, `sc:list`, `sc:crud` today; the installer picks up whatever's there — with your agent. Every other `SKILL.md` stays as a plain file in your filesystem, and any agent that reads SKILL.md (Claude Code, Cursor, anything else) can use them. No daemon, no reindex, no doctor command.

> ![asciinema demo — sc:search finding a SKILL.md in <2 sec](./docs/demo.gif)
> *Add a file, findable. Delete a file, gone.*

⭐ Star the repo if it saved you some pain. Open an issue if it glitches anywhere.

## TL;DR

You have skills / prompts / extensions scattered across folders. Half of them you didn't write, half you don't remember, none are searchable. skill-core registers a small set of meta-skills with your agent (auto-discovered from the `sc/` folder — currently three) and lets every other skill stay wherever you keep it — a git repo, a notes folder, anywhere on disk:

- **`sc:search`** — *ranked fuzzy retrieval.* A multi-axis search that finds the right `SKILL.md` for what the user is trying to do, across every repo you've pointed it at. *"I need a skill for X."*
- **`sc:list`** — *flat catalog.* A complete, deterministic inventory of every registered skill — the catalog view; `sc:search` is the ranked view. *"What do I even have?"*
- **`sc:crud`** — *managing the skills themselves.* A procedural skill for creating, updating, deleting, and importing other skills.

## Why this exists

If you use more than one coding agent — Claude Code, Cursor, Cline, whatever's next — you've probably watched your agents' "skills" / "extensions" / "rules" lists turn into a graveyard. Each tool wants its own registration layer in its own folder with its own conventions, each one nags you for a fresh round of YAML, and over time you end up with dozens of half-working snippets cluttering whatever directory your agent reads from. Most of them you didn't write, most of them you don't remember, none of them are searchable.

skill-core throws that out. A small set of meta-skills register with the agent (every `SKILL.md` shipped under `sc/`). Everything else stays on disk and gets discovered by full-path lookup at the moment of need. **Skills live in *your* filesystem, in a vendor-neutral location** — not in `~/.claude/skills/`, not in `.cursor/rules/`, not in any tool's proprietary store. Switch from Claude Code to Cursor and your skills come with you. Same files, same skills, different harness.

The search is intentionally simple. The user describes their task in one vocabulary; the skill author wrote the description in another. *Skill named "Extract structured data from PDFs"; user says "pull tables out of this report."* Same task, zero shared keywords. This is the vocabulary-mismatch problem from classical information retrieval. Embeddings solve it expensively — model dependency, an index that needs rebuilding, opacity. skill-core solves it cheaply: ask the LLM to expand the query into three axes (literal phrase, synonym/jargon, intent/goal), run each as a full-text search, and merge the rankings with Reciprocal Rank Fusion. The skill that ranks middling on all three axes beats the skill that ranks #1 on one and is absent on the others. That's exactly the robustness property you want.

## Install

Paste this into a fresh agent session:

> Bootstrap skill-core on this machine: ask the user where to clone `git@github.com:belarusrulez/skill-core.git` (suggest the directory where the LLM started as the default), then execute the steps under "Bootstrap on a fresh machine" in INSTALL.md in order. In step 5 you register every SKILL.md found under `$REPO/sc/` with your harness — discover them with `find "$REPO/sc" -mindepth 2 -maxdepth 2 -name SKILL.md`, then register each one the same way your harness expects (you know how). In step 8 you install the task-intake global rule into the harness's global rules file. After step 7, confirm which skills got registered (list them by frontmatter `name:`); after step 8, confirm the task-intake rule is in place. Do not commit anything.

See [INSTALL.md](INSTALL.md) for the annotated walkthrough with rationale, the full layout diagram, and notes on each step.

## Uninstall

Paste this into an agent session:

> Uninstall skill-core on this machine — do every step without asking for confirmation. (1) Unregister every skill the installer added from `$REPO/sc/`: discover them the same way the installer did (`find "$REPO/sc" -mindepth 2 -maxdepth 2 -name SKILL.md`), then remove each via your harness's mechanism. (2) Remove the task-intake rule the installer added (reverse of install step 8): delete the `## Task intake` block from your harness's global rules file — resolve the path first (it may be a symlink; edit the real target). (3) Remove the runtime tree: `rm -rf ~/.sc/`. Leave the cloned source repo on disk and do NOT ask about deleting it — print its path and one line telling me to `rm -rf` it myself if I want the source gone. Source repos listed in `~/.sc/repos.patterns` are never touched; only the runtime state, the harness skill entries, and the task-intake rule go away.

## Day-to-day usage

If you know some skill is needed just include `sc:search` in your prompt. Also if your llm thinks that some new skill is needed it will search by itself well. 

## Requirements

- **macOS** — verified working. Everything in the bootstrap (`/bin/sh`, `sqlite3`, `find`, `grep`, `awk`, `sed`, `readlink`, `ln -s`, `mktemp`) is preinstalled on macOS 14+.
- **Linux** — works on standard distros. POSIX `sh` + standard coreutils. Requires `sqlite3` ≥ 3.20 for FTS5 (Ubuntu 18.04+, Debian 10+, and equivalents). If you hit a portability bug, open an issue.
- **Windows** — native port in development. The current shell-only implementation won't run natively; for now use WSL.
- An agent that loads skills from a per-skill `SKILL.md` file (Claude Code, Cursor, Cline, anything compatible).


## License

MIT. See [LICENSE](LICENSE).
---
name: create-warm-worktree
description: Use when Dave needs a new semi-permanent "warm" Omnibus git worktree under ~/source/repos/<slug> (a parallel work area he keeps and recycles), with its matching home-dir Claude launcher (~/<slug>.sh), dev-stack startup script (~/start-omni-<slug>.sh), and between-sessions reset helper (~/reset-omni-<slug>.sh). Triggers on "make a new warm worktree", "I need another worktree called X", "new area worktree", "set up a parallel work area modeled on the existing ones".
---

# Create a Warm Worktree

## Overview

Dave keeps a handful of long-lived per-area worktrees under `~/source/repos/` (e.g. `assets`, `subrights`, `title-manager`) and recycles branches inside them rather than tearing them down. Each one is a **multi-repo work area** plus two home-dir scripts. This skill creates a new one faithfully.

**The whole thing is mechanical — run the bundled script:**

```bash
~/.claude/skills/create-warm-worktree/create-warm-worktree.sh <slug>
```

Read the rest of this file to understand what it does and to recover if it fails. The slow step is `npm install` (~1.8 GB `node_modules`); the whole run is a few minutes.

## What a warm worktree IS (the current shape)

`~/source/repos/<slug>/` contains git worktrees of **five repos**, all on a recyclable placeholder branch `feature/<slug>-wt`, plus a sentinel and a flattened workspace file:

```text
~/source/repos/<slug>/
├── .cc-keep-worktree                      # sentinel: keep this worktree across /work-finish
├── CLAUDE.md                              # GENERATED port context — auto-loaded by every Claude
│                                          #   session started here (this dir is cwd via ~/<slug>.sh).
│                                          #   Outside every repo, so structurally un-committable.
├── .claude/skills/                                                 # per-skill symlinks, BOTH sources (see below)
├── Treeline.Omnibus.code-workspace        # FLATTENED variant (./ sibling paths)
├── Treeline.Clients.EdelweissComponents/  # worktree off release
├── Treeline.Data/                         # worktree off release
├── Treeline.Services.Omnibus/             # worktree off release
├── Treeline.Services.Ingest/              # worktree off release
└── Treeline.Workspaces/                   # worktree off main   ← the one people forget
```

Plus three scripts in `$HOME`:
- `~/<slug>.sh` — tiny launcher: `cd` into the worktree root, `exec claude -c "$@"`.
- `~/start-omni-<slug>.sh` — brings up the full local dev stack (Omnibus + Ingest, BE + FE).
- `~/reset-omni-<slug>.sh` — between-sessions reset (thin wrapper over the shared `~/reset-omni.sh`).

### The area-root `CLAUDE.md` (how a session knows its ports)

`~/source/repos/<slug>/CLAUDE.md` is **generated** by `~/omni-configure-area.sh` from the port
table, and is the mechanism by which both Dave and Claude know which ports an area owns.

- `~/<slug>.sh` cd's into the area root before `exec claude`, so that directory is cwd at session
  start — the primary place Claude Code discovers `CLAUDE.md`. It loads with no hook or skill.
- The area root is **not inside any git repository** (every repo's toplevel is a *subdirectory* of
  it, and there is no `.git` at or above the area root). git cannot stage a path above its own
  toplevel, so this file is structurally un-committable: `git add ../CLAUDE.md` fails with
  *"outside repository"* and `git add -A` from a repo root never sees it. No `.gitignore` entry is
  needed or possible.
- Only the `<!-- BEGIN omni-ports -->` / `<!-- END omni-ports -->` block is rewritten, so
  hand-written content in the file survives (`omnibus1` carries an ADO identity section above it).
- Because it is generated from `~/omni-ports.sh` on every configure run, it **cannot drift** from
  the real table. Do not hand-edit the block, and do not copy the port numbers into a memory entry —
  that would create a second source of truth that goes stale silently.
- `~/<slug>.sh` also prints the block to the terminal before starting claude, so the ports are
  visible to Dave as well as to the assistant.

And one shared, area-agnostic script in `$HOME`:
- `~/reset-omni.sh` — the canonical reset logic (`reset-omni.sh <slug>`); each area's `~/reset-omni-<slug>.sh` just `exec`s it with its slug. Installed/refreshed from the bundled `reset-omni.sh` template on every run.
- `~/omni-ports.sh` — the slug → dev-port-block table plus the `omni_ports <slug>` resolver. Sourced by every `start-omni-<slug>.sh`. Append-only: existing areas keep their offsets so the ports already written into their gitignored config stay valid.
- `~/omni-configure-area.sh` — materializes one area's ports onto disk (`omni-configure-area.sh <slug>`): jq-patches both `appsettings.Local.json` files (Kestrel URLs + CORS origins), rewrites both `.env.development.local` files, and generates `vite.config.local.mts`. Called by each start script after its seed step; idempotent and safe to run standalone.

### The reset helper (why it exists)

A warm worktree is a **linked** worktree, so it can never rest *on* `release` — the main
checkout at `~/projects/omnibus` holds that branch, and git forbids the same branch in two
worktrees. After a session's PRs merge, each repo is therefore stuck on its now-merged
`feature/...` branch, which confuses the *next* session into thinking there's live work.

`reset-omni.sh` fixes that: for every repo in the area it leaves HEAD **detached at the
repo's own `origin/<default>`** tip. By default it deletes **only the branch that repo was
sitting on** (when merged) — nothing else. Repos with uncommitted **tracked** changes are
skipped untouched, so in-flight work is never clobbered; untracked scratch files are
preserved. The next `/work-start` cuts a fresh branch from `origin/<default>` regardless.

**Why the delete scope is narrow — worktrees share one branch namespace.** All of a repo's
worktrees (every area + the main checkout) share the same `refs/heads`, so `git branch -D`
from one area removes the branch for *all* of them. A per-area reset therefore deletes only
the branch that area was on. Pass **`--prune-merged`** to additionally delete *every* local
branch merged into `origin/<default>` (a repo-wide declutter — opt in deliberately). Git
still refuses to delete a branch checked out in any worktree, so an active area is never
broken either way.

Run it between sessions: `~/reset-omni-<slug>.sh` (or `~/reset-omni.sh <slug>`, or just
`~/reset-omni.sh` from inside the area; add `--prune-merged` for the broad clean). It is the
warm-worktree counterpart to `/cc:git-cleanup`, which can't switch these worktrees to
`release` for the reason above.

And one entry in a **shared** VS Code config (outside any worktree):
- `~/source/repos/.vscode/sessions.json` — the [Terminal Keeper](https://marketplace.visualstudio.com/items?itemName=nguyenngoclong.terminal-keeper) config. One terminal per area under `sessions.default`, each `cd`-ing into the area root and running `claude -c`. The script appends the new area's entry so it shows up as a restorable VS Code terminal.

## Non-obvious points (the judgment calls the script encodes)

| Point | Why it matters |
|---|---|
| **Five repos, including `Treeline.Workspaces`** | Older worktrees (`title-manager`, `quickfix`) only had four — that was the **stale** pattern and caused doc/skill/CLAUDE.md drift because the workspace repo wasn't editable in-tree. Always include all five. (All existing areas were retrofitted to five repos on 2026-07-27.) |
| **`.claude/skills` as a merged directory at the area root** | Claude Code discovers project skills only at cwd and its **parents**, never in subdirectories. Two skill sets matter — the workspace repo's (`Treeline.Workspaces/Omnibus/.claude/skills`) *and the frontend repo's* (`Treeline.Clients.EdelweissComponents/.claude/skills`, which holds the `omnibus-publisher-ui` and `publisher-landing-design` design charters). A single symlink to one of them hides the other, which is how the marketing charter got missed for an entire feature build. **The create script does this automatically in step 2b** by calling `~/sync-omni-skills.sh <slug>`, which builds a real directory of per-skill symlinks into both repos; `~/reset-omni.sh` re-runs it after its checkouts, since a branch change can add or remove a skill. If that script is missing, create falls back to the old workspace-only symlink and warns loudly. Verified: the resolver follows symlinked skill dirs. The area root is not a git repo, so none of this is tracked. |
| **Base branch differs per repo** | The four code repos branch from `release`; `Treeline.Workspaces` branches from `main` (its default). Do not branch all five from `release`. |
| **The root workspace file is the FLATTENED variant** | `~/source/repos/<slug>/Treeline.Omnibus.code-workspace` uses `./Treeline.*` sibling paths and is **not** the same file as `Treeline.Workspaces/Omnibus/Treeline.Omnibus.code-workspace` (which uses `../../`). Copy it from another warm-worktree **root**, never from the repo subdir. |
| **`mise trust` before `mise install`** | A fresh worktree's `mise.toml` is untrusted, so `mise install` aborts until you `mise trust ./mise.toml`. |
| **Seed gitignored config** | `.env.development.local`, `appsettings.Local.json`, `local.settings.json`, `.claude/settings.local.json` are gitignored — a fresh worktree lacks them. The script copies whatever each repo's `.worktreeinclude` declares. |
| **Ingest settings are seeded at dev-stack start, not at creation** | `Treeline.Services.Ingest` has no `.worktreeinclude`; `start-omni-<slug>.sh` seeds its `appsettings.Local.json` (and re-seeds Omnibus certs/appsettings) on first run, so those self-heal. |
| **Every area has its OWN port block** | Ports live in the shared table `~/omni-ports.sh`, keyed by area directory name, offset 10 per area (`quickfix` = 90 → UI 3090 / API 5090+5091 / Ingest 5092 / Ingest UI 3091). The main checkout keeps offset 0 (3000/5000/5001/5002/3001). Several stacks run side by side, and `free_ports` only touches the area's own five ports. The creation script allocates the next free block automatically; `~/omni-configure-area.sh <slug>` writes it into the area's gitignored `appsettings.Local.json` / `.env.development.local` and generates its git-excluded `vite.config.local.mts` (needed because `vite.config.mts` pins `hmr.port` to 3000 whenever mkcert certs are present), including a same-origin proxy (`/ext/common`, and `/ext/search` for the omnibus app) — the external Edelweiss common API allowlists only `:3000`/`:3001`, so a moved frontend can't reach it directly and the login gate would 401 without the proxy. |
| **Offset 60 is permanently reserved — never allocate it** | It maps to API ports 5060/5061, the SIP ports, which sit on Chromium's `kRestrictedPorts` list (`net/base/port_util.cc`). The server binds them and `curl` reaches them fine — the failure is **browser-only**: every fetch fails with `net::ERR_UNSAFE_PORT`, so a stack on offset 60 looks completely healthy from the shell. `quickfix` was moved from 60 to 90 after hitting this live. `omni_ports()` in `~/omni-ports.sh` now guards against it — it checks every resolved port against `OMNI_BLOCKED_PORTS` and returns exit code `3` with an explanatory message if any of them is blocked — and the allocation block below skips past any blocked offset automatically, so this can't silently recur when a new area is created. |
| **The Omnibus API hot-rebinds ports; the Ingest API does not** | Rewriting `appsettings.Local.json` makes Kestrel move endpoints with no restart (observed verbatim: `Config changed. Stopping the following endpoints: 'http://+:5060', 'https://+:5061'` then `Config changed. Starting the following endpoints: 'http://+:5090', 'https://+:5091'`); Vite likewise self-restarts on a config change and picks up a new `VITE_DEV_PORT`. The Ingest API's port, by contrast, arrives as a fixed `--urls` command-line argument at launch — a port reassignment strands the old process on its old port, and `free_ports` won't reclaim it because it's no longer in the area's block. It has to be killed explicitly or the stack restarted. |
| **`.cc-keep-worktree` is currently inert** | The `/work-finish` change that honors it hasn't shipped (see the sentinel's own note), but every area carries it for forward-compat. |
| **Terminal Keeper registration lives OUTSIDE the worktree** | `~/source/repos/.vscode/sessions.json` is shared across every area (it belongs to the `~/source/repos` folder VS Code opens), not to the new worktree. The script edits it in place with `jq --indent 4`, appending one `sessions.default` entry. It's the easiest step to forget by hand — `subrights` drifted out of the file exactly this way (worktree on disk, no terminal). Idempotent + non-fatal: skips if the slug is already there, warns (doesn't abort) if `jq` is missing or the file is absent. |
| **Icon/color for the new entry** | Default icon `git-branch`; color auto-rotates to the first `terminal.ansi*` not already used by another area (keeps them visually distinct). Override either with `TK_ICON=<codicon-id>` / `TK_COLOR=terminal.ansi<Name>` env vars before running. Existing areas use hand-picked *semantic* icons (book=CatalogManager, file-media=assets, cloud-download=ingest, lightbulb=quickfix, tag=title-manager) — set `TK_ICON` if you want to match that spirit. |

## Renaming or resetting an existing area

Don't re-create an area to change its name — `rename-warm-worktree` moves all nine
slug-bearing artifacts together in seconds and keeps the branches, the port block, and
the 1.8 GB `node_modules`. `reset-warm-worktree` owns the between-sessions reset.

## Relationship to `/cc:worktree`

`/cc:worktree` creates worktrees and runs the `.worktreeinclude`/`.worktreesetup` machinery, but it does **not** create the home-dir launcher, the `start-omni-<slug>.sh` dev-stack script, the `.cc-keep-worktree` sentinel, the flattened root workspace file, or the Terminal Keeper `sessions.json` entry — and it won't guarantee the 5-repo set on `feature/<slug>-wt`. This skill's script does the whole warm-worktree shape end to end. Prefer the script.

## After it finishes

The script prints a verification block (per-repo branch, workspace file, sentinel, `node_modules` size, the launcher / dev-stack / reset script paths, whether the Terminal Keeper entry registered, and a diff of the new dev-stack script against its template showing only slug-bearing lines changed). To launch the area: `~/<slug>.sh`. To bring up the stack: `~/start-omni-<slug>.sh`. To reset the area between sessions: `~/reset-omni-<slug>.sh`. The new VS Code terminal appears the next time Terminal Keeper activates the `default` session (reload the window, or run the area immediately via `~/<slug>.sh`).

## Common mistakes

- **Modeling on `title-manager`/`quickfix`** (4-repo, stale) instead of `subrights`/`assets` (5-repo, current).
- **Copying the workspace file from the repo's `Omnibus/` subdir** (wrong `../../` paths) instead of a warm-worktree root.
- **Branching `Treeline.Workspaces` from `release`** — it has no `release`; use `main`.
- **Running `mise install` before `mise trust`** — it fails.
- **Forgetting `.env.development.local`** — the Omnibus UI then can't find the API; the dev-stack script does not seed this one (only certs/appsettings), so creation-time seeding is required.
- **Forgetting the Terminal Keeper entry** — the script now does it, but if you create an area by hand (or `jq` was missing during the run), the area won't show as a VS Code terminal. Add it to `~/source/repos/.vscode/sessions.json` under `sessions.default`.

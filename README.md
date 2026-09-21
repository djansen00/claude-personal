# claude-personal

Dave's personal Claude Code skills and the home-dir scripts they drive. Private by
intent — see *Visibility* below.

## Restore on a new machine

```bash
git clone https://github.com/djansen00/claude-personal.git ~/projects/claude-personal
cd ~/projects/claude-personal
./install.sh --check      # see what it would do
./install.sh              # symlink skills into ~/.claude/skills and scripts into $HOME
```

Then recreate each warm worktree area you want:

```bash
~/.claude/skills/create-warm-worktree/create-warm-worktree.sh <slug>
```

## Details

### What's here

| Path | What | Installed as |
|---|---|---|
| `skills/` | 8 personal Claude Code skills | symlinks in `~/.claude/skills/` |
| `bin/` | the 6 **shared** scripts the skills drive | symlinks in `$HOME` |
| `bin/areas/` | per-area generated scripts (`<slug>.sh`, `start-omni-<slug>.sh`, `reset-omni-<slug>.sh`) | **not installed** by default — snapshot only |

### Why the scripts are here, not just the skills

The warm-worktree skills are documentation wrapping real implementations. `reset-warm-worktree`
says outright: *"The logic already exists and is battle-tested. Do not reimplement it"* — and
points at `~/reset-omni.sh`. A backup of `skills/` alone would restore a set of pointers to code
that isn't on the machine. `bin/` is the code.

`bin/omni-ports.sh` is the **source of truth for every area's dev-port block**. Losing it means
losing the mapping that the already-written `appsettings.Local.json` CORS origins and
`.env.development.local` files depend on.

### Why symlinks, not copies

With symlinks, `git status` in this repo is the truth about what has drifted, and an edit made
anywhere is already staged for commit. Copies reintroduce the sync problem the repo exists to
solve. `install.sh --copy` exists for a machine where symlinks are awkward; prefer not to use it.

Claude Code's skill resolver follows symlinked skill directories — the same mechanism
`sync-omni-skills.sh` already relies on to merge two skill sets into each warm area.

### Why `bin/areas/` is a snapshot and not installed

Those scripts are *generated* per machine by `create-warm-worktree`, then edited in place over
time — `start-omni-assets.sh` has drifted ~1.7K past its siblings. Symlinking them would let one
machine's areas overwrite another's. They are kept so hand-edits are recoverable, and restored
only with `install.sh --areas`, which copies and never overwrites.

### Why this repo is NOT `~/.claude` itself

`~/.claude/` holds live credentials — `edelweiss-creds.json` (mode 600), `cc-defaults.json`,
`stats-cache.json`. Making that directory a git repo puts one careless `git add -A` between you
and publishing your Edelweiss login. A separate directory removes the whole class of accident
rather than relying on `.gitignore` discipline.

### Visibility

**Keep this repo private.** There are no credentials in it — but there are Application Insights
App ID GUIDs, `atl-sqlmi-01`, `treeline-omnibus-sql`, and `treeline-ingest-sql`. That's internal
infrastructure topology, not something to publish.

### Relationship to the `cc` framework

Different things. `cc` (`Treeline.AI.Claude` on AzDO, mirrored to GitHub) is the **org** plugin
everyone installs, and has a hard version-bump rule on every commit. This repo is **personal** —
nobody else uses warm worktrees — and has no version discipline. Don't move skills between them
without deciding which audience they serve.

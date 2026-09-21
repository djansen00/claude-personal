---
name: reset-warm-worktree
description: Use INSTEAD OF /cc:git-cleanup when finishing work inside one of Dave's warm worktree areas under ~/source/repos/<slug> (omnibus1, omnibus2, assets, subrights, ingest, quickfix, title-manager, CatalogManager). /cc:git-cleanup CANNOT work there — it tries to `git checkout release`, which git refuses because the main checkout at ~/projects/omnibus already holds that branch, and the failure is silent-then-destructive. Triggers on "git cleanup", "clean up the repos", "switch back to release", "reset the worktree", "done with this area", "get ready for the next card", or any post-/work-finish tidy-up while cwd is under ~/source/repos/<slug>.
---

# Reset a Warm Worktree (the /cc:git-cleanup replacement for warm areas)

## Use this, not `/cc:git-cleanup`

`/cc:git-cleanup` assumes one checkout per repo: *switch to the default branch, pull, delete the
feature branch*. That assumption is false in a warm worktree.

A warm area (`~/source/repos/<slug>/`) is made of **linked** git worktrees. The **main** checkout
at `~/projects/omnibus` holds `release`, and **git allows a branch in only one worktree at a
time** — so a warm area can *never* rest on `release`. `git checkout release` there always fails:

```
fatal: 'release' is already used by worktree at '/home/djansen/projects/omnibus/Treeline.Services.Omnibus'
```

The resting state for a warm area is therefore **detached HEAD at `origin/<default>`**. That is
what `~/reset-omni.sh` produces, and it is already the documented counterpart to
`/cc:git-cleanup` — see the `create-warm-worktree` skill.

## The command

The logic already exists and is battle-tested. **Do not reimplement it.**

```bash
~/reset-omni.sh                      # auto-detects the area from cwd
~/reset-omni.sh omnibus1             # or name the slug
~/reset-omni.sh omnibus1 --prune-merged   # opt-in repo-wide branch declutter
~/reset-omni-<slug>.sh               # per-area wrapper (exec's the above)
```

Run it from anywhere; with no argument it resolves the area from `$PWD` when that is under
`~/source/repos/<slug>/`. Reads `--help` for the full contract.

## What it guarantees (why it's safe to just run)

| Guarantee | Detail |
|---|---|
| **Per-repo default branch** | Resolves each repo's own `origin/HEAD`. The four code repos → `release`; **`Treeline.Workspaces` → `main`**. Never hardcode `release` across all repos. |
| **Dirty repos are skipped untouched** | A repo with uncommitted **tracked** changes is reported `SKIP` and left exactly as-is. In-flight work is never clobbered. |
| **Untracked files survive** | Scratch files, `docs/temp/` proposals, local notes — all preserved. |
| **Only merged branches deleted** | A branch is deleted only when provably `merge-base --is-ancestor` of `origin/<default>`. Unmerged branches are kept and reported as `kept (unmerged)`. |
| **Narrow delete scope by default** | Deletes **only the branch that repo was sitting on**. See the namespace warning below. |
| **The area's port config survives** | `appsettings.Local.json`, both `.env.development.local` files and both generated `vite.config.local.mts` shims are gitignored or git-excluded, so the reset never touches them. The area-root `CLAUDE.md` sits *outside* every repo entirely and is likewise untouched. An area keeps its port block across resets — you do **not** need to re-run `~/omni-configure-area.sh` (the start script does it anyway). |
| **Stale cc session state cleared** | Deletes `.claude/work-sessions/state/current-work.json` when its `.branch` no longer exists locally. Keeps it (and says so) when the branch survived as unmerged, so a resumable session is never eaten. Added 2026-09-01 — see the statusline note below. |
| **Idempotent** | Running it on an already-reset area is a harmless no-op. |
| **Non-zero exit on skips** | `rc=1` when any repo was skipped, so you notice rather than assume success. |

## ⚠️ Worktrees share ONE branch namespace — mind `--prune-merged`

Every worktree of a repo (all areas **plus** the main checkout) shares the same `refs/heads`.
Deleting a branch from one area deletes it **everywhere**. That is why the default scope is just
the one branch this area was on.

`--prune-merged` deletes *every* local branch merged into `origin/<default>`, repo-wide across all
worktrees. It is a legitimate declutter, but it reaches outside this area — **only pass it when
Dave asks for the broad clean**, and say so when you do. Git still refuses to delete a branch
checked out in any worktree, so an active area can't be broken either way.

## Verification after running

```bash
cd ~/source/repos/<slug>
for d in */; do
  git -C "$d" rev-parse --is-inside-work-tree >/dev/null 2>&1 || continue
  printf '  %-40s %-14s dirty=%s\n' "${d%/}" \
    "$(git -C "$d" rev-parse --abbrev-ref HEAD)" \
    "$(git -C "$d" status --porcelain | wc -l)"
done
```

Expect `HEAD` (detached) for every code repo, `dirty=0`, and no stale session branches
(`git branch --list 'story/*' 'feature/ATL*' 'defect/*'`).

## It also re-syncs the area's project skills

After the checkouts, the script runs `~/sync-omni-skills.sh <slug>`. This matters because a
warm area's `.claude/skills` is a **merged directory** of per-skill symlinks pointing into two
repos — the workspace repo *and* `Treeline.Clients.EdelweissComponents`, which holds the UI
design charters (`omnibus-publisher-ui`, and `publisher-landing-design` on the publisher-pages
line of work).

Detaching to `origin/<default>` changes which of those skills exist on disk. Without the
re-sync you get dangling symlinks for skills the new branch does not have, and you silently
miss skills it added. The sync prunes and rebuilds, and is idempotent.

Nothing here touches git: the area root sits outside every repo.

If you see `NOTE: ~/sync-omni-skills.sh not found`, the area's skill list is stale — restore the
script and run `~/sync-omni-skills.sh <slug>` by hand.

## Known scope boundary — `Treeline.Workspaces` is not reset

`reset-omni.sh` discovers repos via the same `workspace-repos.py` resolver the `/work-*` commands
use. In a 5-repo area that resolver returns **4** repos (it reads
`Treeline.Omnibus.code-workspace`; `Treeline.Workspaces` is the *meta*-repo, included only when
dirty). Because the resolver returns a non-empty list, the script's "every git dir" fallback never
fires — so **`Treeline.Workspaces` keeps sitting on `feature/<slug>-wt`.**

That is very likely **intentional**: `feature/<slug>-wt` is the area's recyclable placeholder
branch, and Workspaces never receives a per-card session branch (it is auto-included by
`/work-start` only when it has uncommitted changes). Leave it alone by default. Reset it by hand
only if Dave asks:

```bash
git -C ~/source/repos/<slug>/Treeline.Workspaces checkout --detach origin/main
```

Do not "fix" this in the script without checking with Dave first — the placeholder branch may be
load-bearing for how the area is recycled.

## Common mistakes

- **Running `/cc:git-cleanup` in a warm area.** It fails on `checkout release` in every repo. Use
  this skill instead.

- **The silent-then-destructive trap — the reason this skill exists.** Do **not** write a loop like:

  ```bash
  git -C "$r" checkout release        # FAILS in a warm worktree
  git -C "$r" pull origin release     # …but this still runs → merges release INTO the session branch
  ```

  With the checkout failed, the pull runs while still on the session branch and merges `release`
  into it. Observed live on 2026-07-28 in `omnibus1`: it happened to be a harmless fast-forward
  only because the session branch was already fully merged. Had it held unmerged work it would
  have created surprise merge commits on a branch about to be deleted. **Guard on checkout
  success, or better — just run `~/reset-omni.sh`, which never pulls at all.**

- **Forgetting that a long branch jump makes `node_modules` stale — the trap that follows a reset.**
  The reset checks out `origin/<default>`, which rewrites `package.json` and `package-lock.json`, but it
  does **not** touch `node_modules`. If the area was sitting far behind release, the frontend then fails
  at *runtime* with an unresolvable import rather than anything git-shaped:

  ```
  [plugin:vite:import-analysis] Failed to resolve import "@zxing/library" from "src/components/BarcodeScanner.tsx"
  ```

  Observed live on 2026-08-14 in `quickfix` after a reset off a branch **1375 commits** behind release:
  two declared packages (`@zxing/library`, `jest-junit`) were missing because `node_modules` was three
  weeks old. **After any reset that moves the branch a long way, run `npm install` at the
  EdelweissComponents repo root before starting the dev stack.** Confirm with:

  ```bash
  cd ~/source/repos/<slug>/Treeline.Clients.EdelweissComponents
  stat -c '%y %n' package-lock.json node_modules   # lockfile newer than node_modules => install
  npm install
  ```

  A related symptom on the backend half: an EF model that maps a column production no longer has, e.g.
  `SqlException: Invalid column name 'As2Identity'` from `UserClaimsEnrichmentService`, producing 500s on
  `/api/organizations` and `/api/vendors/is-vendor`. That is the *same* root cause — stale code, not a
  database or config problem — and the reset is the fix, not a reason to go hunting in `appsettings`.

- **Assuming a clean statusline means a clean area — the 2026-09-01 trap.** The cc framework marks a
  session ACTIVE by the mere *presence* of `.claude/work-sessions/state/current-work.json`, and the
  statusline renders that file's `.branch` as its primary `@ <branch>` chip. Those files are
  **gitignored**, so no amount of git resetting clears them. Before the fix, a fully reset area showed:

  ```
  @ feature/journey-goal-move-contents  ! cwd:detached   feature-journey-goal-move-contents
  ```

  when git was clean and detached the whole time. The only hint was the small red `!` and `cwd:detached`.
  The same stale file also silently narrows the reset itself: `workspace-repos.py` prefers the state
  file's `repositories[]` array over the `*.code-workspace` scan, so a 2-repo session makes
  `reset-omni.sh` report "Repos: 2" and skip the area's other repos entirely — leaving them on the old
  session branch. That is **not** a resolver bug; do not go looking for one. A correct reset now prints
  `@ detached` + `No Work Session`.

- **Do not read the statusline as a dirty/clean indicator unless the dirty patch is applied.** The
  framework's bundled `statusline-script.sh` has *no* uncommitted-change check at all. A `● N dirty`
  chip was added 2026-09-01, but it lives in the **plugin cache**, so a cc plugin upgrade wipes it with
  no error — the chip just stops appearing. Re-apply with `~/reapply-statusline-dirty-patch.sh`
  (idempotent) after any cc update.

- **Hardcoding `release` for all repos.** `Treeline.Workspaces` has no `release` branch; its
  default is `main`. Always resolve `origin/HEAD` per repo.

- **Reaching for `git branch -D` because `-d` refused.** In a warm area `-d` frequently refuses
  with *"not yet merged to refs/remotes/origin/<branch>"* — git is comparing against the branch's
  **upstream**, not against `release`. Before forcing, prove nothing is lost:

  ```bash
  git -C "$r" log --oneline origin/release..<branch> | wc -l   # 0 = every commit is in release
  ```

  `reset-omni.sh` already does this check for you (`merge-base --is-ancestor`), which is the
  better reason to use it.

- **Assuming the area is idle because HEAD looks detached.** Check `git status --porcelain` too —
  a detached HEAD with uncommitted changes is a `SKIP`, not a clean area.

## Relationship to the other worktree skills

| Skill / script | Job |
|---|---|
| `create-warm-worktree` | Creates a new area (5 repos + launcher + dev-stack + reset wrapper + Terminal Keeper entry). |
| **this skill** | Resets an existing area to the between-sessions resting state. |
| `rename-warm-worktree` | Renames an existing area — directory, worktree links, the three home scripts, the port-table key, and the Terminal Keeper terminal, together. |
| `~/reset-omni.sh` | The implementation this skill wraps. Area-agnostic; takes a slug or path. |
| `/cc:git-cleanup` | The upstream framework command. Correct for **normal single-checkout repos**, wrong for warm areas. |
| `/cc:worktree` | Creates throwaway per-card worktrees — a different thing from a warm area. |

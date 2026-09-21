#!/usr/bin/env bash
# reset-omni.sh — reset a warm Omnibus worktree area to a clean between-sessions state.
#
# Each participating repo is left in DETACHED HEAD at its own origin/<default> tip.
# This clears the "stuck on the old, already-merged session branch" confusion that
# warm (linked) worktrees hit — because `release` is checked out in the MAIN worktree,
# a linked worktree can never rest *on* release, so we rest detached at the release
# commit instead. The next `/work-start` cuts a fresh branch from origin/<default>.
#
# BRANCH DELETION SCOPE:
#   Default  — delete ONLY the branch each repo was sitting on (the one we just
#              detached from), and only if it is merged into origin/<default>.
#              All other branches are left alone. This matters because git worktrees
#              SHARE one branch namespace: deleting a branch here removes it for every
#              worktree of the same repo, so a per-area reset must not reach beyond the
#              branch this area was actually on.
#   --prune-merged — additionally delete EVERY local branch merged into
#              origin/<default> (repo-wide cleanup across all worktrees). Opt-in only.
#
# SAFE BY DESIGN:
#   - A repo with uncommitted TRACKED changes is SKIPPED untouched (never clobbered).
#   - Only branches provably merged into origin/<default> are deleted -- either as a
#     literal ancestor, or via an Azure DevOps squash-merge PR commit naming them
#     as the source (see branch_is_merged). Unmerged
#     branches are kept and reported. (git also refuses to delete a branch that is
#     checked out in any worktree, so an active area is never broken.)
#   - Untracked files (e.g. local scratch/proposals) are preserved.
#
# Usage:
#   reset-omni.sh [slug|path] [--prune-merged]
#     slug            a warm worktree under ~/source/repos/<slug>   (e.g. omnibus2)
#     path            an explicit area directory
#     (no positional) auto-detect the area from the current directory
#     --prune-merged  also delete all other merged branches (repo-wide)
#
# Examples:
#   ~/reset-omni.sh omnibus2
#   ~/reset-omni.sh omnibus2 --prune-merged
#   cd ~/source/repos/omnibus2/Treeline.Services.Omnibus && ~/reset-omni.sh

set -uo pipefail

REPO_ROOT="$HOME/source/repos"

resolve_area() {
  local arg="${1:-}"
  if [[ -n "$arg" ]]; then
    [[ -d "$arg" ]] && { (cd "$arg" && pwd); return; }
    [[ -d "$REPO_ROOT/$arg" ]] && { echo "$REPO_ROOT/$arg"; return; }
    echo "ERROR: no such area '$arg' (looked for '$arg' and '$REPO_ROOT/$arg')" >&2
    exit 1
  fi
  case "$PWD" in
    "$REPO_ROOT"/*) echo "$REPO_ROOT/$(printf '%s' "${PWD#"$REPO_ROOT"/}" | cut -d/ -f1)" ;;
    *) echo "ERROR: not inside $REPO_ROOT/<slug>; pass a slug or path." >&2; exit 1 ;;
  esac
}

# --- parse args: one optional positional (slug|path) + optional --prune-merged ---
PRUNE=0
POS=""
for a in "$@"; do
  case "$a" in
    --prune-merged) PRUNE=1 ;;
    -h|--help) sed -n '2,40p' "$0"; exit 0 ;;
    -*) echo "unknown option: $a (see --help)" >&2; exit 2 ;;
    *) if [[ -z "$POS" ]]; then POS="$a"; else echo "unexpected extra arg: $a" >&2; exit 2; fi ;;
  esac
done

AREA="$(resolve_area "$POS")" || exit 1
echo "Area: $AREA"
[[ $PRUNE -eq 1 ]] && echo "Mode: --prune-merged (deleting ALL merged branches, repo-wide)"

# --- merged-branch detection ---------------------------------------------------
# A branch counts as merged if EITHER:
#   (a) it is a literal ancestor of origin/<default>  (real merge / fast-forward), or
#   (b) origin/<default> contains an Azure DevOps merge commit naming it as the
#       source: "Merge pull request N from <branch> into <default>".
# (b) exists because Azure DevOps squash-merges rewrite the source commits, so
# `merge-base --is-ancestor` can NEVER see a squash-merged branch. Without it the
# prune reports every real session branch as "kept (unmerged)" forever.
# The trailing " into" anchor stops prefix collisions (story/ATL1711 must not
# match a commit for story/ATL17110).
# Sets MERGE_KIND to "ancestor" or "squash" on success.
branch_is_merged() {
  local r="$1" b="$2" def="$3"
  MERGE_KIND=""
  if git -C "$r" merge-base --is-ancestor "$b" "origin/$def" 2>/dev/null; then
    MERGE_KIND=ancestor
    return 0
  fi
  if [[ -n "$(git -C "$r" log "origin/$def" -F --grep="from $b into" \
                 --format='%h' -1 2>/dev/null)" ]]; then
    MERGE_KIND=squash
    return 0
  fi
  return 1
}



# Discover the session repos via the canonical workspace resolver (matches /work-*
# scope); fall back to every git working tree directly under the area.
declare -a REPOS=()
primary=""
for d in "$AREA"/*/; do
  if git -C "$d" rev-parse --is-inside-work-tree >/dev/null 2>&1; then primary="${d%/}"; break; fi
done
tool="$(jq -r '.plugins["cc@treeline-cc-framework"][0].installPath' \
          "$HOME/.claude/plugins/installed_plugins.json" 2>/dev/null)/tools/workspace-repos.py"
if [[ -n "$primary" && -f "$tool" ]]; then
  mapfile -t REPOS < <(cd "$primary" && python3 "$tool" --json 2>/dev/null | jq -r '.repos[]?')
fi
if [[ ${#REPOS[@]} -eq 0 ]]; then
  for d in "$AREA"/*/; do
    git -C "$d" rev-parse --is-inside-work-tree >/dev/null 2>&1 && REPOS+=("${d%/}")
  done
fi
[[ ${#REPOS[@]} -eq 0 ]] && { echo "No git repos found under $AREA" >&2; exit 1; }

echo "Repos: ${#REPOS[@]}"
echo

rc=0
for r in "${REPOS[@]}"; do
  name="$(basename "$r")"

  if [[ -n "$(git -C "$r" status --porcelain --untracked-files=no)" ]]; then
    echo "SKIP  $name — uncommitted changes (left untouched)"
    rc=1
    continue
  fi

  def="$(git -C "$r" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's|^origin/||')"
  def="${def:-release}"

  if ! git -C "$r" fetch --quiet origin "$def"; then
    echo "SKIP  $name — 'git fetch origin $def' failed"
    rc=1
    continue
  fi

  was="$(git -C "$r" rev-parse --abbrev-ref HEAD 2>/dev/null)"
  [[ "$was" == "HEAD" ]] && was="(detached)"

  if ! git -C "$r" checkout --quiet --detach "origin/$def"; then
    echo "SKIP  $name — could not detach at origin/$def"
    rc=1
    continue
  fi

  declare -a deleted=() squashed=() kept=() locked=()
  if [[ $PRUNE -eq 1 ]]; then
    # Broad cleanup: every local branch merged into origin/<default>.
    while IFS= read -r b; do
      [[ -z "$b" ]] && continue
      if branch_is_merged "$r" "$b" "$def"; then
        if git -C "$r" branch -D "$b" >/dev/null 2>&1; then
          if [[ "$MERGE_KIND" == squash ]]; then squashed+=("$b"); else deleted+=("$b"); fi
        else
          # Merged, but git refuses -- checked out in another worktree (or is the
          # default branch itself). Report it rather than dropping it silently.
          locked+=("$b")
        fi
      else
        kept+=("$b")
      fi
    done < <(git -C "$r" for-each-ref --format='%(refname:short)' refs/heads)
  else
    # Default: only the branch this area was sitting on, if merged.
    if [[ -n "$was" && "$was" != "(detached)" ]]; then
      if branch_is_merged "$r" "$was" "$def"; then
        if git -C "$r" branch -D "$was" >/dev/null 2>&1; then
          if [[ "$MERGE_KIND" == squash ]]; then squashed+=("$was"); else deleted+=("$was"); fi
        else
          locked+=("$was")
        fi
      else
        kept+=("$was")
      fi
    fi
  fi

  printf 'OK    %-40s detached @ origin/%s (%s), was %s\n' \
    "$name" "$def" "$(git -C "$r" rev-parse --short HEAD)" "$was"
  [[ ${#deleted[@]}  -gt 0 ]] && printf '        deleted (merged): %s\n' "${deleted[*]}"
  [[ ${#squashed[@]} -gt 0 ]] && printf '        deleted (squash-merged via PR): %s\n' "${squashed[*]}"
  [[ ${#locked[@]}   -gt 0 ]] && printf '        merged but LOCKED by another worktree: %s\n' "${locked[*]}"
  [[ ${#kept[@]}     -gt 0 ]] && printf '        kept (unmerged):  %s\n' "${kept[*]}"
  unset deleted squashed kept locked
done

# --- Clear stale cc work-session state --------------------------------------
# The git half of a reset is not the whole resting state. The cc framework marks a
# session ACTIVE by the mere PRESENCE of .claude/work-sessions/state/current-work.json
# (see work-finish step 1: "If $STATE is missing ... No active work session"), and the
# statusline reads that file's .branch into its primary `@ <branch>` chip
# (statusline-script.sh: session_branch). So a reset that detaches HEAD but leaves the
# state file behind produces a statusline that still names the old session branch, with
# only a small red `!` + `cwd:detached` to hint at the mismatch -- the area LOOKS like
# it is still on a session branch. Observed live 2026-09-01 in omnibus2 after
# feature/journey-goal-move-contents merged as PRs 16247/16248.
#
# These files are gitignored, so no amount of git resetting ever clears them.
#
# Safety rule: only clear state whose .branch no longer exists locally. If the branch
# is still present (it was kept as unmerged above), the session is legitimately
# resumable -- leave it alone and say so. Swept over EVERY repo dir in the area, not
# just the resolver's list, because state files are per-repo and cheap to check.
declare -a state_cleared=() state_kept=()
for _d in "$AREA"/*/; do
  git -C "$_d" rev-parse --is-inside-work-tree >/dev/null 2>&1 || continue
  _sf="$_d/.claude/work-sessions/state/current-work.json"
  [[ -f "$_sf" ]] || continue
  _sb=$(python3 -c "
import json,sys
try:
    print(json.load(open(sys.argv[1])).get('branch') or '')
except Exception:
    print('')
" "$_sf" 2>/dev/null)
  _nm="$(basename "${_d%/}")"
  if [[ -n "$_sb" ]] && git -C "$_d" rev-parse --verify -q "refs/heads/$_sb" >/dev/null 2>&1; then
    state_kept+=("$_nm:$_sb")
  else
    rm -f "$_sf" && state_cleared+=("$_nm${_sb:+:$_sb}")
  fi
done
if [[ ${#state_cleared[@]} -gt 0 ]]; then
  printf 'work-session state cleared (branch gone): %s\n' "${state_cleared[*]}"
fi
if [[ ${#state_kept[@]} -gt 0 ]]; then
  printf 'work-session state KEPT (branch still present, session resumable): %s\n' "${state_kept[*]}"
fi
unset state_cleared state_kept

echo
if [[ $rc -eq 0 ]]; then
  echo "Done — every repo detached at its origin default. Next /work-start cuts a fresh branch."
else
  echo "Done with skips (see SKIP lines above). Resolve those repos, then re-run."
fi
# --- Advisory only: are any declared dependencies missing? -------------------
# Read-only. Does not touch anything and does not affect the exit code (see the
# explicit `exit $rc` below). Detaching to origin/<default> rewrites package.json
# and package-lock.json but never node_modules, so an area that was sitting far
# behind release ends up missing packages its code now imports. That failure
# surfaces at RUNTIME in the browser as an unresolvable import
# ("[plugin:vite:import-analysis] Failed to resolve import ..."), not as anything
# git-shaped. Observed live 2026-08-14 in quickfix after a reset off a branch 1375
# commits behind release (@zxing/library and jest-junit were absent).
#
# NOTE: do NOT compare mtimes here. The reset re-checks-out package-lock.json, so
# the lockfile is ALWAYS newer than node_modules immediately afterwards — an
# mtime test fires on every run even when nothing is missing. Ask the question that
# actually matters instead: is anything declared but not installed?
_ec="$AREA/Treeline.Clients.EdelweissComponents"
if [[ -d "$_ec" ]]; then
  if [[ ! -d "$_ec/node_modules" ]]; then
    echo
    echo "!! node_modules is MISSING for this area."
    echo "   Run before starting the dev stack:  (cd $_ec && npm install)"
  elif command -v node >/dev/null 2>&1; then
    # For each declared dep, walk UP from the declaring package.json's directory
    # checking <dir>/node_modules/<dep> at each level, exactly as Node resolves.
    # npm does NOT hoist consistently in this monorepo — pdfmake sits in the app's
    # own node_modules in one area and at the root in another — so a root-only
    # check false-positives. Directory existence (not require.resolve) is used so
    # type-only packages like @types/* are handled correctly.
    _missing="$(cd "$_ec" 2>/dev/null && node -e '
      const fs=require("fs"), path=require("path");
      const root=process.cwd();
      const files=["package.json", ...(fs.existsSync("packages/apps")
        ? fs.readdirSync("packages/apps").map(d=>path.join("packages/apps",d,"package.json")) : [])];
      const installed=(dir,dep)=>{
        let d=path.resolve(dir);
        for(;;){
          if(fs.existsSync(path.join(d,"node_modules",dep))) return true;
          if(d===root||d===path.dirname(d)) return false;
          d=path.dirname(d);
        }
      };
      const miss=new Set();
      for(const f of files){
        if(!fs.existsSync(f)) continue;
        let j; try{ j=JSON.parse(fs.readFileSync(f,"utf8")); }catch{ continue; }
        for(const dep of Object.keys({...j.dependencies,...j.devDependencies})){
          if(dep.startsWith("@above-the-treeline/")) continue;   // workspace-internal
          if(!installed(path.dirname(f),dep)) miss.add(dep);
        }
      }
      if(miss.size) console.log([...miss].join(" "));
    ' 2>/dev/null || true)"
    if [[ -n "$_missing" ]]; then
      echo
      echo "!! Declared dependencies are NOT installed in this area:"
      for _m in $_missing; do echo "     - $_m"; done
      echo "   The checkout updated package.json but node_modules is behind."
      echo "   Run before starting the dev stack:  (cd $_ec && npm install)"
      echo "   Skipping it shows up as a vite 'Failed to resolve import' error in the browser."
    fi
  fi
fi

# --- Re-sync the merged .claude/skills directory --------------------------------
#     The checkouts above change branches, and that changes which project skills
#     exist — notably publisher-landing-design, which only lives on the
#     publisher-pages line of work. Re-running the sync prunes symlinks that now
#     dangle and picks up skills the new branch added. The area root is outside
#     every git repo, so none of this is tracked.
if [[ -x "$HOME/sync-omni-skills.sh" ]]; then
  echo
  "$HOME/sync-omni-skills.sh" "$(basename "$AREA")" || true
else
  echo
  echo "NOTE: ~/sync-omni-skills.sh not found — .claude/skills was NOT re-synced." >&2
  echo "      If a branch change added or removed a project skill, the area's skill" >&2
  echo "      list is now stale (possibly with dangling symlinks)." >&2
fi

exit $rc

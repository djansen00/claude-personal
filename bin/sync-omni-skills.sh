#!/usr/bin/env bash
# sync-omni-skills.sh — merge both Omnibus skill sets into each warm worktree's
# .claude/skills so BOTH load regardless of session cwd.
#
# Why: a warm worktree's .claude/skills is a symlink into Treeline.Workspaces, so the
# frontend repo's own skills (omnibus-publisher-ui, publisher-landing-design) never get
# discovered from the worktree root. This replaces that single symlink with a real
# directory of per-skill symlinks pointing at BOTH sources.
#
# Safe: <WT>/.claude/ is NOT inside any git repo, so nothing here is tracked or pushed.
# Symlinks point INTO the repos; no files are written inside them.
#
# Usage:
#   ~/sync-omni-skills.sh            # apply to every warm worktree
#   ~/sync-omni-skills.sh --check    # dry run, show what would change
#   ~/sync-omni-skills.sh --revert   # restore the original single symlink
#   ~/sync-omni-skills.sh <slug>...  # limit to named worktrees

set -uo pipefail

ROOT="$HOME/source/repos"
WS_REL="Treeline.Workspaces/Omnibus/.claude/skills"
EC_REL="Treeline.Clients.EdelweissComponents/.claude/skills"

MODE=apply
TARGETS=()
for a in "$@"; do
  case "$a" in
    --check)  MODE=check ;;
    --revert) MODE=revert ;;
    -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
    *) TARGETS+=("$a") ;;
  esac
done

if [ ${#TARGETS[@]} -eq 0 ]; then
  for d in "$ROOT"/*/; do
    [ -d "$d/Treeline.Clients.EdelweissComponents" ] && TARGETS+=("$(basename "$d")")
  done
fi

changed=0
for slug in "${TARGETS[@]}"; do
  WT="$ROOT/$slug"
  SK="$WT/.claude/skills"

  if [ ! -d "$WT/Treeline.Clients.EdelweissComponents" ]; then
    printf '%-16s skip — no EdelweissComponents\n' "$slug"; continue
  fi

  # Refuse to touch a .claude that is somehow inside a git repo.
  if git -C "$WT" rev-parse --show-toplevel >/dev/null 2>&1; then
    printf '%-16s SKIP — %s is inside a git repo; refusing\n' "$slug" "$WT"; continue
  fi

  if [ "$MODE" = revert ]; then
    if [ -L "$SK" ]; then
      printf '%-16s already the original symlink\n' "$slug"; continue
    fi
    # Only remove a dir whose entries are all symlinks (i.e. one we created).
    if [ -d "$SK" ] && [ -z "$(find "$SK" -mindepth 1 -maxdepth 1 ! -type l -print -quit)" ]; then
      rm -rf "$SK"
      ln -s "../$WS_REL" "$SK"
      printf '%-16s reverted to single symlink\n' "$slug"; changed=$((changed+1))
    else
      printf '%-16s REFUSED — %s holds real files, not just symlinks\n' "$slug" "$SK"
    fi
    continue
  fi

  # Build the desired skill -> source map from both sources.
  declare -A want=()
  for rel in "$WS_REL" "$EC_REL"; do
    src="$WT/$rel"
    [ -d "$src" ] || continue
    for s in "$src"/*/; do
      [ -f "$s/SKILL.md" ] || continue
      want["$(basename "$s")"]="${s%/}"
    done
  done

  if [ ${#want[@]} -eq 0 ]; then
    printf '%-16s skip — no skills found\n' "$slug"; unset want; continue
  fi

  if [ "$MODE" = check ]; then
    state="symlink"; [ -d "$SK" ] && [ ! -L "$SK" ] && state="realdir"
    printf '%-16s %-8s would link %d skills:' "$slug" "$state" "${#want[@]}"
    for k in $(printf '%s\n' "${!want[@]}" | sort); do
      case "${want[$k]}" in *EdelweissComponents*) printf ' %s(FE)' "$k";; *) printf ' %s' "$k";; esac
    done
    echo; unset want; continue
  fi

  # Apply: replace the symlink with a real dir of per-skill symlinks.
  if [ -L "$SK" ]; then rm "$SK"; fi
  mkdir -p "$SK"

  # Prune stale entries (skill removed, or branch no longer has it).
  for existing in "$SK"/*; do
    [ -e "$existing" ] || [ -L "$existing" ] || continue
    name="$(basename "$existing")"
    if [ -L "$existing" ] && [ -z "${want[$name]+x}" ]; then rm "$existing"; fi
    if [ -L "$existing" ] && [ ! -e "$existing" ]; then rm "$existing"; fi
  done

  n=0; fe=0
  for k in "${!want[@]}"; do
    tgt="${want[$k]}"
    link="$SK/$k"
    if [ -L "$link" ] && [ "$(readlink "$link")" = "$tgt" ]; then :; else
      rm -rf "$link"; ln -s "$tgt" "$link"
    fi
    n=$((n+1))
    case "$tgt" in *EdelweissComponents*) fe=$((fe+1));; esac
  done

  printf '%-16s linked %d skills (%d from the frontend repo)\n' "$slug" "$n" "$fe"
  changed=$((changed+1))
  unset want
done

echo
echo "worktrees changed: $changed"
if [ "$MODE" = apply ]; then
  echo "Verify: start a NEW session in one of them and check that omnibus-publisher-ui"
  echo "        (and publisher-landing-design, on omnibus1/omnibus2/title-manager) appear"
  echo "        in the available-skills list. If they do not, run --revert; the"
  echo "        omnibus-ui-registers skill still covers you."
fi

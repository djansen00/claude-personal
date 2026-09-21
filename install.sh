#!/usr/bin/env bash
# install.sh — link this repo's skills and scripts into place on a machine.
#
#   ./install.sh            # symlink (default) — edits stay live, one place to commit
#   ./install.sh --copy     # copy instead, for a machine where symlinks are awkward
#   ./install.sh --check    # report what would change, touch nothing
#   ./install.sh --areas    # ALSO restore bin/areas/* into $HOME (see the caveat below)
#
# Symlinks are the point: with them, `git status` in this repo is the truth about
# what has drifted. Copies reintroduce exactly the sync problem the repo exists to
# solve, so use --copy only if you must.
#
# NEVER links anything into ~/.claude except the skill directories. Credentials
# (~/.claude/edelweiss-creds.json and friends) live there and must stay untracked.

set -uo pipefail
R="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODE=link; DO_AREAS=0
for a in "$@"; do
  case "$a" in
    --copy)  MODE=copy ;;
    --check) MODE=check ;;
    --areas) DO_AREAS=1 ;;
    -h|--help) sed -n '2,18p' "$0"; exit 0 ;;
    *) echo "unknown flag: $a" >&2; exit 2 ;;
  esac
done

SK="$HOME/.claude/skills"
mkdir -p "$SK"
rc=0

place() {  # place <source> <dest>
  local src="$1" dst="$2" what
  if [[ -L "$dst" ]]; then
    [[ "$(readlink -f "$dst")" == "$(readlink -f "$src")" ]] && { printf '  %-44s ok (linked)\n' "${dst/#$HOME/\~}"; return; }
    what="RELINK (points elsewhere)"
  elif [[ -e "$dst" ]]; then
    what="SKIP — real file/dir already there, not overwriting"
    printf '  %-44s %s\n' "${dst/#$HOME/\~}" "$what"; rc=1; return
  else
    what="create"
  fi
  if [[ "$MODE" == check ]]; then printf '  %-44s would %s\n' "${dst/#$HOME/\~}" "$what"; return; fi
  rm -rf "$dst"
  if [[ "$MODE" == copy ]]; then cp -a "$src" "$dst"; else ln -s "$src" "$dst"; fi
  printf '  %-44s %s\n' "${dst/#$HOME/\~}" "$what"
}

echo ">> skills -> ~/.claude/skills/"
for d in "$R"/skills/*/; do place "${d%/}" "$SK/$(basename "$d")"; done

echo ">> shared scripts -> \$HOME"
for f in "$R"/bin/*.sh; do place "$f" "$HOME/$(basename "$f")"; done

if [[ $DO_AREAS -eq 1 ]]; then
  echo ">> per-area scripts -> \$HOME (copies — these are machine-specific)"
  # Deliberately COPIES, never symlinks: these are generated per machine by
  # create-warm-worktree and edited in place. Linking them would make one
  # machine's areas overwrite another's. They are snapshots for reference and
  # for recovering hand-edits, not a portable install.
  for f in "$R"/bin/areas/*.sh; do
    d="$HOME/$(basename "$f")"
    [[ -e "$d" ]] && { printf '  %-44s SKIP (exists)\n' "${d/#$HOME/\~}"; continue; }
    [[ "$MODE" == check ]] && { printf '  %-44s would copy\n' "${d/#$HOME/\~}"; continue; }
    cp -p "$f" "$d"; printf '  %-44s copied\n' "${d/#$HOME/\~}"
  done
fi

echo
echo ">> note: warm worktrees themselves are NOT restored by this script."
echo "   Recreate each area with:  ~/.claude/skills/create-warm-worktree/create-warm-worktree.sh <slug>"
[[ $rc -ne 0 ]] && echo ">> some destinations were skipped (real files in the way) — resolve by hand." >&2
exit $rc

#!/usr/bin/env bash
# Reset the omnibus1 warm worktree to a clean between-sessions state
# (thin wrapper around the generic ~/reset-omni.sh).
exec "$HOME/reset-omni.sh" omnibus1 "$@"

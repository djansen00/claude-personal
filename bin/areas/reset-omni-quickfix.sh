#!/usr/bin/env bash
# Reset the quickfix warm worktree to a clean between-sessions state
# (thin wrapper around the generic ~/reset-omni.sh).
exec "$HOME/reset-omni.sh" quickfix "$@"

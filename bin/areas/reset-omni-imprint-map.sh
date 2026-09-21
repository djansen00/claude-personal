#!/usr/bin/env bash
# Reset the imprint-map warm worktree to a clean between-sessions state
# (thin wrapper around the generic ~/reset-omni.sh).
exec "$HOME/reset-omni.sh" imprint-map "$@"

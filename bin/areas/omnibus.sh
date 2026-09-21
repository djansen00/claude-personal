#!/usr/bin/env bash
cd /home/djansen/projects/omnibus/Treeline.Workspaces/Omnibus || exit 1
exec claude -c "$@"

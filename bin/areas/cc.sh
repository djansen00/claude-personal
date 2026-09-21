#!/usr/bin/env bash
cd /home/djansen/projects/cc || exit 1
exec claude -c "$@"

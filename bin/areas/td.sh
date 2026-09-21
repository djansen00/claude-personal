#!/usr/bin/env bash
cd /home/djansen/projects/titledispatch || exit 1
exec claude -c "$@"

#!/usr/bin/env bash
# Print the project directory of any compose stack whose running containers are
# using an image older than the latest image available locally — i.e. a newer
# image has been pulled but the stack has not been recreated onto it.
#
# Usage: compose_drift.sh <project_dir> [<project_dir> ...]
#
# Self-clearing: once a stack is restarted (docker compose up -d) the running
# container adopts the latest image ID and is no longer reported.

for dir in "$@"; do
  stale=""
  for cid in $(docker compose --project-directory "$dir" ps -q 2>/dev/null); do
    running=$(docker inspect --format '{{.Image}}' "$cid" 2>/dev/null) || continue
    ref=$(docker inspect --format '{{.Config.Image}}' "$cid" 2>/dev/null) || continue
    [ -n "$ref" ] || continue
    latest=$(docker image inspect --format '{{.Id}}' "$ref" 2>/dev/null) || continue
    if [ -n "$latest" ] && [ "$running" != "$latest" ]; then
      stale=1
    fi
  done
  if [ -n "$stale" ]; then
    echo "$dir"
  fi
done

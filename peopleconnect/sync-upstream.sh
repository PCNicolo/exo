#!/bin/bash
# sync-upstream.sh: pull exo-explore/exo main into this fork.
# main is kept identical to upstream; peopleconnect is rebased on top of it.
set -euo pipefail
cd "$(dirname "$0")/.."
git remote get-url upstream >/dev/null 2>&1 || git remote add upstream https://github.com/exo-explore/exo.git
[ -z "$(git status --porcelain)" ] || { echo "Commit or stash your changes first."; exit 1; }
git fetch --quiet upstream --tags
git checkout --quiet main
git merge --ff-only upstream/main
git push --quiet origin main
git checkout --quiet peopleconnect
echo "upstream main is at $(git rev-parse --short upstream/main); rebasing peopleconnect onto it"
if git rebase main; then
  echo "Rebased. Now: uv sync --extra mlx && uv run pytest, then git push --force-with-lease origin peopleconnect"
else
  echo "Conflict. For uv.lock: git checkout --theirs uv.lock && uv lock && git add uv.lock && git rebase --continue"
  exit 1
fi

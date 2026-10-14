#!/bin/bash
# seed-model.sh: download a model once, then copy it to the other nodes over the LAN.
# exo downloads straight from Hugging Face on every node that needs a shard; with 5 or 6 nodes
# that is the same tens of GB over the office internet 5 or 6 times, and a new layer split means
# more downloads. Seeding the full model on each worker once avoids all of that: exo picks up
# anything already in its models folder.
#
# usage:  HF_TOKEN=hf_xxx bash peopleconnect/seed-model.sh <hf model id> [user@node ...]
# example: bash peopleconnect/seed-model.sh mlx-community/Qwen3-Next-80B-A3B-Instruct-4bit nico@10.0.0.11 nico@10.0.0.12
# HF_TOKEN can also come from peopleconnect/local.env or `hf auth login`. Re-running resumes.
set -euo pipefail
MODEL=${1:?usage: seed-model.sh <hf model id> [user@node ...]}
shift
ENV_FILE="$(dirname "$0")/local.env"
if [ -z "${HF_TOKEN:-}" ] && [ -f "$ENV_FILE" ]; then
  HF_TOKEN=$(grep -E '^HF_TOKEN=' "$ENV_FILE" | cut -d= -f2- || true)
  export HF_TOKEN
fi
FOLDER="${MODEL//\//--}"                        # exo's folder name: org/name -> org--name
LOCAL_DIR="${EXO_DEFAULT_MODELS_DIR:-$HOME/.exo/models}/$FOLDER"
mkdir -p "$LOCAL_DIR"
echo "==> downloading $MODEL to $LOCAL_DIR"
uvx --from huggingface_hub hf download "$MODEL" --local-dir "$LOCAL_DIR" --max-workers 16
du -sh "$LOCAL_DIR"
for host in "$@"; do
  echo "==> copying to $host"
  ssh "$host" "mkdir -p ~/.exo/models/$FOLDER"
  rsync -a --partial --info=progress2 "$LOCAL_DIR/" "$host:~/.exo/models/$FOLDER/"
done
echo "done. exo on each node lists the model as downloaded within a minute (or after a restart)."

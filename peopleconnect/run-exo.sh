#!/bin/bash
# run-exo.sh: start this machine's exo role. Used by launchd and by hand.
# Settings come from peopleconnect/local.env (copy node.env.example or controller.env.example).
set -euo pipefail
cd "$(dirname "$0")/.."
ENV_FILE=peopleconnect/local.env
[ -f "$ENV_FILE" ] || { echo "Missing $ENV_FILE. Copy peopleconnect/node.env.example or controller.env.example to it."; exit 1; }
set -a
# shellcheck disable=SC1090
. "$ENV_FILE"
set +a
: "${EXO_ZENOH_NAMESPACE:?set EXO_ZENOH_NAMESPACE in $ENV_FILE}"
# shellcheck disable=SC2086
exec uv run --no-sync exo --namespace "$EXO_ZENOH_NAMESPACE" ${EXO_EXTRA_ARGS:-}

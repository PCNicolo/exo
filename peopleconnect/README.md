# exo, PeopleConnect fork

This fork runs exo on the Local LLM Grid: retired Apple M1 MacBooks as workers and an Intel
i9 MacBook as the coordinator. Upstream is exo-explore/exo. The `main` branch here is an
untouched mirror of upstream `main`; every change of ours lives on the `peopleconnect`
branch as a short stack of commits on top of it, so pulling upstream is a rebase.

## Why a fork

Upstream is built around Thunderbolt 5 Macs with RDMA (M4 Pro and newer, M3 Ultra). Our
fleet is M1: Thunderbolt 4 and 3, no RDMA, and three of the seven machines have 8 GB. Each
patch below removes something that only makes sense on the newer hardware, or adds a
knob the M1 fleet needs. Everything else is upstream as is.

## What is changed (one commit each)

1. **MLX from the PyPI wheel on macOS** (`pyproject.toml`, `uv.lock`). Upstream builds MLX
   from a git commit of `ml-explore/mlx` main for fast-synch deadlock fixes. Fast synch is
   only used by the RDMA (JACCL) backend, which M1 cannot use. The source build also needs
   the full Xcode Metal toolchain on every node; with the Command Line Tools alone it fails
   at `xcrun: unable to find utility "metal"`. The wheel installs in seconds and is the
   same MLX 0.32.0 upstream shipped until 2026-10-12.
2. **`EXO_MIN_NODE_MEMORY_GB`** (`src/exo/shared/constants.py`, `src/exo/master/placement.py`,
   `src/exo/master/main.py`, tests in `src/exo/master/tests/test_placement.py`). Automatic
   placement skips nodes whose total RAM is under this many GB, unless the request names
   them. Without it an 8 GB M1 gets pulled into a split model for a handful of layers and
   adds a wifi hop to every token. Default 0 (off), so upstream behaviour is unchanged until
   the variable is set. The master applies it, so it must be set on the controller; set it
   on every node so a fallback master behaves the same.
3. **This folder** (`peopleconnect/`): run wrapper, env examples, launchd template, upstream
   sync script. New files only, so they never conflict on rebase.

Nothing in exo's protocol changed. Even so, every node must run the same commit of this
fork, because exo's event and state types only match between identical versions.

## Roles on our hardware

| Machine | Role | Flags | Env |
|---|---|---|---|
| Intel i9 MacBook (16 GB) | coordinator and API front door | `--no-worker --no-downloads --force-master` | `EXO_MIN_NODE_MEMORY_GB=16` |
| M1 Max 14" 32 GB (x2 usable) | workers | none | `EXO_MIN_NODE_MEMORY_GB=16 EXO_MAX_CONCURRENT_REQUESTS=4` |
| M1 Pro 14" 16 or 32 GB | worker | none | same as M1 Max; `EXO_MAX_CONCURRENT_REQUESTS=2` if 16 GB |
| M1 13" 8 GB (x3) | workers for hand-picked small models only | none | `EXO_MIN_NODE_MEMORY_GB=16 EXO_MAX_CONCURRENT_REQUESTS=1` |

How the coordinator role works in upstream exo, no patch needed:

- `--force-master` gives the node election seniority 1,000,000, so it wins every election
  while it is up. The master indexes events and decides placements; that is light work.
- `--no-worker` means it never loads a model shard. The master also never places on it:
  a node without a worker reports no memory, and placement drops any group that contains
  a node without a memory report.
- The API and dashboard run on every node by default, so `http://<controller>:52415` is
  the one stable address. Tokens stream from the workers through the controller over
  zenoh, which is fine at chat speeds. Open WebUI and Caddy on the controller can point
  at `localhost:52415` instead of a failover list of worker IPs.
- Verified 2026-10-14 on an M5 Pro with a Python environment that has no MLX installed at
  all (`uv sync` with no extras): the node starts, elects itself master, answers
  `/node_id`, `/state` and `/models`, and serves the dashboard. Not yet verified on the
  Intel machine itself (x86_64 build of the Rust bindings and the Python wheels).

Intel notes: the exo macOS app is arm64 only, so the controller runs from source. Needs
Rust (rustup, for the `exo_rs` bindings), uv, and either Node to build the dashboard or a
copy of `dashboard/build/` from another machine. No MLX extra. macOS 26.2 is only required
by the app, not by exo from source.

## Running a node from source

```bash
# one time, on the machine
git clone -b peopleconnect https://github.com/PCNicolo/exo.git ~/exo && cd ~/exo
(cd dashboard && npm install && npm run build)     # or copy dashboard/build from another node
uv sync --extra mlx                                 # workers (M1). Controller: uv sync
cp peopleconnect/node.env.example peopleconnect/local.env        # controller: controller.env.example
$EDITOR peopleconnect/local.env                     # namespace, memory floor, concurrency

# by hand
bash peopleconnect/run-exo.sh

# as a launchd agent (starts at login, restarts if it dies)
sed -e "s|__EXO_DIR__|$HOME/exo|g" -e "s|__USER__|$(whoami)|g" \
  peopleconnect/us.peopleconnect.exo.plist.example > ~/Library/LaunchAgents/us.peopleconnect.exo.plist
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/us.peopleconnect.exo.plist
```

`local.env` is ignored by git. The namespace must match on every node; nodes with
different namespaces never see each other.

## Pulling upstream

```bash
bash peopleconnect/sync-upstream.sh
```

It fetches upstream, fast-forwards `main`, rebases `peopleconnect` onto it and stops on
the first conflict. The usual conflict is `uv.lock`: take upstream's version
(`git checkout --theirs uv.lock`), run `uv lock`, `git add uv.lock`, `git rebase --continue`.
Then `uv sync --extra mlx`, `uv run pytest`, and `git push --force-with-lease origin peopleconnect`.
Upstream tags releases rarely (v1.0.71 is from 2026-04-23, with 136 commits on main since),
and the macOS app auto-updates from main builds, so `main` is what we track, not tags.

GitHub Actions is disabled on the fork: upstream's pipeline runs nix builds on three
runner types and needs their Cachix secret.

## Settings that matter on M1, no patch needed

- `EXO_MAX_CONCURRENT_REQUESTS` (default 8): continuous batching slots per model. Each
  slot holds a KV cache; on a 32 GB node with a 17 GB model, 4 is a safer ceiling.
- `EXO_PREFIX_CACHE_MAX_BYTES` (default 10% of RAM) and `EXO_MEMORY_THRESHOLD`
  (0.75 of RAM on 32 GB, 0.70 below): prompt cache limits. Leave at defaults until the
  benchmarks show memory pressure.
- Sharding: `Pipeline` is the default and the right one over wifi. `Tensor` adds an
  all-reduce per layer per token; over Thunderbolt 4 (IP, about 10 to 20 Gbit/s) it may
  break even, over wifi it will not. Measure before changing the default.
- Ring host selection already prefers Thunderbolt over Ethernet over wifi for the
  neighbour links. To use direct Thunderbolt cables between M1s, each Thunderbolt port
  needs its own IP service instead of the Thunderbolt Bridge (a bridge across three
  machines loops). Upstream's `tmp/set_rdma_network_config.sh` does exactly that and
  does not need RDMA; the macOS app installs the same thing as a LaunchDaemon.
- Discovery is IPv6 multicast on UDP 52413 plus TCP 52414 between nodes. Office wifi
  that filters multicast between clients will keep nodes from finding each other.
  Upstream removed `--bootstrap-peers` (exo refuses to start with it). If Monday's wifi
  test shows nodes not discovering each other, the next patch is a zenoh
  `connect/endpoints` list pointing at the controller, which with gossip scouting lets
  the rest of the cluster find each other through it.
- `macmon` (brew, 0.9.0) gives GPU use, power and temperature in the dashboard and in
  `bench/`. Optional. The README warning about macmon crashing applies to M5 only.

## Open items

- Build and run on the Intel i9 (x86_64 Rust bindings, Python wheels, startup).
- Monday benchmarks (`bench/exo_bench.py`): one M1 Max alone, two over wifi, two over a
  Thunderbolt cable, Pipeline vs Tensor. Then set the default sharding and concurrency.
- Decide whether the 8 GB M1s run a small model instance (for example Qwen3.5-2B or
  Llama 3.2 3B for drafts and embeddings) or are retired from the grid.
- Bootstrap peers patch, only if multicast discovery fails on the office network.

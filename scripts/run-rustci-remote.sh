#!/usr/bin/env bash
# Sync project to remote host, then run Rust CI commands there.
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  ./scripts/run-rustci-remote.sh --remote <user@host> --source <local_path> --target <remote_path> [options]

Arguments:
  --remote       SSH destination in user@host format.
  --source       Local path to sync.
  --target       Remote path to sync into.
  --ci-dir       Remote directory where cargo commands run (default: --target).
  --ci-script    Script path (relative to --ci-dir) to run remote CI (default: scripts/run-rustci.sh).
  --port         SSH port (default: 22).
  --key          SSH key path.

Example:
  ./scripts/run-rustci-remote.sh --remote root@192.168.76.1 --port 65500 --source . --target workspace/termux-setmeup
USAGE
}

remote=""
source_dir=""
target=""
ci_dir=""
ci_script="scripts/run-rustci.sh"
port="22"
key_path=""
explicit_key=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --remote|-r)
      remote="${2:-}"
      shift 2
      ;;
    --source|-s)
      source_dir="${2:-}"
      shift 2
      ;;
    --target|--tagret|-t)
      target="${2:-}"
      shift 2
      ;;
    --ci-dir)
      ci_dir="${2:-}"
      shift 2
      ;;
    --ci-script)
      ci_script="${2:-}"
      shift 2
      ;;
    --port|-p)
      port="${2:-}"
      shift 2
      ;;
    --key|-k)
      key_path="${2:-}"
      explicit_key=1
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "Error: unknown option '$1'"
      usage
      exit 1
      ;;
  esac
done

if [[ -z "$remote" || -z "$source_dir" || -z "$target" ]]; then
  echo "Error: --remote, --source and --target are required."
  usage
  exit 1
fi

if [[ -z "$ci_dir" ]]; then
  ci_dir="$target"
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
sync_script="$script_dir/sync-remote.sh"
if [[ ! -f "$sync_script" ]]; then
  echo "Error: sync script not found: $sync_script"
  exit 1
fi

sync_args=(--remote "$remote" --port "$port" --source "$source_dir" --target "$target")
ssh_args=(-p "$port")
if [[ "$explicit_key" -eq 1 ]]; then
  sync_args+=(--key "$key_path")
  ssh_args+=(-i "$key_path")
fi

echo "Step 1/2: Syncing local project to remote..."
"$sync_script" "${sync_args[@]}"

echo "Step 2/2: Running remote Rust CI in '$ci_dir' via '$ci_script'..."
ssh "${ssh_args[@]}" "$remote" "cd \"$ci_dir\" && \
  if [[ ! -f \"$ci_script\" ]]; then \
    echo \"Error: CI script not found: $ci_script\"; \
    exit 1; \
  fi && \
  bash \"$ci_script\""

echo "Remote Rust CI checks passed."


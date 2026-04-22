#!/usr/bin/env bash
# Build the project on this machine.
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  ./scripts/build-local.sh [options]

Options:
  --profile <release|debug>  Build profile (default: release).
  --target <triple>          Optional rust target triple.
  --features <list>          Optional cargo features (comma-separated).
  --help, -h                 Show this help.

Examples:
  ./scripts/build-local.sh
  ./scripts/build-local.sh --profile debug
  ./scripts/build-local.sh --target aarch64-linux-android
USAGE
}

profile="release"
target=""
features=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --profile)
      profile="${2:-}"
      shift 2
      ;;
    --target)
      target="${2:-}"
      shift 2
      ;;
    --features)
      features="${2:-}"
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "Error: unknown option '$1'" >&2
      usage
      exit 1
      ;;
  esac
done

if [[ "$profile" != "release" && "$profile" != "debug" ]]; then
  echo "Error: --profile must be 'release' or 'debug'." >&2
  exit 1
fi

cmd=(cargo build)
if [[ "$profile" == "release" ]]; then
  cmd+=(--release)
fi
if [[ -n "$target" ]]; then
  cmd+=(--target "$target")
fi
if [[ -n "$features" ]]; then
  cmd+=(--features "$features")
fi

echo "Running: ${cmd[*]}"
"${cmd[@]}"

echo "Local build complete (${profile})."

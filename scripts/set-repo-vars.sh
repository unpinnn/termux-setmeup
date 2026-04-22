#!/usr/bin/env bash
# Set GitHub Actions secrets from local token files in docs.1/.
#
# This script replaces manual UI steps:
# Settings -> Secrets and variables -> Actions -> New repository secret
# and sets:
# - CRATES_IO_TOKEN
# - NPM_TOKEN
#
# Requirements:
# - gh CLI installed and authenticated (`gh auth status`)
# - token files present:
#   - docs.1/cargo-reg-token.txt
#   - docs.1/npmjs-token.txt
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  bash scripts/set-repo-vars.sh [--repo owner/name]

Options:
  --repo   Target repository for secrets (default: inferred from git remote)
  -h, --help

Examples:
  bash scripts/set-repo-vars.sh
  bash scripts/set-repo-vars.sh --repo your-user/termux-setmeup
USAGE
}

repo=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)
      repo="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage
      exit 1
      ;;
  esac
done

if ! command -v gh >/dev/null 2>&1; then
  echo "Error: gh CLI is not installed." >&2
  exit 1
fi

if ! gh auth status >/dev/null 2>&1; then
  echo "Error: gh CLI is not authenticated. Run: gh auth login" >&2
  exit 1
fi

if [[ -z "$repo" ]]; then
  if ! remote_url="$(git config --get remote.origin.url 2>/dev/null)"; then
    echo "Error: could not read git remote.origin.url; pass --repo owner/name." >&2
    exit 1
  fi
  # Supports both SSH and HTTPS remotes.
  repo="$(printf '%s' "$remote_url" | sed -E 's#(git@github.com:|https://github.com/)##; s#\.git$##')"
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root_dir="$(cd "$script_dir/.." && pwd)"

crates_file="$root_dir/docs.1/cargo-reg-token.txt"
npm_file="$root_dir/docs.1/npmjs-token.txt"

if [[ ! -f "$crates_file" ]]; then
  echo "Error: missing $crates_file" >&2
  exit 1
fi
if [[ ! -f "$npm_file" ]]; then
  echo "Error: missing $npm_file" >&2
  exit 1
fi

crates_token="$(head -n1 "$crates_file" | tr -d '\r\n')"
npm_token="$(head -n1 "$npm_file" | tr -d '\r\n')"

if [[ -z "$crates_token" ]]; then
  echo "Error: CRATES token file is empty: $crates_file" >&2
  exit 1
fi
if [[ -z "$npm_token" ]]; then
  echo "Error: NPM token file is empty: $npm_file" >&2
  exit 1
fi

echo "Setting CRATES_IO_TOKEN secret on $repo ..."
printf '%s' "$crates_token" | gh secret set CRATES_IO_TOKEN --repo "$repo"

echo "Setting NPM_TOKEN secret on $repo ..."
printf '%s' "$npm_token" | gh secret set NPM_TOKEN --repo "$repo"

echo "Done. Secrets updated on $repo:"
echo "- CRATES_IO_TOKEN"
echo "- NPM_TOKEN"


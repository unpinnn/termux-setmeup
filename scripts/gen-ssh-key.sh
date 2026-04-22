#!/usr/bin/env bash
# Ensure local SSH key exists and install its public key on a remote host.
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  scripts/gen-ssh-key.sh <user@host> [-p port] [-k key_path]

Examples:
  scripts/gen-ssh-key.sh alice@example.com
  scripts/gen-ssh-key.sh alice@example.com -p 2222
  scripts/gen-ssh-key.sh alice@example.com -p 22 -k ~/.ssh/id_ed25519
USAGE
}

if [[ $# -lt 1 ]]; then
  usage
  exit 1
fi

remote="$1"
shift

port="22"
key_path="$HOME/.ssh/id_ed25519"

while getopts ":p:k:h" opt; do
  case "$opt" in
    p) port="$OPTARG" ;;
    k) key_path="$OPTARG" ;;
    h)
      usage
      exit 0
      ;;
    :)
      echo "Error: option -$OPTARG requires a value."
      usage
      exit 1
      ;;
    \?)
      echo "Error: invalid option -$OPTARG"
      usage
      exit 1
      ;;
  esac
done

pub_key="${key_path}.pub"

if [[ ! -f "$key_path" || ! -f "$pub_key" ]]; then
  # Generate a default ed25519 key pair when missing.
  echo "SSH key not found at $key_path. Generating ed25519 key..."
  mkdir -p "$HOME/.ssh"
  ssh-keygen -t ed25519 -f "$key_path" -N ""
fi

echo "Copying public key to $remote (port $port)..."

if command -v ssh-copy-id >/dev/null 2>&1; then
  # Preferred path: ssh-copy-id handles duplicates and permissions.
  ssh-copy-id -i "$pub_key" -p "$port" "$remote"
else
  # Fallback for minimal environments where ssh-copy-id is unavailable.
  cat "$pub_key" | ssh -p "$port" "$remote" \
    "mkdir -p ~/.ssh && chmod 700 ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"
fi

echo "Done. You should now be able to SSH into $remote without a password."

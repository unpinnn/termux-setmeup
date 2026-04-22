#!/usr/bin/env bash
# Sync local source to remote path. Uses rclone+sftp first, falls back to scp.
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  bash scripts/sync-remote.sh --remote <user@host> --source <local_path> --target <remote_path> [options]

Examples:
  bash scripts/sync-remote.sh --remote root@192.168.76.1 --port 65500 --source . --target ~/workspace/termux-setmeup
  bash scripts/sync-remote.sh --remote root@192.168.76.1 --port 65500 --key ~/.ssh/id_ed25519 --source . --target workspace/termux-setmeup

Notes:
  - <source> is local path.
  - <target> is remote path on <user@host>.
  - Preferred transport is rclone (SFTP backend). scp is fallback.
USAGE
}

remote=""
source_path=""
target_path=""
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
      source_path="${2:-}"
      shift 2
      ;;
    --target|--tagret|-t)
      target_path="${2:-}"
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

if [[ -z "$remote" || -z "$source_path" || -z "$target_path" ]]; then
  echo "Error: --remote, --source and --target are required."
  usage
  exit 1
fi

remote_target="$target_path"

case "$remote_target" in
  ""|"."|"/"|"~"|"~/")
    # Guard rail: never sync to remote home/root by accident.
    echo "Error: refusing unsafe remote target '$remote_target'."
    echo "Use a dedicated project path, e.g. 'workspace/termux-setmeup' or '~/workspace/termux-setmeup'."
    exit 1
    ;;
esac

if [[ ! -e "$source_path" ]]; then
  echo "Error: source path does not exist: $source_path"
  exit 1
fi

# Parse remote user@host
if [[ "$remote" != *"@"* ]]; then
  echo "Error: remote must be in user@host format."
  exit 1
fi
remote_user="${remote%@*}"
remote_host="${remote#*@}"

if [[ "$explicit_key" -eq 1 ]]; then
  if [[ ! -f "$key_path" ]]; then
    echo "Error: key file not found: $key_path"
    exit 1
  fi
else
  for candidate in "$HOME/.ssh/id_ed25519" "$HOME/.ssh/id_rsa"; do
    if [[ -f "$candidate" ]]; then
      key_path="$candidate"
      break
    fi
  done
fi

# If caller forgot to quote "~" in Git Bash, convert local HOME-expanded path
# back into a remote-home-relative path.
if [[ "$remote_target" == "$HOME/"* ]]; then
  # Git Bash may pre-expand "~"; normalize back to remote-home form.
  remote_target="~/${remote_target#"$HOME"/}"
fi

# Expand remote home correctly when creating directories over ssh.
mkdir_target="$remote_target"
if [[ "$remote_target" == "~/"* ]]; then
  mkdir_target="\$HOME/${remote_target#~/}"
elif [[ "$remote_target" == "~" ]]; then
  mkdir_target="\$HOME"
fi

echo "Preparing remote target: $remote:$remote_target"
ssh_args=(-p "$port")
if [[ -n "$key_path" ]]; then
  ssh_args+=(-i "$key_path")
fi
ssh "${ssh_args[@]}" "$remote" "mkdir -p \"$mkdir_target\""

echo "Syncing '$source_path' -> '$remote:$remote_target' (port $port)..."

# rclone remote path should not include "~/" prefix.
rclone_target="$remote_target"
if [[ "$rclone_target" == "~/"* ]]; then
  rclone_target="${rclone_target#~/}"
elif [[ "$rclone_target" == "~" ]]; then
  rclone_target=""
fi
rclone_conn=":sftp,host=${remote_host},user=${remote_user},port=${port}"
rclone_remote="${rclone_conn}:${rclone_target}"
rclone_args=(--log-level ERROR)
if [[ -n "$key_path" ]]; then
  # Pass key path as a separate arg so Git Bash can path-convert for native rclone.exe.
  rclone_args+=(--sftp-key-file "$key_path")
fi

if command -v rclone >/dev/null 2>&1; then
  # rclone gives faster incremental sync and cleaner exclusion behavior.
  if [[ -d "$source_path" ]]; then
    if rclone sync "$source_path" "$rclone_remote" "${rclone_args[@]}"; then
      echo "Sync complete (rclone)."
      exit 0
    fi
  else
    filename="$(basename "$source_path")"
    file_target="${rclone_remote%/}/$filename"
    if rclone copyto "$source_path" "$file_target" "${rclone_args[@]}"; then
      echo "Sync complete (rclone)."
      exit 0
    fi
  fi
  echo "rclone failed, falling back to scp..."
else
  # scp fallback keeps script usable even without rclone installed.
  echo "rclone not found, using scp fallback..."
fi

if [[ -d "$source_path" ]]; then
  scp_args=(-r -P "$port")
  if [[ -n "$key_path" ]]; then
    scp_args+=(-i "$key_path")
  fi
  scp "${scp_args[@]}" "$source_path"/. "$remote:$remote_target/"
else
  scp_args=(-P "$port")
  if [[ -n "$key_path" ]]; then
    scp_args+=(-i "$key_path")
  fi
  scp "${scp_args[@]}" "$source_path" "$remote:$remote_target/"
fi

echo "Sync complete (scp fallback)."


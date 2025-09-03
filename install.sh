#!/bin/bash
set -euo pipefail

if command -v apk >/dev/null 2>&1; then
  apk add --no-cache git openssh-client curl jq
elif command -v apt-get >/dev/null 2>&1; then
  apt-get update && apt-get install -y git openssh-client curl jq && rm -rf /var/lib/apt/lists/*
fi

BASE="/home/container"
mkdir -p "$BASE"
cd "$BASE"

if [ -n "${REMOTE_SSH_KEY:-}" ]; then
  mkdir -p "$BASE/.ssh"
  chmod 700 "$BASE/.ssh"
  printf "%s\n" "${REMOTE_SSH_KEY}" > "$BASE/.ssh/id_ed25519"
  chmod 600 "$BASE/.ssh/id_ed25519"
  ssh-keyscan github.com >> "$BASE/.ssh/known_hosts" 2>/dev/null || true
  chmod 644 "$BASE/.ssh/known_hosts"
fi

git config --global --add safe.directory "$BASE" || true
git config --global --add safe.directory /mnt/server || true

if [ -n "${REMOTE_GIT:-}" ]; then
  BRANCH="${REMOTE_BRANCH:-main}"
  if [ -f "$BASE/.ssh/id_ed25519" ]; then
    export GIT_SSH_COMMAND='ssh -i /home/container/.ssh/id_ed25519 -o IdentitiesOnly=yes'
  else
    echo "[CSKStart] WARNING: REMOTE_GIT is set but REMOTE_SSH_KEY is missing. Using default SSH agent (may fail)."
  fi

  tmp_ssh=""
  if [ -d "$BASE/.ssh" ]; then
    tmp_ssh="$(mktemp -d)"
    mv "$BASE/.ssh" "$tmp_ssh/.ssh"
  fi

  shopt -s dotglob nullglob
  rm -rf "$BASE"/* || true
  shopt -u dotglob nullglob
  mkdir -p "$BASE"

  if [ -n "$tmp_ssh" ] && [ -d "$tmp_ssh/.ssh" ]; then
    mv "$tmp_ssh/.ssh" "$BASE/.ssh"
    rmdir "$tmp_ssh" || true
  fi

  git clone --depth=1 --branch "$BRANCH" "$REMOTE_GIT" "$BASE"
fi

curl -fsSL "https://raw.githubusercontent.com/CoderskyNetwork/CSKStart/refs/heads/main/start.sh" -o "$BASE/start.sh"
chmod +x "$BASE/start.sh"
echo "[CSKStart] start.sh installed/updated."

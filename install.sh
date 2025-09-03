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
export HOME="$BASE"

mkdir -p "$BASE/.ssh"
chmod 700 "$BASE/.ssh"

if [ -n "${REMOTE_SSH_KEY:-}" ]; then
  RAW="$REMOTE_SSH_KEY"
  FIXED="$RAW"
  did_fix="false"

  if printf "%s" "$RAW" | grep -q '\\n'; then
    echo "[CSKStart] WARNING: SSH key contains literal \\n; converting to real newlines."
    FIXED="$(printf "%b" "$RAW")"
    did_fix="true"
  fi

  if ! printf "%s" "$FIXED" | grep -q '-----BEGIN OPENSSH PRIVATE KEY-----' || \
     ! printf "%s" "$FIXED" | grep -q '-----END OPENSSH PRIVATE KEY-----' || \
     [ "$(printf "%s" "$FIXED" | wc -l)" -le 2 ] || \
     printf "%s" "$FIXED" | grep -q ' [[:alnum:]/+=]' ; then
    echo "[CSKStart] WARNING: SSH key appears single-line or with extra spaces; reformatting."
    FIXED="$(printf "%s" "$FIXED" | tr -d '\r')"
    BODY="$(printf "%s" "$FIXED" \
      | sed 's/-----BEGIN OPENSSH PRIVATE KEY-----//g' \
      | sed 's/-----END OPENSSH PRIVATE KEY-----//g')"
    BODY="$(printf "%s" "$BODY" | tr -d '[:space:]')"
    BODY="$(printf "%s" "$BODY" | fold -w 64)"
    FIXED="-----BEGIN OPENSSH PRIVATE KEY-----\n${BODY}\n-----END OPENSSH PRIVATE KEY-----"
    did_fix="true"
  fi

  printf "%b\n" "$FIXED" > "$BASE/.ssh/id_ed25519"
  sed -i 's/\r$//' "$BASE/.ssh/id_ed25519"
  chmod 600 "$BASE/.ssh/id_ed25519"

  if [ "$did_fix" = "true" ]; then
    echo "[CSKStart] NOTICE: SSH key auto-fixed. If problems persist, paste it exactly as multi-line OpenSSH."
  fi
fi

ssh-keyscan -t ed25519 github.com >> "$BASE/.ssh/known_hosts" 2>/dev/null || true
chmod 644 "$BASE/.ssh/known_hosts"

git config --global --add safe.directory "$BASE" || true
git config --global --add safe.directory /mnt/server || true
unset GIT_DIR GIT_WORK_TREE

if [ -n "${REMOTE_GIT:-}" ]; then
  BRANCH="${REMOTE_BRANCH:-main}"
  if [ -f "$BASE/.ssh/id_ed25519" ]; then
    export GIT_SSH_COMMAND='ssh -i /home/container/.ssh/id_ed25519 -o IdentitiesOnly=yes -o UserKnownHostsFile=/home/container/.ssh/known_hosts -o StrictHostKeyChecking=accept-new'
  else
    echo "[CSKStart] WARNING: REMOTE_SSH_KEY missing. Using default SSH agent (may fail)."
    export GIT_SSH_COMMAND='ssh -o UserKnownHostsFile=/home/container/.ssh/known_hosts -o StrictHostKeyChecking=accept-new'
  fi

  echo "[CSKStart] Cleaning and fetching fresh repo ($BRANCH)..."
  tmpdir="$(mktemp -d)"
  git -C "$tmpdir" init -q
  git -C "$tmpdir" remote add origin "$REMOTE_GIT"
  if ! git -C "$tmpdir" fetch --depth=1 origin "$BRANCH" -q; then
    git -C "$tmpdir" fetch --depth=1 origin -q
    def_ref="$(git -C "$tmpdir" symbolic-ref -q refs/remotes/origin/HEAD || true)"
    def_branch="${def_ref#refs/remotes/origin/}"
    [ -n "$def_branch" ] || def_branch="master"
    BRANCH="$def_branch"
  fi
  git -C "$tmpdir" checkout -B "$BRANCH" "origin/$BRANCH" -q

  shopt -s dotglob nullglob
  rm -rf "$BASE"/* || true
  mv "$tmpdir"/* "$BASE"/
  rm -rf "$tmpdir"
fi

curl -fsSL "https://raw.githubusercontent.com/CoderskyNetwork/CSKStart/refs/heads/main/start.sh" -o "$BASE/start.sh"
chmod +x "$BASE/start.sh"
echo "[CSKStart] start.sh installed/updated."

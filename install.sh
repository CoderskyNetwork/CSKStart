#!/bin/bash
set -e

if command -v apk >/dev/null 2>&1; then
  apk add --no-cache git openssh-client curl jq
elif command -v apt-get >/dev/null 2>&1; then
  apt-get update && apt-get install -y git openssh-client curl jq && rm -rf /var/lib/apt/lists/*
fi

cd /home/container

if [ -n "${REMOTE_SSH_KEY:-}" ]; then
  mkdir -p /home/container/.ssh
  chmod 700 /home/container/.ssh
  printf "%s\n" "${REMOTE_SSH_KEY}" > /home/container/.ssh/id_ed25519
  chmod 600 /home/container/.ssh/id_ed25519
  ssh-keyscan github.com >> /home/container/.ssh/known_hosts 2>/dev/null || true
  chmod 644 /home/container/.ssh/known_hosts
fi

if [ -n "${REMOTE_GIT:-}" ] && [ ! -d .git ]; then
  BRANCH="${REMOTE_BRANCH:-main}"
  if [ -f /home/container/.ssh/id_ed25519 ]; then
    GIT_SSH_COMMAND='ssh -i /home/container/.ssh/id_ed25519 -o IdentitiesOnly=yes' \
      git clone --depth=1 --branch "$BRANCH" "$REMOTE_GIT" /home/container
  else
    echo "[CSKStart] WARNING: REMOTE_GIT is set but REMOTE_SSH_KEY is missing. Clone skipped."
  fi
fi

curl -fsSL "https://raw.githubusercontent.com/CoderskyNetwork/CSKStart/refs/heads/main/start.sh" -o /home/container/start.sh
chmod +x /home/container/start.sh
echo "[CSKStart] start.sh installed from remote."

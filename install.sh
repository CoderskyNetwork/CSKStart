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

resolve_target_branch() {
  local desired="${REMOTE_BRANCH:-main}"
  if git show-ref --verify --quiet "refs/remotes/origin/${desired}"; then
    echo "$desired"
    return
  fi
  local def
  def="$(git symbolic-ref -q refs/remotes/origin/HEAD 2>/dev/null || true)"
  def="${def#refs/remotes/origin/}"
  if [ -n "$def" ] && git show-ref --verify --quiet "refs/remotes/origin/${def}"; then
    echo "$def"
    return
  fi
  if git show-ref --verify --quiet "refs/remotes/origin/master"; then
    echo "master"
    return
  fi
  echo "${desired}"
}

if [ -n "${REMOTE_GIT:-}" ]; then
  BRANCH="${REMOTE_BRANCH:-main}"
  if [ -f "$BASE/.ssh/id_ed25519" ]; then
    export GIT_SSH_COMMAND='ssh -i /home/container/.ssh/id_ed25519 -o IdentitiesOnly=yes'
  else
    echo "[CSKStart] WARNING: REMOTE_GIT is set but REMOTE_SSH_KEY is missing. Using default SSH agent (may fail)."
  fi

  if [ -d ".git" ]; then
    echo "[CSKStart] GIT: repository found. Updating $BRANCH..."
    git remote get-url origin >/dev/null 2>&1 || git remote add origin "$REMOTE_GIT"
    git remote set-url origin "$REMOTE_GIT"
    git fetch --prune --depth=1 origin -q
    TARGET="$(resolve_target_branch)"
    git checkout -B "$TARGET" "origin/$TARGET" -q || git checkout -B "$TARGET" -q
    git reset --hard "origin/${TARGET}" -q || true
    git submodule update --init --recursive -q || true

  else
    if [ -z "$(ls -A "$BASE" 2>/dev/null)" ]; then
      echo "[CSKStart] GIT: empty dir. Cloning $BRANCH..."
      git clone --depth=1 --branch "$BRANCH" "$REMOTE_GIT" "$BASE"
    else
      echo "[CSKStart] GIT: non-empty dir without .git. Initializing in-place on $BRANCH..."
      git init -q
      git remote remove origin 2>/dev/null || true
      git remote add origin "$REMOTE_GIT"
      git fetch --depth=1 origin "$BRANCH" -q || git fetch --depth=1 origin -q
      TARGET="$(resolve_target_branch)"
      git checkout -B "$TARGET" "origin/$TARGET" -q
      git reset --hard "origin/$TARGET" -q
      git submodule update --init --recursive -q || true
    fi
  fi
fi

curl -fsSL "https://raw.githubusercontent.com/CoderskyNetwork/CSKStart/refs/heads/main/start.sh" -o "$BASE/start.sh"
chmod +x "$BASE/start.sh"
echo "[CSKStart] start.sh installed/updated."

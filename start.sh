#!/usr/bin/env bash
set -euo pipefail
cd /home/container
export HOME="/home/container"

SERVER_TYPE="${SERVER_TYPE:-paper}"
VERSION="${VERSION:-latest}"
REMOTE_GIT="${REMOTE_GIT:-}"
REMOTE_BRANCH="${REMOTE_BRANCH:-main}"
MEM_MB="${SERVER_MEMORY:-1024}"
JVM_FLAGS="${JVM_FLAGS:-}"
JAR_FLAGS="${JAR_FLAGS:-}"
USER_AGENT="cskstart/1.0"
JAR_NAME="server.jar"

AIKAR_FLAGS='-XX:+AlwaysPreTouch -XX:+DisableExplicitGC -XX:+ParallelRefProcEnabled -XX:+PerfDisableSharedMem -XX:+UnlockExperimentalVMOptions -XX:+UseG1GC -XX:G1HeapRegionSize=8M -XX:G1HeapWastePercent=5 -XX:G1MaxNewSizePercent=40 -XX:G1MixedGCCountTarget=4 -XX:G1MixedGCLiveThresholdPercent=90 -XX:G1NewSizePercent=30 -XX:G1RSetUpdatingPauseTimePercent=5 -XX:G1ReservePercent=20 -XX:InitiatingHeapOccupancyPercent=15 -XX:MaxGCPauseMillis=200 -XX:MaxTenuringThreshold=1 -XX:SurvivorRatio=32 -Dusing.aikars.flags=https://mcflags.emc.gs -Daikars.new.flags=true'
JVM_FLAGS="${JVM_FLAGS//\$AIKAR/$AIKAR_FLAGS}"

memXmx="-Xmx${MEM_MB}M"
memXms="-Xms${MEM_MB}M"

# Optional Git pull on boot (admin-configured)
if [[ -n "$REMOTE_GIT" && -d .git ]]; then
  echo "[CSKStart] Updating ${REMOTE_BRANCH} from ${REMOTE_GIT}..."
  if [[ -f /home/container/.ssh/id_ed25519 ]]; then
    export GIT_SSH_COMMAND='ssh -i /home/container/.ssh/id_ed25519 -o IdentitiesOnly=yes -o UserKnownHostsFile=/home/container/.ssh/known_hosts -o StrictHostKeyChecking=accept-new'
    git config --global --add safe.directory /home/container || true
    git fetch --all -q || true
    git reset --hard "origin/${REMOTE_BRANCH}" -q || true
    git submodule update --init --recursive -q || true
  else
    echo "[CSKStart] WARNING: REMOTE_SSH_KEY is not installed; git pull skipped."
  fi
elif [[ -n "$REMOTE_GIT" && ! -d .git ]]; then
  echo "[CSKStart] WARNING: REMOTE_GIT is set but .git is missing. Reinstall or clone manually."
fi

# --- Helpers without jq ---
json_get_array_last() {
  # $1: key name, reads JSON from stdin (single-line or multi-line)
  # prints last element (without quotes)
  tr -d '\n' | sed -n "s/.*\"$1\":[[]\([^]]]*\)].*/\1/p" | awk -F',' '{gsub(/^[ \t"]+|[ \t"]+$/, "", $NF); gsub(/^"|"$/, "", $NF); print $NF}'
}

api_get() {
  # $1: url
  curl -fsSL -H "User-Agent: ${USER_AGENT}" "$1"
}

resolve_version() {
  local project="$1"
  if [[ "$VERSION" == "latest" ]]; then
    api_get "https://api.papermc.io/v2/projects/${project}" | json_get_array_last "versions"
  else
    echo "$VERSION"
  fi
}

resolve_build() {
  local project="$1" ver="$2"
  api_get "https://api.papermc.io/v2/projects/${project}/versions/${ver}" | json_get_array_last "builds"
}

download_jar() {
  local project="$1" ver="$2" build="$3" file="${project}-${ver}-${build}.jar"
  local url="https://api.papermc.io/v2/projects/${project}/versions/${ver}/builds/${build}/downloads/${file}"
  echo "[DL] Downloading ${file}..."
  curl -fL -o "${JAR_NAME}" "$url"
}

if [[ ! -f "${JAR_NAME}" ]]; then
  case "$SERVER_TYPE" in
    paper|velocity)
      ver="$(resolve_version "$SERVER_TYPE" || true)"
      build="$(resolve_build "$SERVER_TYPE" "$ver" || true)"
      if [[ -z "${ver:-}" || -z "${build:-}" || "$ver" == "null" || "$build" == "null" ]]; then
        echo "[CSKStart] ERROR: Unable to resolve version/build for ${SERVER_TYPE}."
        exit 1
      fi
      download_jar "$SERVER_TYPE" "$ver" "$build"
      ;;
    *)
      echo "[CSKStart] ERROR: Invalid SERVER_TYPE: ${SERVER_TYPE}. Use paper or velocity."
      exit 1
      ;;
  esac
fi

if [[ "$SERVER_TYPE" == "paper" ]]; then
  [[ -f eula.txt ]] || { echo "eula=true" > eula.txt; echo "[EULA] Accepted."; }
fi

echo "[CSKStart] Starting ${SERVER_TYPE} with ${MEM_MB} MB..."
exec java ${memXmx} ${memXms} ${JVM_FLAGS} -jar "${JAR_NAME}" ${JAR_FLAGS}

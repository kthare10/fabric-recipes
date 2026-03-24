#!/usr/bin/env bash
set -euo pipefail

# ---------- tiny logger ----------
log() { printf '[%(%H:%M:%S)T] %s\n' -1 "$*"; }

# ---------- usage (no heredoc) ----------
usage() {
  printf '%s\n' \
"Usage:" \
"  ./setup_ship.sh --token TOKEN --hosts \"IP@name[%srcIP] ...\" --urls \"https://a/ps,https://b/ps\"" \
"                 [--workdir PATH] [--archiver-repo URL] [--psx-repo URL]" \
"                 [--archiver-branch BRANCH] [--psx-branch BRANCH]" \
"                 [--no-sudo] [--verbose]" \
"" \
"Host format:" \
"  ip@name              — single network (backward compatible)" \
"  ip@name%src_ip       — multi-network: bind pscheduler --source to src_ip" \
"  ip@name%iface        — multi-network: resolve iface IP at runtime, bind --source" \
"" \
"Defaults:" \
"  --workdir            \$PWD" \
"  --archiver-repo      https://github.com/kthare10/pscheduler-result-archiver.git" \
"  --psx-repo           https://github.com/kthare10/perfsonar-extensions.git" \
"  --archiver-branch    main" \
"  --psx-branch         main" \
"" \
"Examples:" \
"  # Single network" \
"  ./setup_ship.sh --token \"\$TOKEN\" \\" \
"                 --hosts \"23.134.232.50@shore-STAR\" \\" \
"                 --urls \"https://localhost:8443/ps,https://23.134.232.50:8443/ps\"" \
"" \
"  # Multi-network (2 NICs, each on a different L3 network)" \
"  ./setup_ship.sh --token \"\$TOKEN\" \\" \
"                 --hosts \"10.129.133.2@shore-net1%10.135.145.2 10.129.134.2@shore-net2%10.135.146.2\" \\" \
"                 --urls \"https://localhost:8443/ps,https://10.129.133.2:8443/ps\"" \
""
  exit 1
}

# ---------- defaults ----------
WORKDIR="$(pwd)"
ARCHIVER_REPO="https://github.com/kthare10/pscheduler-result-archiver.git"
PSX_REPO="https://github.com/kthare10/perfsonar-extensions.git"
ARCHIVER_BRANCH="main"
PSX_BRANCH="main"
USE_SUDO=1
VERBOSE=0

TOKEN=""
HOSTS=""
URLS=""

# ---------- argparse ----------
while [[ $# -gt 0 ]]; do
  case "${1:-}" in
    --token) TOKEN="${2:-}"; shift 2 ;;
    --hosts) HOSTS="${2:-}"; shift 2 ;;
    --urls|--archive-urls) URLS="${2:-}"; shift 2 ;;
    --workdir) WORKDIR="${2:-}"; shift 2 ;;
    --archiver-repo) ARCHIVER_REPO="${2:-}"; shift 2 ;;
    --psx-repo) PSX_REPO="${2:-}"; shift 2 ;;
    --archiver-branch) ARCHIVER_BRANCH="${2:-}"; shift 2 ;;
    --psx-branch) PSX_BRANCH="${2:-}"; shift 2 ;;
    --no-sudo) USE_SUDO=0; shift ;;
    --verbose|-v) VERBOSE=1; shift ;;
    -h|--help) usage ;;
    *) printf 'Unknown arg: %s\n' "${1:-}"; usage ;;
  esac
done

[[ -z "$TOKEN" || -z "$HOSTS" || -z "$URLS" ]] && { printf 'ERROR: --token, --hosts, and --urls are required.\n'; usage; }
[[ $VERBOSE -eq 1 ]] && set -x

# ---------- sudo helper ----------
SUDO=""
if [[ $USE_SUDO -eq 1 ]]; then
  if command -v sudo >/dev/null 2>&1; then
    SUDO="sudo"
  else
    log "WARN: --no-sudo implied (sudo not found)"
  fi
fi

# ---------- prereqs ----------
need() { command -v "$1" >/dev/null 2>&1 || { printf "ERROR: '%s' is required.\n" "$1"; exit 1; }; }
need git
need python3
need awk
need sed

# ---------- helpers ----------
clone_or_update() {
  local repo_url="$1" dest_dir="$2" branch="$3"
  if [[ -d "$dest_dir/.git" ]]; then
    log "Updating $dest_dir (branch: $branch)"
    git -C "$dest_dir" fetch --all --prune
    git -C "$dest_dir" checkout "$branch"
    git -C "$dest_dir" pull --ff-only
  else
    log "Cloning $repo_url -> $dest_dir (branch: $branch)"
    git clone --branch "$branch" --depth 1 "$repo_url" "$dest_dir"
  fi
}

# ---------- run ----------
mkdir -p "$WORKDIR"
cd "$WORKDIR"

# 1) pscheduler-result-archiver
ARCHIVER_DIR="${WORKDIR}/pscheduler-result-archiver"
clone_or_update "$ARCHIVER_REPO" "$ARCHIVER_DIR" "$ARCHIVER_BRANCH"

log "Enable Docker (archiver)"
$SUDO bash "$ARCHIVER_DIR/scripts/enable_docker.sh"

ARCHIVER_CFG="${ARCHIVER_DIR}/archiver/config.yml"
[[ -f "$ARCHIVER_CFG" ]] || { printf 'ERROR: Missing %s\n' "$ARCHIVER_CFG"; exit 1; }
log "Update archiver config token"
python3 "$ARCHIVER_DIR/scripts/archiver_update_config.py" "$ARCHIVER_CFG" --token "$TOKEN" --no-up

# Generate .env for docker-compose (required: ARCHIVER_DB_PASSWORD, ARCHIVER_BEARER_TOKEN, GRAFANA_ADMIN_PASSWORD)
ARCHIVER_ENV="${ARCHIVER_DIR}/.env"
if [[ ! -f "$ARCHIVER_ENV" ]]; then
  log "Creating .env for archiver docker-compose"
  DB_PASS="$(openssl rand -hex 16)"
  cat > "$ARCHIVER_ENV" <<ENVEOF
ARCHIVER_DB_PASSWORD=${DB_PASS}
ARCHIVER_BEARER_TOKEN=${TOKEN}
GRAFANA_ADMIN_USER=admin
GRAFANA_ADMIN_PASSWORD=perfsonar
ENVEOF
  log "Generated .env (Grafana login: admin/perfsonar)"
else
  log ".env already exists; updating bearer token"
  sed -i "s|^ARCHIVER_BEARER_TOKEN=.*|ARCHIVER_BEARER_TOKEN=${TOKEN}|" "$ARCHIVER_ENV"
fi

# Launch the archiver stack from the repo root (where docker-compose.yml lives)
log "docker compose up -d (archiver stack)"
( cd "$ARCHIVER_DIR" && docker compose up -d )

# 2) perfsonar-extensions
PSX_DIR="${WORKDIR}/perfsonar-extensions"
clone_or_update "$PSX_REPO" "$PSX_DIR" "$PSX_BRANCH"

ENV_SRC="${PSX_DIR}/docker/env.template"
ENV_DST="${PSX_DIR}/docker/.env"
[[ -f "$ENV_SRC" ]] || { printf 'ERROR: Missing %s\n' "$ENV_SRC"; exit 1; }

if [[ -f "$ENV_DST" ]]; then
  log ".env exists; leaving as-is"
else
  log "Creating .env from template"
  cp "$ENV_SRC" "$ENV_DST"
fi

log "Populate .env via setup_env.py"
( cd "${PSX_DIR}/docker" && python3 scripts/setup_env.py ".env" "$TOKEN" --hosts "$HOSTS" --archive-urls "$URLS" )

# 3) Launch stack
log "docker compose up -d (testpoint)"
( cd "${PSX_DIR}/docker" && docker compose -f docker-compose-testpoint.yml up -d )

# Wait for testpoint container to be running and healthy
log "Waiting for perfsonar-testpoint container to start..."
for i in $(seq 1 30); do
  if docker inspect --format='{{.State.Running}}' perfsonar-testpoint 2>/dev/null | grep -q true; then
    log "perfsonar-testpoint is running."
    break
  fi
  sleep 2
done

log "Done."
printf '%s\n' \
"Repos:" \
"  - $ARCHIVER_DIR" \
"  - $PSX_DIR" \
"" \
"Next:" \
"  docker ps" \
"  docker compose -f ${PSX_DIR}/docker/docker-compose-testpoint.yml logs -f"

#!/usr/bin/env bash
set -euo pipefail

# --------------------------------------------------------------------------
# validate_deployment.sh — Verify Docker deployment on a shore or ship node
#
# Usage:
#   ./validate_deployment.sh --role shore --token TOKEN
#   ./validate_deployment.sh --role ship  --token TOKEN [--nmea]
# --------------------------------------------------------------------------

log() { printf '[%(%H:%M:%S)T] %s\n' -1 "$*"; }

ROLE=""
TOKEN=""
ENABLE_NMEA=0

while [[ $# -gt 0 ]]; do
  case "${1:-}" in
    --role)  ROLE="${2:-}";  shift 2 ;;
    --token) TOKEN="${2:-}"; shift 2 ;;
    --nmea)  ENABLE_NMEA=1; shift ;;
    -h|--help)
      printf '%s\n' \
        "Usage: ./validate_deployment.sh --role shore|ship --token TOKEN [--nmea]" \
        "" \
        "Options:" \
        "  --role   shore or ship" \
        "  --token  Archiver bearer token" \
        "  --nmea   Include NMEA listener checks (ship only)"
      exit 0 ;;
    *) printf 'Unknown arg: %s\n' "${1:-}"; exit 1 ;;
  esac
done

[[ -z "$ROLE" || -z "$TOKEN" ]] && { printf 'ERROR: --role and --token are required.\n'; exit 1; }
[[ "$ROLE" != "shore" && "$ROLE" != "ship" ]] && { printf 'ERROR: --role must be shore or ship.\n'; exit 1; }

PASS=0
FAIL=0
check() {
  local label="$1" ok="$2"
  if [[ "$ok" == "1" ]]; then
    printf '  [PASS] %s\n' "$label"
    ((PASS++))
  else
    printf '  [FAIL] %s\n' "$label"
    ((FAIL++))
  fi
}

SEP="======================================================================"

printf '%s\n' "$SEP"
printf '%s VM — Docker Deployment Validation\n' "$(echo "$ROLE" | tr '[:lower:]' '[:upper:]')"
printf '%s\n' "$SEP"

# --- 1. Container Status ---
printf '\n--- 1. Container Status ---\n'
sudo docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'

EXPECTED="timescaledb grafana archiver archiver-nginx"
if [[ "$ROLE" == "ship" ]]; then
  EXPECTED="$EXPECTED perfsonar-testpoint"
  if [[ "$ENABLE_NMEA" -eq 1 ]]; then
    EXPECTED="$EXPECTED nmea-listener"
  fi
fi

RUNNING="$(sudo docker ps --format '{{.Names}}')"
for c in $EXPECTED; do
  echo "$RUNNING" | grep -qw "$c" && ok=1 || ok=0
  check "Container '$c' running" "$ok"
done

# --- 2. Container Health ---
printf '\n--- 2. Container Health ---\n'
for c in $EXPECTED; do
  health="$(sudo docker inspect --format='{{.State.Health.Status}}' "$c" 2>/dev/null || echo 'no-healthcheck')"
  printf '  %s: %s\n' "$c" "$health"
done

# --- 3. TimescaleDB Connectivity ---
printf '\n--- 3. TimescaleDB Connectivity ---\n'
pg_out="$(sudo docker exec timescaledb pg_isready -U grafana_writer -d perfsonar 2>&1)"
echo "$pg_out" | grep -q "accepting connections" && ok=1 || ok=0
check "pg_isready" "$ok"
printf '  %s\n' "$pg_out"

# --- 4. Database Tables ---
printf '\n--- 4. Database Tables ---\n'
sudo docker exec timescaledb psql -U grafana_writer -d perfsonar \
  -c "SELECT tablename FROM pg_tables WHERE schemaname='public';"

if [[ "$ENABLE_NMEA" -eq 1 ]]; then
  printf '\n  nav_data table columns:\n'
  sudo docker exec timescaledb psql -U grafana_writer -d perfsonar \
    -c "SELECT column_name, data_type FROM information_schema.columns WHERE table_name='nav_data' ORDER BY ordinal_position;"
fi

# --- 5. Archiver API Health ---
printf '\n--- 5. Archiver API Health ---\n'
health_resp="$(curl -sk https://localhost:8443/ps/health)"
echo "$health_resp" | grep -qi "ok\|healthy\|running" && ok=1 || ok=0
check "Health endpoint" "$ok"
printf '  Response: %s\n' "$health_resp"

# --- 6. Archiver API Auth ---
printf '\n--- 6. Archiver API Auth Test ---\n'
http_noauth="$(curl -sk -o /dev/null -w '%{http_code}' https://localhost:8443/ps/measurements/latency)"
printf '  POST without token → HTTP %s (expect 401/403)\n' "$http_noauth"
[[ "$http_noauth" == "401" || "$http_noauth" == "403" ]] && ok=1 || ok=0
check "Rejects unauthenticated request" "$ok"

http_auth="$(curl -sk -o /dev/null -w '%{http_code}' -H "Authorization: Bearer $TOKEN" https://localhost:8443/ps/measurements/latency)"
printf '  POST with token    → HTTP %s (expect non-401)\n' "$http_auth"
[[ "$http_auth" != "401" ]] && ok=1 || ok=0
check "Accepts authenticated request" "$ok"

# --- 7. Grafana ---
printf '\n--- 7. Grafana Accessibility ---\n'
http_grafana="$(curl -sk -o /dev/null -w '%{http_code}' https://localhost:8443/)"
printf '  Grafana HTTPS → HTTP %s\n' "$http_grafana"
[[ "$http_grafana" == "200" || "$http_grafana" == "302" ]] && ok=1 || ok=0
check "Grafana reachable" "$ok"

# --- 8. NGINX TLS ---
printf '\n--- 8. NGINX TLS Check ---\n'
tls_out="$(curl -svk https://localhost:8443/ps/health 2>&1 | grep -i 'SSL connection' || echo 'no SSL info')"
printf '  %s\n' "$tls_out"

# --- Ship-specific checks ---
if [[ "$ROLE" == "ship" ]]; then
  printf '\n--- 9. perfSONAR Testpoint — pScheduler Status ---\n'
  ps_ping="$(sudo docker exec perfsonar-testpoint pscheduler ping 2>&1 || echo 'pscheduler ping failed')"
  echo "$ps_ping" | grep -qi "alive\|pong\|ok" && ok=1 || ok=0
  check "pScheduler responding" "$ok"
  printf '  %s\n' "$ps_ping"

  printf '\n--- 10. perfSONAR Testpoint — Cron Job ---\n'
  cron_out="$(sudo docker exec perfsonar-testpoint cat /etc/cron.d/perfsonar_tests 2>/dev/null \
    || sudo docker exec perfsonar-testpoint crontab -l 2>/dev/null \
    || echo 'No cron found')"
  printf '  %s\n' "$cron_out"

  printf '\n--- 11. perfSONAR Testpoint — Environment Config ---\n'
  for var in HOSTS ARCHIVE_URLS CRON_EXPRESSION; do
    val="$(sudo docker exec perfsonar-testpoint printenv "$var" 2>/dev/null || echo 'NOT SET')"
    printf '  %s=%s\n' "$var" "$val"
  done

  if [[ "$ENABLE_NMEA" -eq 1 ]]; then
    printf '\n--- 12. NMEA Listener Status ---\n'
    nmea_logs="$(sudo docker logs --tail 10 nmea-listener 2>&1 || echo 'nmea-listener container not found')"
    printf '  %s\n' "$nmea_logs"
  fi
fi

# --- Summary ---
printf '\n%s\n' "$SEP"
printf 'Results: %d PASS, %d FAIL\n' "$PASS" "$FAIL"
printf '%s\n' "$SEP"

[[ "$FAIL" -eq 0 ]] && exit 0 || exit 1

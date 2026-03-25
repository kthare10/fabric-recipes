#!/usr/bin/env bash
set -euo pipefail

# --------------------------------------------------------------------------
# validate_cross.sh — Cross-connectivity tests between ship and remote node
#
# Run on the SHIP node to verify connectivity to the shore archiver and
# pScheduler reachability.
#
# Usage:
#   ./validate_cross.sh --token TOKEN --remote-ip SHORE_IP [--src-ips "IP1 IP2"]
# --------------------------------------------------------------------------

log() { printf '[%(%H:%M:%S)T] %s\n' -1 "$*"; }

TOKEN=""
REMOTE_IP=""
SRC_IPS=""

while [[ $# -gt 0 ]]; do
  case "${1:-}" in
    --token)     TOKEN="${2:-}";     shift 2 ;;
    --remote-ip) REMOTE_IP="${2:-}"; shift 2 ;;
    --src-ips)   SRC_IPS="${2:-}";   shift 2 ;;
    -h|--help)
      printf '%s\n' \
        "Usage: ./validate_cross.sh --token TOKEN --remote-ip SHORE_IP [--src-ips \"IP1 IP2\"]" \
        "" \
        "Options:" \
        "  --remote-ip  Shore/remote node IP" \
        "  --token      Archiver bearer token" \
        "  --src-ips    Space-separated list of local source IPs to test (optional)"
      exit 0 ;;
    *) printf 'Unknown arg: %s\n' "${1:-}"; exit 1 ;;
  esac
done

[[ -z "$TOKEN" || -z "$REMOTE_IP" ]] && { printf 'ERROR: --token and --remote-ip are required.\n'; exit 1; }

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
printf 'CROSS-CONNECTIVITY TESTS — Local → %s\n' "$REMOTE_IP"
printf '%s\n' "$SEP"

# --- 1. Ping tests ---
printf '\n--- 1. Network Ping ---\n'
if [[ -n "$SRC_IPS" ]]; then
  for src_ip in $SRC_IPS; do
    ping_out="$(ping -I "$src_ip" -c 3 "$REMOTE_IP" 2>&1 || true)"
    echo "$ping_out" | grep -q ' 0% packet loss' && ok=1 || ok=0
    check "Ping ${src_ip} → ${REMOTE_IP}" "$ok"
  done
else
  ping_out="$(ping -c 3 "$REMOTE_IP" 2>&1 || true)"
  echo "$ping_out" | grep -q ' 0% packet loss' && ok=1 || ok=0
  check "Ping → ${REMOTE_IP}" "$ok"
fi

# --- 2. Remote archiver health ---
printf '\n--- 2. Remote Archiver Health ---\n'
http_health="$(curl -sk -o /dev/null -w '%{http_code}' -H "Authorization: Bearer $TOKEN" "https://${REMOTE_IP}:8443/ps/health" 2>/dev/null || echo '000')"
printf '  Remote archiver health → HTTP %s\n' "$http_health"
[[ "$http_health" == "200" ]] && ok=1 || ok=0
check "Remote archiver reachable" "$ok"

# --- 3. pScheduler reachability ---
printf '\n--- 3. pScheduler Reachability ---\n'
if sudo docker inspect perfsonar-testpoint >/dev/null 2>&1; then
  ps_out="$(sudo docker exec perfsonar-testpoint pscheduler ping "$REMOTE_IP" 2>&1 || echo 'pscheduler ping failed')"
  echo "$ps_out" | grep -qi "alive\|pong\|ok" && ok=1 || ok=0
  check "pScheduler ping → ${REMOTE_IP}" "$ok"
  printf '  %s\n' "$ps_out"
else
  printf '  Skipped (perfsonar-testpoint container not running)\n'
fi

# --- 4. Docker resource usage ---
printf '\n--- 4. Docker Resource Usage ---\n'
sudo docker stats --no-stream --format 'table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}'

# --- Summary ---
printf '\n%s\n' "$SEP"
printf 'Results: %d PASS, %d FAIL\n' "$PASS" "$FAIL"
printf '%s\n' "$SEP"

[[ "$FAIL" -eq 0 ]] && exit 0 || exit 1

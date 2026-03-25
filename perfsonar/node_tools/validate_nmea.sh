#!/usr/bin/env bash
set -euo pipefail

# --------------------------------------------------------------------------
# validate_nmea.sh — Run NMEA simulation and verify the full pipeline
#
# 1. Runs the NMEA simulator (UDP → nmea-listener container)
# 2. Checks TimescaleDB for ingested nav_data rows
# 3. Tests the GET /nav and POST /measurements/nav API endpoints
# 4. Optionally checks a remote archiver for replicated data
#
# Usage:
#   ./validate_nmea.sh --token TOKEN [--sim-script PATH] [--sim-port PORT]
#                      [--sim-duration SEC] [--remote-ip SHORE_IP]
# --------------------------------------------------------------------------

log() { printf '[%(%H:%M:%S)T] %s\n' -1 "$*"; }

TOKEN=""
SIM_SCRIPT="perfsonar-extensions/nmea-listener/nmea_sim.py"
SIM_PORT=13551
SIM_DURATION=30
REMOTE_IP=""

while [[ $# -gt 0 ]]; do
  case "${1:-}" in
    --token)        TOKEN="${2:-}";        shift 2 ;;
    --sim-script)   SIM_SCRIPT="${2:-}";   shift 2 ;;
    --sim-port)     SIM_PORT="${2:-}";     shift 2 ;;
    --sim-duration) SIM_DURATION="${2:-}"; shift 2 ;;
    --remote-ip)    REMOTE_IP="${2:-}";    shift 2 ;;
    -h|--help)
      printf '%s\n' \
        "Usage: ./validate_nmea.sh --token TOKEN [options]" \
        "" \
        "Options:" \
        "  --sim-script    Path to nmea_sim.py (default: perfsonar-extensions/nmea-listener/nmea_sim.py)" \
        "  --sim-port      UDP port (default: 13551)" \
        "  --sim-duration  Seconds to run simulator (default: 30)" \
        "  --remote-ip     Shore IP to check remote archiving (optional)"
      exit 0 ;;
    *) printf 'Unknown arg: %s\n' "${1:-}"; exit 1 ;;
  esac
done

[[ -z "$TOKEN" ]] && { printf 'ERROR: --token is required.\n'; exit 1; }

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
printf 'NMEA NAV DATA — Simulation & Validation\n'
printf '%s\n' "$SEP"

# --- 0. Check prerequisites ---
printf '\n--- 0. Prerequisites ---\n'
if [[ ! -f "$SIM_SCRIPT" ]]; then
  printf '  ERROR: Simulator script not found: %s\n' "$SIM_SCRIPT"
  exit 1
fi
check "Simulator script exists" "1"

running="$(sudo docker ps --format '{{.Names}}')"
echo "$running" | grep -qw "nmea-listener" && ok=1 || ok=0
check "nmea-listener container running" "$ok"
if [[ "$ok" -eq 0 ]]; then
  printf '  ERROR: nmea-listener must be running before validation.\n'
  exit 1
fi

# --- 1. Run NMEA simulator ---
printf '\n--- 1. Running NMEA Simulator (%ss on port %s) ---\n' "$SIM_DURATION" "$SIM_PORT"
python3 "$SIM_SCRIPT" "$SIM_PORT" "$SIM_DURATION"

# Wait for the listener to flush its last batch
printf '\n  Waiting 8s for listener to flush...\n'
sleep 8

# --- 2. NMEA Listener Logs ---
printf '\n--- 2. NMEA Listener Logs (last 20 lines) ---\n'
sudo docker logs --tail 20 nmea-listener 2>&1

# --- 3. nav_data Row Count ---
printf '\n--- 3. nav_data Row Count ---\n'
count="$(sudo docker exec timescaledb psql -U grafana_writer -d perfsonar -t \
  -c "SELECT COUNT(*) FROM nav_data;" | tr -d ' ')"
printf '  Rows in nav_data: %s\n' "$count"
[[ "$count" -gt 0 ]] && ok=1 || ok=0
check "nav_data has rows" "$ok"

# --- 4. Sample rows ---
printf '\n--- 4. Sample nav_data Rows ---\n'
sudo docker exec timescaledb psql -U grafana_writer -d perfsonar \
  -c "SELECT ts, vessel_id, latitude, longitude, heading_true, roll_deg, pitch_deg, heave_m FROM nav_data ORDER BY ts DESC LIMIT 5;"

# --- 5. GPS data integrity (GGA parsing) ---
printf '\n--- 5. GPS Data Integrity ---\n'
gps_count="$(sudo docker exec timescaledb psql -U grafana_writer -d perfsonar -t \
  -c "SELECT COUNT(*) FROM nav_data WHERE latitude IS NOT NULL AND longitude IS NOT NULL;" | tr -d ' ')"
printf '  Rows with GPS position: %s\n' "$gps_count"
[[ "$gps_count" -gt 0 ]] && ok=1 || ok=0
check "GGA parsing (lat/lon present)" "$ok"

# --- 6. Motion data integrity (PSXN,23 parsing) ---
printf '\n--- 6. Motion Data Integrity ---\n'
motion_count="$(sudo docker exec timescaledb psql -U grafana_writer -d perfsonar -t \
  -c "SELECT COUNT(*) FROM nav_data WHERE roll_deg IS NOT NULL AND pitch_deg IS NOT NULL;" | tr -d ' ')"
printf '  Rows with roll/pitch: %s\n' "$motion_count"
[[ "$motion_count" -gt 0 ]] && ok=1 || ok=0
check "PSXN,23 parsing (roll/pitch present)" "$ok"

# --- 7. GET /nav API endpoint ---
printf '\n--- 7. GET /nav API Response ---\n'
api_out="$(curl -sk -H "Authorization: Bearer $TOKEN" 'https://localhost:8443/ps/nav?limit=3' 2>/dev/null)"
echo "$api_out" | python3 -m json.tool 2>/dev/null | head -40 || printf '  %s\n' "$api_out"
echo "$api_out" | grep -q "latitude" && ok=1 || ok=0
check "GET /nav returns data" "$ok"

# --- 8. Direct POST /measurements/nav ---
printf '\n--- 8. Direct POST /measurements/nav ---\n'
post_payload='{"points":[{"ts":"2025-01-15T12:00:00Z","vessel_id":"api-test","latitude":48.0,"longitude":-123.0,"heading_true":270.0,"roll_deg":1.5,"pitch_deg":0.8,"heave_m":0.2}]}'
post_resp="$(curl -sk -X POST \
  -H "Authorization: Bearer $TOKEN" \
  -H 'Content-Type: application/json' \
  -d "$post_payload" \
  'https://localhost:8443/ps/measurements/nav' 2>/dev/null)"
printf '  POST response: %s\n' "$post_resp"

verify_out="$(sudo docker exec timescaledb psql -U grafana_writer -d perfsonar -t \
  -c "SELECT vessel_id, latitude, longitude FROM nav_data WHERE vessel_id = 'api-test';" | tr -d ' ')"
[[ -n "$verify_out" ]] && ok=1 || ok=0
check "Direct POST row persisted" "$ok"
printf '  DB verify: %s\n' "$verify_out"

# --- 9. Remote archiving (optional) ---
if [[ -n "$REMOTE_IP" ]]; then
  printf '\n--- 9. Remote Archiving — Shore DB ---\n'
  shore_count="$(sudo docker exec timescaledb psql -U grafana_writer -d perfsonar -t \
    -c "SELECT COUNT(*) FROM nav_data;" 2>/dev/null | tr -d ' ' || echo '0')"
  # Actually query the remote DB via the API
  remote_resp="$(curl -sk -H "Authorization: Bearer $TOKEN" \
    "https://${REMOTE_IP}:8443/ps/nav?limit=1" 2>/dev/null || echo '{}')"
  echo "$remote_resp" | grep -q "latitude" && ok=1 || ok=0
  check "Shore archiver has nav data" "$ok"
  printf '  Remote response: %s\n' "$(echo "$remote_resp" | head -5)"
fi

# --- 10. Data time range ---
printf '\n--- 10. Data Time Range ---\n'
range_out="$(sudo docker exec timescaledb psql -U grafana_writer -d perfsonar -t \
  -c "SELECT MIN(ts), MAX(ts), MAX(ts) - MIN(ts) AS duration FROM nav_data WHERE vessel_id != 'api-test';")"
printf '  %s\n' "$range_out"

# --- Summary ---
printf '\n%s\n' "$SEP"
printf 'Results: %d PASS, %d FAIL\n' "$PASS" "$FAIL"
printf '%s\n' "$SEP"

[[ "$FAIL" -eq 0 ]] && exit 0 || exit 1

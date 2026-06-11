#!/usr/bin/env bash
# run_lead.sh <lead_ms> [count] [period] : one full experiment run at the given
# LEAD_TIME_MS that collects <count> repeated-attack samples in a single run.
#   clean -> start(attack) -> register -> wait until past the LAST attack slot -> result
# Writes the Singapore per-slot vote summary to /tmp/lead_<L>_result.txt
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${HERE}/config.sh"
cd "${REPO_DIR}"

L="${1:?usage: run_lead.sh <lead_ms> [count] [period]}"
COUNT="${2:-${ATTACK_COUNT}}"
PERIOD="${3:-${ATTACK_PERIOD}}"
SLOT0="${ATTACK_SLOT_DEFAULT}"
LAST_SLOT=$(( SLOT0 + (COUNT-1)*PERIOD ))   # height of the final attack
TARGET=$(( LAST_SLOT + 20 ))                # wait a bit past it

# UK node0-of-range http port = 8545 + UK_START*2
UK_HTTP=$(( 8545 + UK_START * 2 ))
uk_height() {
    ssh -i "pem/${UK_PEM}" "${SSH_OPTS[@]}" "${SSH_USER}@${UK_IP}" \
      "curl -s -X POST -H 'Content-Type: application/json' --data '{\"jsonrpc\":\"2.0\",\"method\":\"eth_blockNumber\",\"params\":[],\"id\":1}' http://127.0.0.1:${UK_HTTP} | jq -r .result" 2>/dev/null
}

echo "########## LEAD=${L}ms : clean ##########"
"${HERE}/cluster.sh" clean >"/tmp/lead_${L}_clean.log" 2>&1
echo "########## LEAD=${L}ms : start (count=${COUNT} period=${PERIOD}, attacks ${SLOT0}..${LAST_SLOT}) ##########"
ATTACK_SLOT=$SLOT0 ATTACK_PERIOD=$PERIOD ATTACK_COUNT=$COUNT LEAD_TIME_MS="$L" "${HERE}/cluster.sh" start >"/tmp/lead_${L}_start.log" 2>&1
grep -E "ATTACK armed|all hosts started|reported errors" "/tmp/lead_${L}_start.log" | tail -3
echo "########## LEAD=${L}ms : register ##########"
"${HERE}/cluster.sh" set >"/tmp/lead_${L}_set.log" 2>&1
echo "registered $(grep -c 'send createValidator' "/tmp/lead_${L}_set.log") validators"
echo "########## LEAD=${L}ms : waiting to pass last attack slot ${LAST_SLOT} (target ${TARGET}) ##########"
for i in $(seq 1 4000); do
    h=$(uk_height); h=$((h))
    printf "  UK height=%s (target %s)\r" "$h" "$TARGET"
    [ "${h:-0}" -ge "$TARGET" ] && { echo "  reached $h"; break; }
    sleep 6
done
sleep 5
echo "########## LEAD=${L}ms : RESULT ##########"
"${HERE}/cluster.sh" result | tee "/tmp/lead_${L}_result.txt"
echo "########## LEAD=${L}ms : CHECK (UK) ##########"
"${HERE}/cluster.sh" check

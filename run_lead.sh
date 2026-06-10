#!/usr/bin/env bash
# run_lead.sh <lead_ms> [count] [period] : one full experiment run at the given
# LEAD_TIME_MS that collects <count> repeated-attack samples in a single run.
#   clean -> start(attack) -> register -> wait until past the LAST attack slot -> result
# Writes the Singapore per-slot vote summary to /tmp/lead_<L>_result.txt
set -uo pipefail
L="${1:?usage: run_lead.sh <lead_ms> [count] [period]}"
COUNT="${2:-100}"
PERIOD="${3:-168}"
SLOT0=300
LAST_SLOT=$(( SLOT0 + (COUNT-1)*PERIOD ))   # height of the final attack
TARGET=$(( LAST_SLOT + 20 ))                # wait a bit past it
cd "$(dirname "${BASH_SOURCE[0]}")"

UK_PEM="pem/bsc-new-attack-3.pem"
UK_IP="3.10.211.250"
SSH_OPTS=(-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o ConnectTimeout=15)

uk_height() {
    ssh -i "$UK_PEM" "${SSH_OPTS[@]}" "ubuntu@${UK_IP}" \
      "curl -s -X POST -H 'Content-Type: application/json' --data '{\"jsonrpc\":\"2.0\",\"method\":\"eth_blockNumber\",\"params\":[],\"id\":1}' http://127.0.0.1:8573 | jq -r .result" 2>/dev/null
}

echo "########## LEAD=${L}ms : clean ##########"
./cluster.sh clean >"/tmp/lead_${L}_clean.log" 2>&1
echo "########## LEAD=${L}ms : start (count=${COUNT} period=${PERIOD}, attacks ${SLOT0}..${LAST_SLOT}) ##########"
ATTACK_SLOT=$SLOT0 ATTACK_PERIOD=$PERIOD ATTACK_COUNT=$COUNT LEAD_TIME_MS="$L" ./cluster.sh start >"/tmp/lead_${L}_start.log" 2>&1
grep -E "ATTACK armed|all hosts started|reported errors" "/tmp/lead_${L}_start.log" | tail -3
echo "########## LEAD=${L}ms : register ##########"
./cluster.sh set >"/tmp/lead_${L}_set.log" 2>&1
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
./cluster.sh result | tee "/tmp/lead_${L}_result.txt"
echo "########## LEAD=${L}ms : CHECK (UK) ##########"
./cluster.sh check

#!/bin/bash
# Shared pipeline helpers. Sourced by pipeline.sh and run-one-test.sh.
NS_FALCO=falco
NS_APP=webapp
RECEIVER=deploy/falco-webhook-receiver

plog(){ echo "  | $*"; }   # streamed back to the learner as remote: lines on push

# wait_alert <rule> <pod> <since-rfc3339> <timeout-sec>
# Returns 0 if the receiver saw an alert for <rule> attributed to <pod> since <since>.
wait_alert(){
  local rule="$1" pod="$2" since="$3" to="${4:-30}" end
  end=$(( $(date +%s) + to ))
  while [ "$(date +%s)" -lt "$end" ]; do
    if kubectl -n "$NS_FALCO" logs "$RECEIVER" --since-time="$since" 2>/dev/null \
        | jq -ceR --arg r "$rule" --arg p "$pod" \
          'fromjson? | .json // empty | select(.rule==$r and .output_fields["k8s.pod.name"]==$p)' \
        | grep -q .; then
      return 0
    fi
    sleep 2
  done
  return 1
}

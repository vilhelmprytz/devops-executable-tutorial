#!/bin/bash
# run-one-test.sh <name> <run-cmd> <expect|expect_no_alert> <rule>
# Runs one detection test in a throwaway pod cloned from the app, then asserts
# the expected alert did (or did not) reach the webhook receiver for that pod.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; . "$HERE/lib.sh"
name="$1"; cmd="$2"; mode="$3"; rule="$4"
POD="dac-test-$RANDOM"

# Throwaway pod in the app namespace with the app's label, so namespace-scoped
# rules (e.g. "shell in webapp") attribute the events correctly.
# PID 1 is `sleep` (a real binary), NOT a shell: otherwise the pod's own startup
# would trip the "shell in webapp" rule and poison negative tests.
kubectl -n "$NS_APP" run "$POD" --image=python:3.12-alpine --restart=Never \
  --labels=app=netcheck --command -- sleep 600 >/dev/null
cleanup(){ kubectl -n "$NS_APP" delete pod "$POD" --force --grace-period=0 >/dev/null 2>&1; }
trap cleanup EXIT
kubectl -n "$NS_APP" wait --for=condition=Ready "pod/$POD" --timeout=60s >/dev/null

T=$(date -u +%FT%TZ)
kubectl -n "$NS_APP" exec "$POD" -- sh -c "$cmd" >/dev/null 2>&1 || true

if [ "$mode" = "expect" ]; then
  if wait_alert "$rule" "$POD" "$T" 30; then
    plog "PASS: '$name' -> '$rule' fired"; exit 0
  else
    plog "FAIL: '$name' expected '$rule' but it did not fire"; exit 1
  fi
else
  # Negative test: fire the marker in the SAME pod. Once the marker alert arrives
  # the whole detection path is proven live, so a missing <rule> alert is real,
  # not just slow. (The grace sleep runs AFTER the barrier, never instead of it.)
  kubectl -n "$NS_APP" exec "$POD" -- echo "dac-marker-$POD" >/dev/null 2>&1 || true
  if ! wait_alert "CI pipeline marker" "$POD" "$T" 30; then
    plog "FAIL: marker never arrived — cannot trust the negative result"; exit 1
  fi
  sleep 2
  if wait_alert "$rule" "$POD" "$T" 1; then
    plog "FAIL: '$name' expected NO '$rule' but it fired"; exit 1
  else
    plog "PASS: '$name' -> '$rule' stayed quiet"; exit 0
  fi
fi

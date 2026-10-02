#!/bin/bash
# The "CI pipeline": validate -> record -> deploy -> rollout -> test -> pass|rollback.
# Invoked by the pre-receive hook against a checkout of the pushed revision.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; . "$HERE/lib.sh"
REPO="$(cd "$HERE/.." && pwd)"
RULES="$REPO/rules/custom-rules.yaml"
TESTS="$REPO/tests/tests.yaml"
# Helm 3 uses --atomic; on Helm 4 switch to --rollback-on-failure (see setup log).
HELM_RB="--atomic"

echo "=== Detection-as-Code pipeline ==="

echo "--- [1/4] validate rules (falco -V) ---"
if ! kubectl -n "$NS_FALCO" exec -i ds/falco -c falco -- \
      sh -c 'cat >/tmp/c.yaml && falco -V /etc/falco/falco_rules.yaml -V /tmp/c.yaml' < "$RULES"; then
  echo "VALIDATION FAILED — rules were NOT deployed. Fix the file and push again."
  exit 1
fi

echo "--- [2/4] record current release revision ---"
PREV=$(helm -n "$NS_FALCO" status falco -o json | jq -r '.version')
echo "  | current revision: $PREV"

echo "--- [3/4] deploy (helm upgrade) ---"
if ! helm upgrade falco falcosecurity/falco -n "$NS_FALCO" --version 9.2.0 --reuse-values \
      --set-file "customRules.custom-rules\.yaml=$RULES" --wait --timeout 4m "$HELM_RB"; then
  echo "DEPLOY FAILED — Helm rolled the release back to revision $PREV."
  exit 1
fi
kubectl -n "$NS_FALCO" rollout status ds/falco --timeout=180s

echo "--- [4/4] run detection tests ---"

rollback_and_exit(){
  echo "$1 — rolling back to revision $PREV"
  helm rollback falco "$PREV" -n "$NS_FALCO" --wait
  kubectl -n "$NS_FALCO" rollout status ds/falco --timeout=180s
  exit 1
}

# Parse tests.yaml into tab-separated rows. If the parser itself fails (e.g.
# python3 / PyYAML missing), abort — a failed parser must never masquerade as
# "all tests passed".
PARSED=$(mktemp)
if ! python3 - "$TESTS" >"$PARSED" <<'PY'
import sys, yaml
for t in yaml.safe_load(open(sys.argv[1])) or []:
    mode = "expect" if "expect" in t else "expect_no_alert"
    rule = t.get("expect") or t.get("expect_no_alert")
    print("\t".join([t["name"], t["run"], mode, rule]))
PY
then
  rm -f "$PARSED"
  rollback_and_exit "TEST PARSER FAILED (is python3 + PyYAML available?)"
fi

# Guard: tests.yaml has entries but none parsed -> never silently pass.
if grep -Eq '^[[:space:]]*-[[:space:]]*name:' "$TESTS" && [ ! -s "$PARSED" ]; then
  rm -f "$PARSED"
  rollback_and_exit "NO TESTS PARSED although tests.yaml is non-empty"
fi

fails=0
while IFS=$'\t' read -r name cmd mode rule; do
  [ -z "$name" ] && continue
  echo "  > test: $name"
  bash "$HERE/run-one-test.sh" "$name" "$cmd" "$mode" "$rule" || fails=$((fails+1))
done < "$PARSED"
rm -f "$PARSED"

if [ "$fails" -ne 0 ]; then
  rollback_and_exit "TESTS FAILED ($fails)"
fi

echo "=== ALL GREEN — rules validated, deployed and verified ==="

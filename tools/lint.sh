#!/usr/bin/env bash
# Authoring-side linter. Validates JSON, YAML and shell under the scenario dir.
# There is no local Falco, so Falco rule *semantics* are a Killercoda check only;
# here we only confirm files are well-formed.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCN="$ROOT/detection-as-code-with-falco"
fail=0

echo "== JSON =="
if jq -e . "$SCN/index.json" >/dev/null; then echo "  ok: index.json"; else echo "  BAD JSON: index.json"; fail=1; fi

echo "== shell (bash -n + shellcheck) =="
while IFS= read -r f; do
  if bash -n "$f"; then echo "  ok: ${f#"$SCN"/}"; else echo "  BAD SHELL: $f"; fail=1; fi
  # foreground.sh is a fragment typed into the learner's shell: no shebang by design.
  case "$f" in */foreground.sh) continue;; esac
  if command -v shellcheck >/dev/null; then shellcheck -S error "$f" || { echo "  shellcheck ERROR: $f"; fail=1; }; fi
done < <(find "$SCN" \( -name '*.sh' -o -name 'pre-receive' \))

echo "== YAML =="
while IFS= read -r f; do
  if python3 -c 'import yaml,sys; list(yaml.safe_load_all(open(sys.argv[1])))' "$f"; then
    echo "  ok: ${f#"$SCN"/}"
  else
    echo "  BAD YAML: $f"; fail=1
  fi
done < <(find "$SCN" \( -name '*.yaml' -o -name '*.yml' \))

echo "== index.json references exist =="
if python3 - "$SCN" <<'PY'
import json,os,sys
scn=sys.argv[1]; d=json.load(open(os.path.join(scn,"index.json")))["details"]
refs=[]
for sec in ("intro","finish"):
    refs+=[d[sec][k] for k in ("text","background","foreground") if k in d.get(sec,{})]
for st in d["steps"]:
    refs+=[st[k] for k in ("text","verify","background","foreground") if k in st]
bad=[r for r in refs if not os.path.exists(os.path.join(scn,r))]
if bad:
    print("  MISSING:",bad); sys.exit(1)
print("  all refs present")
PY
then :; else fail=1; fi

echo
if [ "$fail" -eq 0 ]; then echo "LINT OK"; else echo "LINT FAILED"; fi
exit $fail

#!/bin/bash
# Pass once the custom rule is deployed into Falco AND a test references it.
kubectl -n falco get cm falco-rules -o yaml 2>/dev/null | grep -q "Shell spawned by netcheck app" \
  && grep -q "Shell spawned by netcheck app" /root/falco-rules/tests/tests.yaml

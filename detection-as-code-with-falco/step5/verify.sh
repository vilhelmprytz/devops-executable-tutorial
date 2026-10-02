#!/bin/bash
# Pass once the exception is deployed into Falco's rules.
kubectl -n falco get cm falco-rules -o yaml 2>/dev/null | grep -q "allowed_maintenance"

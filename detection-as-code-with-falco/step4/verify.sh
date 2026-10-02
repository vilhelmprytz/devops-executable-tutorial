#!/bin/bash
# Pass when the Step 3 rule is still the deployed state and neither broken rule
# made it into Falco (both rejected pushes were rolled back / never applied).
cm=$(kubectl -n falco get cm falco-rules -o yaml 2>/dev/null)
echo "$cm" | grep -q "Shell spawned by netcheck app" \
  && ! echo "$cm" | grep -q "Never fires" \
  && ! echo "$cm" | grep -q "Broken rule"

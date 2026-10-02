#!/bin/bash
# Pass once the pipeline has deployed at least once (Helm revision >= 2).
rev=$(helm -n falco status falco -o json 2>/dev/null | jq -r '.version')
[ -n "$rev" ] && [ "$rev" -ge 2 ] 2>/dev/null

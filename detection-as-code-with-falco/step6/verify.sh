#!/bin/bash
# Pass only when the patched app is up AND rejects the injection:
#  - it must return "invalid host" (proves the fix is live and serving), and
#  - the injected `cat /etc/shadow` must NOT execute (no 'root:' in the output).
out=$(curl -s "http://localhost:30080/ping?host=127.0.0.1;cat%20/etc/shadow" 2>/dev/null)
echo "$out" | grep -q "invalid host" && ! echo "$out" | grep -q "root:"

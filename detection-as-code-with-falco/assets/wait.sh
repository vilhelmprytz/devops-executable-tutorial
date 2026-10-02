#!/bin/bash
# Foreground spinner: shown in the learner's terminal until setup finishes.
# No set -e / no exit here — this runs in the user's interactive shell.
# Not self-deleting: if the page reloads mid-setup, foreground.sh can re-run it.
clear
echo "Setting up the Detection-as-Code lab (Falco + Falcosidekick + sample app)."
echo "This can take a few minutes while container images pull. Live progress:"
echo
last=""
spin='|/-\'
i=0
while [ ! -f /tmp/dac-finished ]; do
  cur=$(tail -n 1 /root/.dac/setup.log 2>/dev/null)
  if [ -n "$cur" ] && [ "$cur" != "$last" ]; then
    printf '\r\033[K  %s\n' "$cur"
    last="$cur"
  fi
  printf '\r %s installing...' "${spin:i++%4:1}"
  sleep 0.5
done
printf '\r\033[K'
echo "Setup complete. The lab is ready — start with Step 1."

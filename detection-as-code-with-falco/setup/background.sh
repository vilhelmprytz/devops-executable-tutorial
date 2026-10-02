#!/bin/bash
# Runs on controlplane as root while the intro page shows.
# Assets may not be on disk yet when this starts, so poll for the installer,
# then run it with all output captured to a log the spinner tails.
FILE=/root/.dac/setup.sh
while [ ! -f "$FILE" ]; do sleep 0.5; done
chmod +x "$FILE" 2>/dev/null
bash "$FILE" >/root/.dac/setup.log 2>&1

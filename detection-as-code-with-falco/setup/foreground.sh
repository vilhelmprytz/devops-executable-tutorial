if [ -f /tmp/dac-finished ]; then echo "Lab ready — start with Step 1."; else FILE=/root/.dac/wait.sh; while [ ! -f "$FILE" ]; do sleep 0.3; done; bash "$FILE"; fi

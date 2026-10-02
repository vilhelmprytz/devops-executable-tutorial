# Close the loop: fix the application

Detection is not the goal — it is the signal. The last move in the DevOps feedback
loop is to take what the alert told you and fix the software, so the attack cannot
happen again. Alerts from runtime flow back into development: that is the
monitoring-to-code loop.

## 1. Read what the alert told you

Look again at an alert from your custom rule:

````plain
kubectl -n falco logs deploy/falco-webhook-receiver --tail=20 | grep "Shell spawned"
```{{exec}}

The `output_fields` point at the `netcheck` pod in `webapp`, and the command line
shows a shell running whatever was passed to the app. The app builds a shell
command out of user input — that is the bug.

## 2. Fix the code

The app source is a real file at `/root/app/app.py`. Open it and fix the `/ping`
handler so user input can never become a command.

```plain
vi /root/app/app.py
```{{exec}}

Hints:
- The problem is `subprocess.run(f"ping -c1 {host}", shell=True)`.
- Pass an **argv list** and drop `shell=True`, so `host` is an argument, never code.
- Validate `host` too (allow only letters, digits, `.` and `-`).

<details><summary>Solution — the patched handler</summary>

Add near the top:

```python
import re
HOST_RE = re.compile(r"^[A-Za-z0-9.-]+$")
````

Replace the `/ping` branch with:

```python
if u.path == "/ping":
    host = q.get("host", ["127.0.0.1"])[0]
    if not HOST_RE.match(host):
        return self._send(400, "invalid host\n")
    out = subprocess.run(
        ["ping", "-c1", host],
        capture_output=True, text=True, timeout=10,
    )
    return self._send(200, out.stdout + out.stderr)
```

A full reference copy is at `/root/.dac/lib/app-fixed.py`.

</details>

## 3. Redeploy the app

Push your edited source into the ConfigMap and restart the app:

````plain
kubectl -n webapp create configmap netcheck-src \
  --from-file=app.py=/root/app/app.py --dry-run=client -o yaml | kubectl apply -f -
kubectl -n webapp rollout restart deploy/netcheck
kubectl -n webapp rollout status deploy/netcheck
```{{exec}}

## 4. Attack again — and watch it fail

Re-run the exact attack from Step 1:

```plain
curl -s "http://localhost:30080/ping?host=127.0.0.1;cat%20/etc/shadow"
```{{exec}}

The injection no longer runs: you get `invalid host` instead of the contents of
`/etc/shadow`. And because no shell was spawned and no sensitive file was read,
**no new alert is raised** — confirm the receiver shows nothing new for this
attack:

```plain
kubectl -n falco logs deploy/falco-webhook-receiver --since=20s | grep -E "Shell spawned|Read sensitive" || echo "no alert — the attack is dead"
```{{exec}}

You have closed the loop: an alert found a real bug, you fixed the code, and the
attack that used to fire is now both harmless and silent.

Click **Check** once the patched app rejects the injection.
````

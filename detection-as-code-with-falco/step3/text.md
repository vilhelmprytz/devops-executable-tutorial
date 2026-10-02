# Write a custom rule — and a test for it

Falco's default rules caught the sensitive-file read. But they do **not** catch
something more specific to *your* app: the `netcheck` service should never start a
shell at all. When it does, that is command injection. No stable default rule
says "this particular app spawned a shell" — so your team writes that rule.

This step is hands-on. You will add a rule, add a test that proves it fires, and
push both through the pipeline.

## 1. Write the rule

Edit `rules/custom-rules.yaml` and add a rule that fires when a shell starts
inside the `webapp` namespace.

```plain
cd /root/falco-rules && vi rules/custom-rules.yaml
```{{exec}}

Hints:
- A rule needs `rule`, `desc`, `condition`, `output` and `priority`.
- Useful building blocks: `spawned_process`, `container`, the macro `shell_procs`
  (a shell was started), and the field `k8s.ns.name` (the namespace).
- Put the pod and namespace in the `output` so the alert tells you *where*.

<details><summary>Solution — the rule</summary>

```yaml
- rule: Shell spawned by netcheck app
  desc: The netcheck web app should never start a shell; a shell here means command injection.
  condition: spawned_process and container and k8s.ns.name = "webapp" and shell_procs
  output: "Shell spawned in netcheck (cmd=%proc.cmdline parent=%proc.pname pod=%k8s.pod.name ns=%k8s.ns.name)"
  priority: WARNING
  tags: [dac, webapp]
```

> We scope by namespace rather than by parent process (`proc.pname = python3`)
> so the rule is easy to test and still catches any shell in the app, however it
> was spawned. Scoping to the parent process is a reasonable tightening later.

</details>

## 2. Write the test

Add a test to `tests/tests.yaml` that runs a shell and expects your rule to fire.

```plain
vi tests/tests.yaml
```{{exec}}

<details><summary>Solution — the test</summary>

```yaml
- name: app shell is detected
  run: echo attacker-was-here
  expect: Shell spawned by netcheck app
```

The pipeline runs each `run` command inside a throwaway pod in the `webapp`
namespace — and running a command there starts a shell, which is exactly the
behaviour your rule flags. So the test produces the real thing the rule detects.

</details>

## 3. Ship it

```plain
git commit -am "detect shells spawned by the netcheck app"
git push origin main
```{{exec}}

The pipeline validates the rule, deploys it, then runs **both** tests — the
original `/etc/shadow` one and your new shell one — and reports `ALL GREEN`.

Prove it end to end by attacking the real app again and watching your own rule
fire in the UI and the receiver:

```plain
curl -s "http://localhost:30080/ping?host=127.0.0.1;id" >/dev/null
kubectl -n falco logs deploy/falco-webhook-receiver --tail=10 | grep "Shell spawned"
```{{exec}}

Click **Check** once your rule is deployed and its test is in `tests.yaml`.

# Tune a false positive

Your rule flags *every* shell in the `webapp` namespace. But suppose the team has
one legitimate reason to run a shell there — a maintenance task that prints a
health summary. Right now that trips the rule, and alerts you do not care about
drown the ones you do. This is **alert fatigue**, and the fix is not to delete the
rule — it is to add a precise **exception** for the known-good case, through the
same pipeline.

First, see the false positive. Run the benign maintenance command in the app pod:

```plain
POD=$(kubectl -n webapp get pod -l app=netcheck -o jsonpath='{.items[0].metadata.name}')
kubectl -n webapp exec "$POD" -- sh -c "echo falco-lab-maintenance: all healthy"
kubectl -n falco logs deploy/falco-webhook-receiver --tail=5 | grep "Shell spawned"
```{{exec}}

It fired — a false positive. Now carve it out.

## 1. Add an exception (don't rewrite the rule)

Edit `rules/custom-rules.yaml` and **append** an exception to your existing rule,
rather than changing its condition.

```plain
cd /root/falco-rules && vi rules/custom-rules.yaml
```{{exec}}

Hints:
- Use `override: { exceptions: append }` so you extend the rule in place.
- Match the known-good command by a distinctive token in its command line.

<details><summary>Solution — the exception</summary>

Append this as a separate YAML item (it refers to the rule by name):

```yaml
- rule: Shell spawned by netcheck app
  exceptions:
    - name: allowed_maintenance
      fields: [proc.cmdline]
      comps: [contains]
      values:
        - ["falco-lab-maintenance"]
  override: { exceptions: append }
```

Matching a token with `contains` is deliberately simple. Note the trade-off:
anything whose command line contains that token is now exempt, so an exception
always widens a blind spot. Keep them specific.

</details>

## 2. Add tests for both sides

A good exception is proven two ways: the benign case is now quiet, **and** the
attack is still caught. Add both to `tests/tests.yaml`.

```plain
vi tests/tests.yaml
```{{exec}}

<details><summary>Solution — the tests</summary>

```yaml
- name: maintenance shell stays quiet
  run: echo falco-lab-maintenance all healthy
  expect_no_alert: Shell spawned by netcheck app

- name: attack shell is still detected
  run: echo attacker-was-here
  expect: Shell spawned by netcheck app
```

</details>

## 3. Ship it

```plain
git commit -am "allow the maintenance shell, keep detecting attacks"
git push origin main
```{{exec}}

The pipeline deploys the exception and runs both tests: the maintenance case now
stays quiet (verified against the marker barrier, so a quiet result is trustworthy
and not just slow), and the attack case still fires. `ALL GREEN`.

Click **Check** once the exception is deployed.

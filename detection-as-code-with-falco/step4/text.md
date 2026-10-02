# Break it on purpose

A pipeline is only worth having if it stops bad changes. There are two ways a
detection rule goes wrong, and the pipeline catches both — before anyone relies
on the rule in production.

## 1. A broken rule — caught by validation

Add a rule with a mistake: a misspelled macro. Falco cannot compile it.

```plain
cd /root/falco-rules
cat >> rules/custom-rules.yaml <<'EOF'

- rule: Broken rule
  desc: references a macro that does not exist
  condition: spawned_proces and container
  output: "should never deploy (%proc.name)"
  priority: WARNING
EOF
git commit -am "add a broken rule"
git push origin main
```{{exec}}

The **validate** stage fails: `falco -V` reports the undefined macro, the push is
**rejected**, and nothing is deployed. Your running rules are untouched.

Revert the bad commit:

```plain
git reset --hard HEAD~1
```{{exec}}

## 2. A rule that never fires — caught by the test

A rule can be perfectly valid and still be useless if it never matches. This is
the subtle failure: it looks fine, deploys fine, and silently protects nothing.
The *test* is what catches it.

Add a rule whose condition can never match real activity, plus a test that
expects it to fire:

```plain
cat >> rules/custom-rules.yaml <<'EOF'

- rule: Never fires
  desc: condition can never be true in this lab
  condition: spawned_process and container and proc.name = "a-binary-that-never-runs"
  output: "unreachable (%proc.cmdline pod=%k8s.pod.name)"
  priority: WARNING
  tags: [dac]
EOF
cat >> tests/tests.yaml <<'EOF'

- name: never-fires rule should fire
  run: sh -c "echo anything"
  expect: Never fires
EOF
git commit -am "add a rule that never fires"
git push origin main
```{{exec}}

This time **validate** passes and the rule **deploys** — but the **test** fails
(the expected alert never arrives), so the pipeline **rolls Falco back** to the
previous revision and rejects the push. A silently-broken rule never makes it to
a state anyone trusts.

Revert:

```plain
git reset --hard HEAD~1
```{{exec}}

Confirm the good rule from Step 3 is still the deployed state, and the broken
ones are gone:

```plain
helm -n falco history falco | tail -5
kubectl -n falco get cm falco-rules -o yaml | grep -E "Shell spawned by netcheck app|Never fires|Broken rule"
```{{exec}}

Click **Check**: the Step 3 rule is still live and neither broken rule is deployed.

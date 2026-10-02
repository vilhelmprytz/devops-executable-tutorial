# Falco detection rules — managed as code

This repository holds your Falco **detection rules** and their **tests**, and
ships them through a pipeline, exactly like application code.

```
rules/custom-rules.yaml   # the detection rules you deploy
tests/tests.yaml          # the tests that prove each rule works
pipeline/                 # the pipeline that runs on every push
hooks/pre-receive         # git hook that triggers the pipeline (the "CI")
```

## How a change ships

Edit a rule or a test, then:

```bash
git commit -am "my change"
git push origin main
```

The push triggers `pipeline/pipeline.sh`, which runs four stages and streams its
output back to your terminal (the `remote:` lines):

1. **Validate** — `falco -V` loads the default ruleset plus your file. A YAML
   error, an undefined macro or a misspelled field stops the push here, before
   anything is deployed.
2. **Record** the current Falco release revision (so it can roll back).
3. **Deploy** — `helm upgrade` mounts your rules into Falco and waits for the
   DaemonSet to roll out on both nodes.
4. **Test** — each test in `tests.yaml` runs its command inside a throwaway pod
   and checks the webhook receiver for the expected alert.

If any stage fails, the pipeline **rolls Falco back** to the previous revision
and **rejects the push**. Your working copy still has the change, so you can fix
it and push again.

## Test format

```yaml
- name: reading /etc/shadow is detected
  run: cat /etc/shadow
  expect: Read sensitive file untrusted      # this rule MUST fire

- name: maintenance shell stays quiet
  run: echo falco-lab-maintenance all healthy
  expect_no_alert: Shell spawned by netcheck app   # must NOT fire (an exception covers it)
```

A negative test (`expect_no_alert`) is checked with a **marker**: the pipeline
emits a synthetic marker event in the same pod and waits for it to arrive. Only
once the marker proves the detection path is live does a missing alert count as
"stayed quiet" — so negatives can't pass just because Falco was slow.

## Writing a rule

A new rule needs `rule`, `desc`, `condition`, `output` and `priority`:

```yaml
- rule: Shell spawned by netcheck app
  desc: The netcheck web app should never start a shell.
  condition: spawned_process and container and k8s.ns.name = "webapp" and shell_procs
  output: "Shell in netcheck (cmd=%proc.cmdline pod=%k8s.pod.name ns=%k8s.ns.name)"
  priority: WARNING
  tags: [dac, webapp]
```

## Tuning a rule (exceptions and overrides)

Append an exception to an existing rule instead of rewriting it:

```yaml
- rule: Shell spawned by netcheck app
  exceptions:
    - name: allowed_maintenance
      fields: [proc.cmdline]
      comps: [startswith]
      values: [["sh -c echo healthcheck"]]
  override: { exceptions: append }
```

Other overrides: `override: { items: append }` (add to a list),
`override: { condition: replace }` (swap a macro's condition),
`enabled: false` + `override: { enabled: replace }` (disable a rule).

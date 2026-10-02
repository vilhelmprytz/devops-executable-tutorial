# The rules repo and the pipeline

Falco shipped with a set of default rules. But the rules *your team* cares about —
the ones specific to your application — should be treated like any other code:
versioned, reviewed, tested and deployed by a pipeline. That is what the repo at
`/root/falco-rules` is for.

## Tour the repo

```plain
cd /root/falco-rules && ls -R rules tests pipeline
```{{exec}}

```plain
cat README.md
```{{exec}}

- `rules/custom-rules.yaml` — your detection rules.
- `tests/tests.yaml` — a test per rule, proving it fires (or stays quiet).
- `pipeline/` — the pipeline that runs on every push.
- `hooks/pre-receive` — the git hook that triggers it. This stands in for a
  hosted CI service (GitHub Actions, GitLab CI): here, `git push` *is* the
  trigger, and the pipeline runs locally.

Skim the pipeline stages:

```plain
sed -n '1,40p' pipeline/pipeline.sh
```{{exec}}

It does four things on every push: **validate** the rules (`falco -V`),
**record** the current release, **deploy** with `helm upgrade`, then **test**.
If anything fails it **rolls back** and rejects the push.

## Push a trivial change

Make a harmless edit — improve the marker rule's description — and push it, to
watch the whole pipeline run:

```plain
sed -i 's/Synthetic barrier event/Synthetic barrier event (edited)/' rules/custom-rules.yaml
git commit -am "clarify marker rule description"
git push origin main
```{{exec}}

Watch the `remote:` lines: validation passes, Falco is upgraded, the rollout
completes, the seed test (`reading /etc/shadow is detected`) passes, and you get
`ALL GREEN`. Your rule change is now live in Falco — deployed by the pipeline,
not by hand.

```plain
helm -n falco history falco | tail -3
```{{exec}}

Click **Check** once the push succeeded (the Falco release is now at revision 2
or higher).

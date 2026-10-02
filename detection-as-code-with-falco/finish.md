# Well done

You took runtime detection through a full DevOps loop:

- Attacked a running app and saw Falco's default rules flag it, with the pod and
  namespace, in the UI and a webhook.
- Managed detection rules as code in Git, shipped by a pipeline that **validates
  → deploys → tests → rolls back**.
- Wrote a custom rule and a test, and watched the pipeline stop a broken rule and
  a rule that no longer fired.
- Tuned a false positive with an exception, proving both that the benign case went
  quiet and that the attack was still caught.
- Closed the loop: used an alert to find the bug, fixed the app, and confirmed the
  attack now fails and is silent.

## Design decisions worth noting

- **Modern eBPF driver.** No kernel module to compile or match to the host; the
  probe loads into the kernel at runtime. It needs access to the host kernel,
  which is why Falco runs as a **privileged DaemonSet**, one pod per node, so it
  sees every container's syscalls.
- **Test rules before *and* after deploy.** `falco -V` catches rules that will not
  load; the post-deploy tests catch rules that load fine but never match. Both
  failures are real, and they need different checks.
- **A local git hook stands in for hosted CI.** The `pre-receive` hook does what a
  GitHub Actions / GitLab CI job would: the same validate-deploy-test-rollback
  stages would run as pipeline steps against a real cluster.
- **The app team owns its rules.** The rules live beside the app and go through the
  app's own pipeline, instead of security being a separate team's job.

## Limitations (runtime security is not magic)

- Falco only sees events **once it is running** — it cannot detect what happened
  before it started.
- Tests only cover the attacks **someone thought of**; a novel technique can still
  pass unnoticed.
- Rules need **tuning**. Too broad and you get alert fatigue; too narrow and you
  miss things. Exceptions help, but every exception widens a blind spot.
- Falco needs access to the **host kernel**, so it cannot run on platforms that
  hide it (for example AWS Fargate).
- Falco **detects**, it does not **prevent**. It tells you an attack is happening;
  stopping it is a separate response.

## Take it further

- Scope the custom rule more tightly (e.g. by parent process or image).
- Add more app-specific rules and tests, and route Falcosidekick to Slack or
  another real output.
- Explore Falco's incubating and sandbox rulesets for broader coverage.

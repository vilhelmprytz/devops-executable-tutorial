# Baseline: detecting an attack at runtime

Build-time checks — image scanning, admission policies — catch *known* problems
before a workload starts. They cannot see what a container actually *does* once
it is running. **Runtime security** closes that gap. In this lab, [Falco](https://falco.org)
watches every system call on both nodes and raises an alert when a container
behaves suspiciously.

> This is an authorised, self-contained lab. The `netcheck` app in the `webapp`
> namespace is **deliberately vulnerable** so you can see detection work. Nothing
> here leaves the cluster, and you fix the vulnerability yourself in the last step.

## Look at what is running

The setup installed Falco (a privileged DaemonSet, one pod per node),
Falcosidekick (which routes alerts), its web UI, and a webhook receiver.

```plain
kubectl get nodes
```{{exec}}

```plain
kubectl -n falco get daemonset,deploy
```{{exec}}

```plain
kubectl -n webapp get pods -o wide
```{{exec}}

## Open the alert UI

Expose the Falcosidekick UI and open it (log in with `admin` / `admin`):

```plain
kubectl -n falco patch svc falco-falcosidekick-ui -p '{"spec":{"type":"NodePort","ports":[{"port":2802,"targetPort":2802,"nodePort":30282}]}}'
```{{exec}}

[Open the Falcosidekick UI]({{TRAFFIC_HOST1_30282}})

Leave this tab open — alerts will appear here as you trigger them.

## Trigger the vulnerable endpoint

The app exposes `GET /ping?host=<x>` and runs `ping` on whatever you pass. Because
it builds a shell command from your input, you can make it run other commands too.
Read a sensitive file through it:

```plain
curl -s "http://localhost:30080/ping?host=127.0.0.1;cat%20/etc/shadow"
```{{exec}}

Within a second or two, Falco flags it. See the alert in the UI, and in the
webhook receiver's log:

```plain
kubectl -n falco logs deploy/falco-webhook-receiver --tail=5
```{{exec}}

You should see a `Read sensitive file untrusted` rule, with `output_fields`
naming the pod and namespace that did it.

## How the event travelled

```plain
  cat /etc/shadow            (a syscall: open on /etc/shadow)
        │
        ▼
  modern eBPF driver         Falco's in-kernel probe sees the syscall
        │
        ▼
  Falco rule engine          matches the "Read sensitive file untrusted" rule
        │
        ▼
  Falcosidekick              fans the alert out to its outputs
        │
        ├────────────▶ Web UI (what you just saw)
        └────────────▶ Webhook receiver (what the pipeline will read)
```

Everything after the syscall is just data moving through components you can
inspect — which is exactly what lets us treat detection as code.

Click **Check** to continue once you have seen an alert.

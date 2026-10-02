#!/usr/bin/env python3
"""Assert the Falco Helm values keep every lab-critical setting. Exits 1 on drift."""
import sys, yaml, os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
path = os.path.join(ROOT, "detection-as-code-with-falco/assets/lib/falco-values.yaml")
v = yaml.safe_load(open(path))


def req(cond, msg):
    if not cond:
        print("FAIL:", msg)
        sys.exit(1)


req(v["driver"]["kind"] == "modern_ebpf", "driver.kind must be modern_ebpf")
req(v["falcoctl"]["artifact"]["install"]["enabled"] is False, "falcoctl install must be false")
req(v["falcoctl"]["artifact"]["follow"]["enabled"] is False, "falcoctl follow must be false")
req(v["falco"]["rule_matching"] == "all", "rule_matching must be all")

ao = v["falco"]["append_output"]
req(any(e.get("suggested_output") for e in ao), "append_output must keep suggested_output")
req(
    any(
        e.get("match", {}).get("source") == "syscall"
        and {"k8s.ns.name", "k8s.pod.name"}.issubset(set(e.get("extra_fields", [])))
        for e in ao
    ),
    "append_output must add k8s.ns.name and k8s.pod.name for syscall",
)

fsk = v["falcosidekick"]
req(fsk["enabled"] is True and fsk["replicaCount"] == 1, "falcosidekick enabled with 1 replica")
req(
    fsk["config"]["webhook"]["address"].startswith("http://falco-webhook-receiver.falco"),
    "webhook address must point at the receiver service",
)
req(fsk["webui"]["enabled"] is True and fsk["webui"]["replicaCount"] == 1, "webui enabled with 1 replica")
req(fsk["webui"]["redis"]["storageEnabled"] is False, "webui redis storage must be disabled")

print("falco-values OK")

#!/bin/bash
# Orchestrator for the Detection-as-Code lab. Runs once in the background on
# controlplane. Phases log with timestamps so the spinner can surface progress.
# Re-running continues toward a ready lab (install steps are idempotent).
set -uo pipefail
log(){ echo "[$(date -u +%H:%M:%S)] $*"; }
# die() aborts WITHOUT writing the finished marker, so the spinner never reports
# "ready" for a broken lab. The banner is the last line the spinner shows.
die(){ echo "[SETUP FAILED] $*"; echo "See /root/.dac/setup.log for details."; exit 1; }
export KUBECONFIG=/root/.kube/config

log "=== environment probe ==="
uname -r || true
nproc 2>/dev/null || true
free -m 2>/dev/null | head -2 || true
for t in helm jq python3 git curl yq; do printf '%-8s ' "$t"; command -v "$t" || echo MISSING; done
kubectl get storageclass 2>/dev/null || log "no storageclass listed"

log "=== verify assets were staged ==="
# The scenario ships its files via the index.json `assets` glob to /root/.dac.
# If the subtree is missing (e.g. the glob did not preserve structure), fail
# loudly here instead of at a confusing `kubectl apply` further down.
for d in /root/.dac/lib /root/.dac/repo-seed; do
  for _ in $(seq 1 20); do [ -d "$d" ] && break; sleep 1; done
  [ -d "$d" ] || die "expected asset dir $d is missing (check the index.json assets glob)"
done
for f in /root/.dac/lib/receiver.yaml /root/.dac/lib/falco-values.yaml \
         /root/.dac/lib/app.py /root/.dac/lib/app.yaml \
         /root/.dac/repo-seed/pipeline/pipeline.sh; do
  [ -f "$f" ] || die "expected asset file $f is missing"
done

log "=== ensure jq + python3 + PyYAML (the pipeline needs them) ==="
need_apt=0
command -v jq >/dev/null || need_apt=1
command -v python3 >/dev/null || need_apt=1
python3 -c 'import yaml' 2>/dev/null || need_apt=1
if [ "$need_apt" -eq 1 ]; then
  apt-get update -y >/dev/null 2>&1 || true
  apt-get install -y jq python3 python3-yaml >/dev/null 2>&1 || log "WARN: apt install failed"
fi
command -v jq >/dev/null || die "jq is required but not available"
python3 -c 'import yaml' 2>/dev/null || die "python3 + PyYAML are required but not available"

log "=== wait for cluster: kubeconfig + 2 Ready nodes ==="
while [ ! -f /root/.kube/config ]; do sleep 2; done
until [ "$(kubectl get nodes --no-headers 2>/dev/null | grep -cw Ready)" -eq 2 ]; do
  log "waiting for 2 Ready nodes..."; sleep 3
done
log "cluster ready: $(kubectl get nodes --no-headers | awk '{print $1}' | paste -sd, -)"

log "=== helm repos ==="
helm repo add falcosecurity https://falcosecurity.github.io/charts >/dev/null 2>&1 || true
helm repo update >/dev/null

log "=== namespace + webhook receiver (must exist before Falco starts) ==="
kubectl create namespace falco --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -f /root/.dac/lib/receiver.yaml || die "receiver apply failed"
kubectl -n falco rollout status deploy/falco-webhook-receiver --timeout=120s || die "receiver did not become ready"

log "=== install Falco 0.45.0 (chart 9.2.0) + Falcosidekick + UI ==="
helm upgrade --install falco falcosecurity/falco \
  --namespace falco --version 9.2.0 \
  -f /root/.dac/lib/falco-values.yaml \
  --wait --timeout 6m || die "helm install of Falco failed"
kubectl -n falco rollout status ds/falco --timeout=300s || die "Falco DaemonSet did not roll out"
log "falco pods: $(kubectl -n falco get pods --no-headers | wc -l)"

log "=== deploy the sample app (webapp/netcheck) ==="
# Keep the app source as a real editable file; the learner patches it in Step 6.
mkdir -p /root/app
cp /root/.dac/lib/app.py /root/app/app.py
kubectl create namespace webapp --dry-run=client -o yaml | kubectl apply -f -
kubectl -n webapp create configmap netcheck-src \
  --from-file=app.py=/root/app/app.py --dry-run=client -o yaml | kubectl apply -f - || die "app configmap failed"
kubectl apply -f /root/.dac/lib/app.yaml || die "app manifest apply failed"
kubectl -n webapp rollout status deploy/netcheck --timeout=120s || die "app did not become ready"
log "app up on NodePort 30080 (source at /root/app/app.py)"
log "=== seed /root/falco-rules git repo + pipeline hook ==="
WORK=/root/falco-rules
BARE=/root/falco-rules.git
rm -rf "$WORK" "$BARE"
mkdir -p "$WORK"
cp -r /root/.dac/repo-seed/. "$WORK"/ || die "could not copy repo-seed"
chmod +x "$WORK"/pipeline/*.sh "$WORK"/hooks/pre-receive
git config --global user.email lab@example.com
git config --global user.name "DaC Lab"
git config --global init.defaultBranch main
git init -q --bare "$BARE"
cp "$WORK/hooks/pre-receive" "$BARE/hooks/pre-receive"
chmod +x "$BARE/hooks/pre-receive"
(
  cd "$WORK" || exit 1
  git init -q
  git add -A
  git commit -qm "seed detection rules and tests"
  git branch -M main
  git remote add origin "$BARE"
  # Intentionally NOT pushed here: the learner's first push in Step 2 is the
  # first pipeline run, so they watch validate/deploy/test happen themselves.
) || die "git repo seeding failed"
log "repo ready at $WORK (edit rules/tests, then: git commit -am ... && git push)"

log "=== setup complete ==="
touch /tmp/dac-finished

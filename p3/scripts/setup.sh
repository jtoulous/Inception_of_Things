#!/bin/bash
set -euo pipefail

CLUSTER="mycluster"
HERE="$(cd "$(dirname "$0")" && pwd)"
CONFS="$HERE/../confs"
SELF="$HERE/$(basename "$0")"

if ! docker info >/dev/null 2>&1; then
    command -v docker >/dev/null || { echo "ERROR: docker is not installed - run ./install.sh first" >&2; exit 1; }
    getent group docker >/dev/null || { echo "ERROR: no docker group - run ./install.sh first" >&2; exit 1; }
    [ -z "${P3_SG:-}" ] || { echo "ERROR: still no access to the Docker socket - is dockerd running?" >&2; exit 1; }
    export P3_SG=1
    exec sg docker -c "$SELF"
fi

echo ">>> Creating the k3d cluster..."
k3d cluster get "$CLUSTER" >/dev/null 2>&1 || k3d cluster create "$CLUSTER"

echo ">>> Creating the namespaces..."
for ns in argocd dev; do
    kubectl create namespace "$ns" --dry-run=client -o yaml | kubectl apply -f -
done

echo ">>> Installing Argo CD..."
kubectl apply --server-side -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
kubectl wait --for=condition=available --timeout=600s deployment/argocd-server -n argocd

echo ">>> Declaring the application..."
kubectl apply -f "$CONFS/application.yaml"

echo ">>> Waiting for Argo CD to deploy the application..."
for _ in $(seq 1 60); do
    kubectl wait --for=condition=available --timeout=5s deployment/wil-playground -n dev 2>/dev/null && break
    sleep 5
done

echo ">>> Opening the port-forwards..."
pkill -f "[k]ubectl port-forward svc/wil-playground" 2>/dev/null || true
pkill -f "[k]ubectl port-forward svc/argocd-server"  2>/dev/null || true

nohup bash -c 'while true; do
    kubectl port-forward svc/wil-playground -n dev 8888:8888
    sleep 2
done' >/tmp/pf-app.log 2>&1 &
nohup kubectl port-forward svc/argocd-server -n argocd 8080:443 >/tmp/pf-argocd.log 2>&1 &
disown -a

echo
echo "=== ARGO CD ==="
echo "  in the VM:   https://localhost:8080   (self-signed cert, accept the warning)"
echo "  on the host: https://localhost:8443   (SSH tunnel opened by the Makefile)"
echo "  login:    admin"
echo -n "  password: "
kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath="{.data.password}" | base64 -d
echo
echo
echo "=== APPLICATION ==="
echo "  in the VM:   curl http://localhost:8888/"
echo "  on the host: curl http://localhost:8888/"

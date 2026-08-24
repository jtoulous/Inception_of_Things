#!/bin/bash
set -euo pipefail

CLUSTER="mycluster"

# The [k] keeps pkill from matching this very command line
pkill -f "[k]ubectl port-forward svc/wil-playground" 2>/dev/null || true
pkill -f "[k]ubectl port-forward svc/argocd-server"  2>/dev/null || true

# Deleting the cluster takes the namespaces, Argo CD and the app with it
k3d cluster delete "$CLUSTER"

#!/bin/bash
set -euo pipefail

CLUSTER="mycluster"

pkill -f "[k]ubectl port-forward svc/wil-playground" 2>/dev/null || true
pkill -f "[k]ubectl port-forward svc/argocd-server"  2>/dev/null || true

k3d cluster delete "$CLUSTER"

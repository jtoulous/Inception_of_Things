#!/bin/bash

# Supprimer l'app Argo CD
kubectl delete -f ../confs/application.yaml

# Supprimer Argo CD
kubectl delete -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Supprimer les namespaces
kubectl delete namespace argocd
kubectl delete namespace dev

# Supprimer le cluster
k3d cluster delete mycluster
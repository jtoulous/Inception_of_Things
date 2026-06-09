k3d cluster create mycluster
kubectl create namespace argocd
kubectl create namespace dev

kubectl apply --server-side -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
kubectl wait --for=condition=available --timeout=420s deployment/argocd-server -n argocd

kubectl apply -f ../confs/application.yaml

until sudo kubectl get deployment wil-playground -n dev 2>/dev/null | grep -q "wil-playground"; do
    echo "Waiting for deployment..."
    sleep 5
done
kubectl wait --for=condition=available --timeout=420s deployment/wil-playground -n dev

kubectl port-forward svc/wil-playground 8888:8888 -n dev &
kubectl port-forward svc/argocd-server 8080:443 -n argocd &

echo ""
echo "=== ARGO CD LOGIN ==="
echo "login: admin"
echo -n "password: "
kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath="{.data.password}" | base64 -d
echo ""
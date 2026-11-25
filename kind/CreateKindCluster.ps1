$startTime = Get-Date

# Install the cluster and wait for it to be ready
kind create cluster --name k8s-fawry --config KindCluster.yaml #--wait 90s

# Install network plugin that supports NetworkPolicy (https://docs.tigera.io/calico/latest/getting-started/kubernetes/kind)
kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.27.0/manifests/tigera-operator.yaml
kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.27.0/manifests/custom-resources.yaml

# Install Nginx Ingress Controller
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml

# Pin Ingress controller to the control-plane node that holds ports 80/443
kubectl patch deployment ingress-nginx-controller -n ingress-nginx --type='merge' -p '{"spec":{"template":{"spec":{"nodeSelector":{"ingress-ready":"true"}}}}}'

# Wait for the Nginx Ingress Controller to be ready
# kubectl rollout watching deployment controller itself 
#so it insure that is on the control-plane node and ready to serve traffic
# and old one is replaced by the new one
Write-Output "Waiting for Nginx Ingress controller to be ready..."
kubectl rollout status deployment/ingress-nginx-controller -n ingress-nginx --timeout=300s

$endTime = Get-Date
$duration = $endTime - $startTime

Write-Output "Cluster is ready! ($($duration.TotalSeconds) seconds)"

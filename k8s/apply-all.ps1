Write-Host "1. Creating Namespace..." -ForegroundColor Cyan
kubectl apply -f Namespace.yaml

Write-Host "2. Checking Docker Registry Secret (regcred)..." -ForegroundColor Cyan
$secretExists = kubectl get secret regcred -n fawry-task --ignore-not-found

if (-not $secretExists) {
    Write-Host "regcred not found. Creating securely..." -ForegroundColor Yellow

    $dockerUser = $env:DOCKERHUB_USER
    if (-not $dockerUser) { $dockerUser = Read-Host "Docker Hub username" }

    $plainPat = $env:DOCKERHUB_TOKEN
    if (-not $plainPat) {
        $secure = Read-Host "Docker Hub access token (read-only)" -AsSecureString
        $BSTR = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
        try { $plainPat = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($BSTR) }
        finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($BSTR) }
    }

    kubectl create secret docker-registry regcred `
      --docker-server=https://index.docker.io/v1/ `
      --docker-username=$dockerUser `
      --docker-password=$plainPat `
      --namespace=fawry-task

    if ($LASTEXITCODE -ne 0) {
        Write-Host "regcred create FAILED" -ForegroundColor Red
        exit 1
    }
    $plainPat = $null
    Write-Host "regcred created, nothing saved to file!" -ForegroundColor Green
} else {
    Write-Host "regcred exists in cluster. Skip." -ForegroundColor Green
}

Write-Host "3. Setting up TLS Certificate & Secret..." -ForegroundColor Cyan
if (-not (Test-Path "tls.crt") -or -not (Test-Path "tls.key")) {
    Write-Host "   Generating new OpenSSL Certificate..." -ForegroundColor DarkYellow
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 `
      -keyout tls.key -out tls.crt `
      -subj "/CN=flask-app.com"
}
kubectl create secret tls flask-tls-secret `
  --cert=tls.crt `
  --key=tls.key `
  --namespace=fawry-task `
  --dry-run=client -o yaml | kubectl apply -f -

Write-Host "4. Applying Secrets..." -ForegroundColor Cyan
kubectl apply -f ./secrets/

Write-Host "5. Applying ConfigMaps..." -ForegroundColor Cyan
kubectl apply -f ./configmaps/

Write-Host "6. Applying Network Policies..." -ForegroundColor Cyan
kubectl apply -f ./network-policies/

Write-Host "7. Applying Services..." -ForegroundColor Cyan
kubectl apply -f ./services/

Write-Host "8. Deploying Workloads (StatefulSet & Deployment)..." -ForegroundColor Cyan
kubectl apply -f ./deployments/

Write-Host "9. Applying Ingress Routing..." -ForegroundColor Cyan
kubectl apply -f ./ingress/

Write-Host "Deployment Completed! Checking status..." -ForegroundColor Green
kubectl get all,pvc,ingress,netpol -n fawry-task
#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"
NS=fawry-task

echo "1. Creating Namespace..."
kubectl apply -f Namespace.yaml

echo "2. Checking Docker Registry Secret (regcred)..."
if [[ -z "$(kubectl get secret regcred -n "$NS" --ignore-not-found -o name)" ]]; then
  echo "   regcred not found. Creating securely..."

  DOCKER_USER="${DOCKERHUB_USER:-}"
  if [[ -z "$DOCKER_USER" ]]; then
    read -rp "Docker Hub username: " DOCKER_USER
  fi

  DOCKER_PAT="${DOCKERHUB_TOKEN:-}"
  if [[ -z "$DOCKER_PAT" ]]; then
    read -rsp "Docker Hub access token (read-only): " DOCKER_PAT
    echo
  fi

  if ! kubectl create secret docker-registry regcred \
      --docker-server=https://index.docker.io/v1/ \
      --docker-username="$DOCKER_USER" \
      --docker-password="$DOCKER_PAT" \
      --namespace="$NS"; then
    echo "   regcred create FAILED"
    exit 1
  fi
  unset DOCKER_PAT
  echo "   regcred created, nothing saved to file"
else
  echo "   regcred exists in cluster. Skip."
fi

echo "3. Setting up TLS Certificate & Secret..."
if [[ ! -f tls.crt || ! -f tls.key ]]; then
  echo "   Generating new OpenSSL Certificate..."
  openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout tls.key -out tls.crt \
    -subj "/CN=flask-app.com"
fi
kubectl create secret tls flask-tls-secret \
  --cert=tls.crt \
  --key=tls.key \
  --namespace="$NS" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "4. Applying Secrets..."
kubectl apply -f ./secrets/

echo "5. Applying ConfigMaps..."
kubectl apply -f ./configmaps/

echo "6. Applying Network Policies..."
kubectl apply -f ./network-policies/

echo "7. Applying Services..."
kubectl apply -f ./services/

echo "8. Deploying Workloads (StatefulSet & Deployment)..."
kubectl apply -f ./deployments/

echo "9. Applying Ingress Routing..."
kubectl apply -f ./ingress/

echo "Deployment Completed! Checking status..."
kubectl get all,pvc,ingress,netpol -n "$NS"
# Kubernetes Multi-Tier Deployment: Flask (BucketList) & MySQL

[![Kubernetes](https://img.shields.io/badge/Kubernetes-v1.28+-326CE5?logo=kubernetes&logoColor=white)](https://kubernetes.io/)
[![KinD](https://img.shields.io/badge/Cluster-KinD%202--Node-blue)](https://kind.sigs.k8s.io/)
[![Calico](https://img.shields.io/badge/CNI-Calico%20v3.27-F9A825)](https://www.tigera.io/project-calico/)
[![Ingress](https://img.shields.io/badge/Ingress-NGINX%20TLS-009639)](https://kubernetes.github.io/ingress-nginx/)

A declarative, multi-node Kubernetes deployment for a containerized Python Flask web application (`BucketList`) backed by a MySQL `StatefulSet`. Deployed on a 2-node KinD cluster (1 control-plane + 1 worker) with standard Kubernetes `NetworkPolicy` isolation enforced by Calico, host-based TLS Ingress routing, dynamic PVC provisioning, and automated PowerShell/Bash bootstrap scripts.

---

## 🏗️ 1. Architecture & Traffic Flow

```text
                         [ Client Request ]
                                 │
                                 ▼
                    [ NGINX Ingress (TLS:443) ]
                      │ (Host: flask-app.com)
                      ▼
            [ Service: flask-service (ClusterIP:80) ]
            [ Service: flask-nodeport-service (:30008) ] (Bonus hook)
                      │
                      ▼
     ┌─────────────────────────────────────────────────────┐
     │              Flask Web App (Deployment)             │
     │     - Replicas: 2                                   │
     │     - Probes: Startup, Liveness, Readiness          │
     │     - Resources: Req(64Mi, 100m) / Lim(256Mi, 300m) │
     └─────────────────────────────────────────────────────┘
                              │
                              │ TCP :3306 (Allowed only from app=flask-app)
                              ▼
     ┌─────────────────────────────────────────────────────┐
     │     Kubernetes NetworkPolicy (enforced by Calico)   │
     │       Allows: app=flask-app ONLY | Denies: Rest     │
     └─────────────────────────────────────────────────────┘
                              │
                              ▼
             [ Service: db-service (ClusterIP:3306) ]
                              │
                              ▼
     ┌─────────────────────────────────────────────────────┐
     │             MySQL Database (StatefulSet)            │
     │     - Replicas: 2 (mysql-0, mysql-1)                │
     │     - Storage: volumeClaimTemplates (500Mi)         │
     │     - Probes: tcpSocket on port 3306                │
     │     - Resources: Req(256Mi, 250m) / Lim(512Mi, 500m)│
     └─────────────────────────────────────────────────────┘
```

---

## 📁 2. Repository Layout

```text
fawry-k8s-flask-mysql/
├── .gitignore                          # Ignores generated TLS keys/certs & local temp files
├── README.md                           # Architecture, runbook, and design trade-offs
├── flaskapp/                           # Python Flask application source & Dockerfile
├── mysql/                              # MySQL schema init script (BucketList.sql) & Dockerfile
├── kind/
│   ├── KindCluster.yaml                # 2-node KinD topology (ports 80/443, disableDefaultCNI)
│   ├── CreateKindCluster.ps1           # Cluster bootstrap + Calico CNI + NGINX Ingress setup
│   └── DeleteKindCluster.ps1           # Cluster teardown script
└── k8s/
    ├── Namespace.yaml                  # Dedicated 'fawry-task' namespace
    ├── apply-all.ps1                   # Deployment & secret bootstrap script (Windows PowerShell)
    ├── Bash-apply-all.sh               # Deployment & secret bootstrap script (Linux/macOS Bash)
    ├── configmaps/
    │   ├── flask-config.yaml           # Flask database connection parameters
    │   └── mysql-config.yaml           # MySQL database name parameter
    ├── secrets/
    │   └── mysql-secret.yaml           # Local dev database credentials
    ├── network-policies/
    │   └── db-network-policy.yaml      # Standard K8s NetworkPolicy restricting TCP :3306 to Flask
    ├── services/
    │   ├── flask-service.yaml          # Internal ClusterIP (Port 80 -> Target 5002)
    │   ├── mysql-service.yaml          # Internal ClusterIP (Port 3306)
    │   └── flask-nodeport-service.yaml # Bonus NodePort test hook (Port 30008)
    ├── deployments/
    │   ├── flask-deployment.yaml       # 2-replica Flask web tier with HTTP probes & limits
    │   └── mysql-statefulset.yaml      # 2-replica MySQL StatefulSet with dynamic PVCs
    └── ingress/
        └── flask-ingress.yaml          # Host-based TLS Ingress rule for flask-app.com
```

---

## 🐳 3. Container Images (Build & Push)

Both images are built explicitly for `linux/amd64` and pushed to Docker Hub under tag `v1`. Per the assignment's private-registry requirement, **`mysql-db` is hosted in a private Docker Hub repository** (pulled via `imagePullSecrets: regcred`), while **`flask-app` is public**.

```bash
# 1. Build & push Flask web app image (Public repository)
docker build --platform linux/amd64 -t userName/flask-app:v1 ./flaskapp
docker push userName/flask-app:v1

# 2. Build & push MySQL database image (Private repository)
docker build --platform linux/amd64 -t userName/mysql-db:v1 ./mysql
docker push userName/mysql-db:v1
```
> **Note:** `mysql-db` is a private repository, so you cannot pull mine.
> Replace `userName` with your own Docker Hub username, push both images to your account
> (keep `mysql-db` private), and update the `image:` fields (currently `kirollous03/...`) in
> `k8s/deployments/flask-deployment.yaml` and `k8s/deployments/mysql-statefulset.yaml`.
> The deploy scripts will then create `regcred` from your own credentials.
---

## ⚙️ 4. Prerequisites & Cluster Provisioning

### Prerequisites
- Docker Engine
- `kind` & `kubectl`
- `openssl` (for generating local self-signed TLS certificates)

### Why KinD?
**KinD** was chosen deliberately to satisfy the multi-node requirement (**1 control-plane + 1 worker**) while avoiding Minikube's single-node limitation. Under the hood, KinD bootstraps conformant Kubernetes clusters using **`kubeadm`** and allows disabling the default CNI (`disableDefaultCNI: true`) so **Calico (`v3.27.0`)** can enforce standard `NetworkPolicy` resources cleanly on a local workstation.

### Provision the 2-Node Cluster
```powershell
cd kind
.\CreateKindCluster.ps1
```

> **Note:** The `kind/` scripts are written in PowerShell and expect to run from inside `kind/`. On Linux/macOS without `pwsh`, execute the `kind create` and `kubectl` commands inside `CreateKindCluster.ps1` directly (pausing a few seconds after `tigera-operator.yaml` if Calico CRDs are still registering).

To tear down the cluster later:
```powershell
cd kind
.\DeleteKindCluster.ps1
```

---

## 🚀 5. Application Deployment

Both scripts create the `fawry-task` namespace, bootstrap the `regcred` registry secret at runtime, generate local self-signed TLS certificates if missing, and apply all manifests in dependency order.

### Windows (PowerShell)
> Run from inside `k8s/` so relative manifest paths resolve properly.
```powershell
cd k8s
.\apply-all.ps1
```

### Linux / macOS (Bash)
> `Bash-apply-all.sh` resolves its own working directory automatically.
```bash
cd k8s
chmod +x Bash-apply-all.sh
./Bash-apply-all.sh
```

> **Credential Handling:** Registry tokens are never committed to Git. If `regcred` does not already exist in the cluster, both scripts read `DOCKERHUB_USER`/`DOCKERHUB_TOKEN` from environment variables or prompt interactively, create the secret in-cluster, and clear the token from memory immediately afterward.

---

## 🔍 6. Verification & Testing

### 1. Inspect All Cluster Resources
```bash
kubectl get all,pvc,ingress,netpol -n fawry-task
```

### 2. Test via Host-Based TLS Ingress (`flask-app.com`)
Host-based routing (`https://flask-app.com/`) was chosen over path-based routing (e.g., `/flask`) so Flask's relative static assets and template routes work cleanly without NGINX URL rewrite rules.

Add the local mapping to your hosts file (`/etc/hosts` on Linux/macOS or `C:\Windows\System32\drivers\etc\hosts` on Windows):
```text
127.0.0.1 flask-app.com
```
Then verify via `curl` or browser:
```bash
curl -k https://flask-app.com
```
*Quick alternative without editing `/etc/hosts`:*
```bash
curl -k --resolve flask-app.com:443:127.0.0.1 https://flask-app.com
```

> **Testing Note (MySQL Split-Brain Symptom):** Because `replicas: 2` runs two independent MySQL instances behind `db-service` without replication, signing up and immediately signing in may fail intermittently if the requests hit different replicas (`mysql-0` vs `mysql-1`). This is expected under the un-replicated 2-replica rubric; see Section 7 below.

### 3. Test via NodePort Service (Bonus Rubric)
`KindCluster.yaml` maps host ports `80` and `443` for Ingress. To test the NodePort (`:30008`) directly:
- **On Linux / Docker bridge network:**
  ```bash
  WORKER_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' k8s-fawry-worker)
  curl http://$WORKER_IP:30008
  ```
- **On Windows/macOS hosts:** either expose port `30008` in `KindCluster.yaml` under `extraPortMappings` or test service routing via `kubectl port-forward svc/flask-service 5002:80 -n fawry-task`.

### 4. Verify NetworkPolicy Isolation
Confirm that unauthorized pods (without label `app: flask-app`) cannot reach MySQL on port `3306`:
```bash
kubectl run netpol-test --rm -it --image=busybox -n fawry-task -- nc -zvw 3 db-service 3306
```
**Expected result:** Connection times out / is dropped by Calico.

---

## 🧠 7. Engineering Decisions, Trade-offs & Troubleshooting

### 1. Host OOM Crash & MySQL Stale Volume State
* **Issue:** During initial deployment, host RAM exhaustion terminated the Docker daemon and KinD nodes mid-initialization. Upon restart, Flask recovered while MySQL pods entered `CrashLoopBackOff` during `docker-entrypoint.sh`.
* **Root Cause:** Rebuilding and re-tagging the MySQL image did not fix the crash because persistent state lives on the mounted PVC (`/var/lib/mysql`), which was left in a dirty, half-initialized state after the abrupt OOM kill.
* **Resolution:** Torn down the stale cluster and recreated it cleanly with sufficient memory headroom so dynamic PVCs initialized from scratch.

### 2. Storage & Dynamic Provisioning Scope
* Rather than configuring static `hostPath` PersistentVolumes manually, the MySQL `StatefulSet` uses `volumeClaimTemplates` backed by KinD's default `standard` `StorageClass` (`rancher.io/local-path`), which dynamically provisions and binds a dedicated PV per replica. Standalone NFS server provisioning (bonus) was not implemented for this local setup.

### 3. Known Architectural Trade-offs
* **MySQL `replicas: 2` & Split-Brain Risk:** Matches the assignment rubric (`2 replicas` behind a `ClusterIP` service). Without replication (e.g., MySQL InnoDB Cluster or a MySQL Operator), `mysql-0` and `mysql-1` hold divergent data. Moving to a Headless Service targeting `mysql-0` (or an Operator) is planned next.
* **NodePort Alongside Ingress:** Added solely as the assignment's bonus test hook; production clusters should terminate external traffic exclusively at the Ingress/Gateway layer.
* **Ingress Controller Lifecycle:** `kubernetes/ingress-nginx` matches the assignment spec. Because the community `ingress-nginx` project reached retirement in March 2026, greenfield production deployments should target Kubernetes **Gateway API** or an actively maintained controller.

---

## 🚧 8. Roadmap (Toward `v2.0.0`)

- [ ] **High-Cohesion Refactor & Split-Brain Mitigation:** Consolidate manifests into per-component files, convert `db-service` to a Headless Service (`clusterIP: None`) routing Flask to `mysql-0.db-service` until an Operator is introduced, and drop the redundant NodePort.
- [ ] **CI & Security Scanning:** Add GitHub Actions workflow with automated builds and **Trivy** image/manifest scans.
- [ ] **Packaging & GitOps:** Package manifests as a **Helm** chart and deploy via **Argo CD**.
- [ ] **Secrets & Observability:** Replace static dev `mysql-secret.yaml` with **External Secrets / Vault**, and add **Prometheus & Loki**.
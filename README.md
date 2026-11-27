# Kubernetes Multi-Tier Deployment: Flask (BucketList) & MySQL

[![Kubernetes](https://img.shields.io/badge/Kubernetes-v1.28+-326CE5?logo=kubernetes&logoColor=white)](https://kubernetes.io/)
[![KinD](https://img.shields.io/badge/Cluster-KinD%202--Node-blue)](https://kind.sigs.k8s.io/)
[![Calico](https://img.shields.io/badge/CNI-Calico%20v3.27-F9A825)](https://www.tigera.io/project-calico/)
[![Ingress](https://img.shields.io/badge/Ingress-NGINX%20TLS-009639)](https://kubernetes.github.io/ingress-nginx/)

A declarative, multi-node Kubernetes deployment for a containerized Python Flask web application (`BucketList`) backed by a MySQL `StatefulSet`. Deployed on a 2-node KinD cluster (1 control-plane + 1 worker) with standard Kubernetes `NetworkPolicy` isolation enforced by Calico, host-based TLS Ingress routing, Headless Service database pinning, and automated PowerShell/Bash bootstrap scripts.

---

## ⚡ Quick Start (Copy & Run 1-2-3-4)

Assuming you have **Docker Desktop**, **`kind`**, **`kubectl`**, and **`openssl`** installed:

```powershell
# 1. Create the 2-node KinD cluster (with Calico CNI & NGINX Ingress)
cd kind
.\CreateKindCluster.ps1

# 2. Deploy the entire stack (Namespace, Secrets, ConfigMap, NetPol, MySQL, Flask)
cd ..\k8s
.\apply-all.ps1

# 3. Map the local domain (run PowerShell as Administrator)
Add-Content -Path "$env:SystemRoot\System32\drivers\etc\hosts" -Value "`n127.0.0.1 flask-app.com"

# 4. Verify the app is live (or open https://flask-app.com in your browser)
curl -k https://flask-app.com
```
> **Note:** On Linux/macOS without PowerShell, run the `kind` / `kubectl` commands inside `kind/CreateKindCluster.ps1` directly, then run `chmod +x Bash-apply-all.sh && ./Bash-apply-all.sh` inside `k8s/`. (See detailed notes below.)

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
         [ Headless Service: db-service (clusterIP: None) ]
                              │
                              │ Direct DNS: mysql-0.db-service
                              ▼
     ┌─────────────────────────────────────────────────────┐
     │             MySQL Database (StatefulSet)            │
     │     - Replicas: 2 (mysql-0 active, mysql-1 standby) │
     │     - Storage: volumeClaimTemplates (500Mi)         │
     │     - Probes: tcpSocket on port 3306                │
     │     - Resources: Req(256Mi, 250m) / Lim(512Mi, 500m)│
     └─────────────────────────────────────────────────────┘
```

---

## 📁 2. Repository Layout

```text
fawry-k8s-flask-mysql/
├── .gitignore                      # Ignores generated TLS keys/certs & local temp files
├── README.md                       # Architecture, quick start, and troubleshooting guide
├── flaskapp/                       # Python Flask application source & Dockerfile
├── mysql/                          # MySQL schema init script (BucketList.sql) & Dockerfile
├── kind/
│   ├── KindCluster.yaml            # 2-node KinD topology (ports 80/443, disableDefaultCNI)
│   ├── CreateKindCluster.ps1       # Cluster bootstrap + Calico CNI + pinned NGINX Ingress
│   └── DeleteKindCluster.ps1       # Cluster teardown script
└── k8s/
    ├── Namespace.yaml              # Dedicated 'fawry-task' namespace
    ├── apply-all.ps1               # Automated deployment script (Windows PowerShell)
    ├── Bash-apply-all.sh           # Automated deployment script (Linux/macOS Bash)
    ├── secrets.yaml                # Local dev MySQL credentials
    ├── configMap.yaml              # Flask DB config (points host to mysql-0.db-service)
    ├── db-network-policy.yaml      # Standard K8s NetworkPolicy restricting TCP :3306 to Flask
    ├── mysql-statefulset.yaml      # Headless db-service + 2-replica MySQL StatefulSet
    └── flask-deployment.yaml       # Ingress + ClusterIP Service + 2-replica Flask Deployment
```

*(Note: The original 11-folder submission structure is preserved in git tag `v1.0-fawry-rubric`.)*

---

## 🐳 3. Container Images (Public vs Private)

Per the private-registry requirement:
* **`flask-app` (`kirollous03/flask-app:v1`)** is hosted in a **Public** Docker Hub repository.
* **`mysql-db` (`kirollous03/mysql-db:v1`)** is hosted in a **Private** Docker Hub repository (pulled via `imagePullSecrets: regcred`).

Because `mysql-db` is private, anyone cloning this repo should build and push their own images to Docker Hub:

```bash
# 1. Build & push Flask image (Public repo)
docker build -t <YOUR_DOCKERHUB_USER>/flask-app:v1 ./flaskapp
docker push <YOUR_DOCKERHUB_USER>/flask-app:v1

# 2. Build & push MySQL image (keep this repo Private)
docker build -t <YOUR_DOCKERHUB_USER>/mysql-db:v1 ./mysql
docker push <YOUR_DOCKERHUB_USER>/mysql-db:v1
```
*(Tip for Apple Silicon / ARM Macs: add `--platform linux/amd64` to `docker build` if your cluster nodes are `amd64`.)*

**Update image references before deploying:**
* Search for `kirollous03/flask-app:v1` in `k8s/flask-deployment.yaml` and replace with `<YOUR_DOCKERHUB_USER>/flask-app:v1`.
* Search for `kirollous03/mysql-db:v1` in `k8s/mysql-statefulset.yaml` and replace with `<YOUR_DOCKERHUB_USER>/mysql-db:v1`.

---

## ⚙️ 4. Cluster Provisioning & Deployment Details

### Why KinD?
**KinD** was chosen to provide a local multi-node Kubernetes cluster (**1 control-plane + 1 worker**) via Docker Desktop on Windows without spinning up heavy extra VMs. Under the hood, KinD bootstraps nodes using **`kubeadm`** and allows `disableDefaultCNI: true` (`podSubnet: 192.168.0.0/16`) so **Calico (`v3.27.0`)** can enforce `NetworkPolicy` rules.

### Cluster Provisioning (`kind/`)
The scripts in `kind/` are written in PowerShell and expect to be executed from inside `kind/`:
```powershell
cd kind
.\CreateKindCluster.ps1
```
> **Linux/macOS Note:** Run the `kind create` and `kubectl` commands inside `CreateKindCluster.ps1` directly (pausing a few seconds after applying `tigera-operator.yaml` if Calico CRDs are still registering).

To delete the cluster when finished:
```powershell
cd kind
.\DeleteKindCluster.ps1
```

### Application Deployment (`k8s/`)
* **Windows:** Run `.\apply-all.ps1` from inside `k8s/`.
* **Linux/macOS:** Run `./Bash-apply-all.sh` (it automatically resolves its own directory).

> **Handling `regcred` Errors:** Registry credentials are never committed to Git; the scripts prompt you in-memory if `regcred` is missing. If you accidentally enter a wrong Docker Hub username or token and MySQL enters `ImagePullBackOff`, delete the secret and re-run the script to enter them again:
> ```bash
> kubectl delete secret regcred -n fawry-task
> ```

---

## 🔍 5. Verification & Testing

### 1. Check All Cluster Resources
```bash
kubectl get all,pvc,ingress,netpol -n fawry-task
```

### 2. Test via TLS Ingress (`flask-app.com`)
Host-based routing (`https://flask-app.com/`) was chosen over path-based routing so Flask's relative static assets work cleanly without NGINX URL rewrite rules.
* Verify with `curl` (or open `https://flask-app.com` in your browser and accept the local self-signed certificate warning):
```bash
curl -k https://flask-app.com
```
*Quick test without editing your `hosts` file:*
```bash
curl -k --resolve flask-app.com:443:127.0.0.1 https://flask-app.com
```

### 3. Verify Headless DNS & Zero Split-Brain
Confirm `mysql-0.db-service` resolves directly to `mysql-0`'s Pod IP:
```bash
kubectl run dns-test --rm -it --image=busybox -n fawry-task -- nslookup mysql-0.db-service
```
Sign up, sign in, add a wish, log out, and sign back in at `https://flask-app.com` — all requests consistently hit `mysql-0`.

### 4. Verify NetworkPolicy Isolation
Confirm that unauthorized pods (without label `app: flask-app`) cannot reach MySQL on port `3306`:
```bash
kubectl run netpol-test --rm -it --image=busybox -n fawry-task -- nc -zvw 3 db-service 3306
```
**Expected result:** Connection times out / is dropped by Calico.

---

## 🧠 6. Engineering Decisions & Issues Solved

### 1. Host RAM Exhaustion & Stuck MySQL Storage State
* **Issue:** During the first cluster run, host RAM filled up completely (Out-Of-Memory), causing Docker Desktop and the KinD cluster to crash. After restarting, Flask came up fine, while MySQL pods failed during `docker-entrypoint.sh` startup.
* **Why rebuilding image tags didn't fix it:** Even after rebuilding and pushing new MySQL image versions, the error persisted because the crash interrupted first-time DB initialization mid-way, leaving `/var/lib/mysql` on the persistent volume in a corrupted half-initialized state. Since database state lives on the volume (not in the image layers), changing image tags had no effect.
* **Fix:** Deleted the cluster completely to wipe the corrupted volumes, freed up RAM, and recreated the cluster cleanly.

### 2. NGINX Ingress Scheduled on `worker` Instead of `control-plane`
* **Issue:** `curl -k https://flask-app.com` failed with `curl: (35) Connection was aborted` / `curl: (52) Empty reply`, even though `kubectl port-forward` to the controller worked.
* **Root Cause:** Docker Desktop does not allow mapping the same host ports (`80`/`443`) to two node containers simultaneously, so `KindCluster.yaml` maps `extraPortMappings` (`80`/`443`) strictly on `control-plane` (labeled `ingress-ready=true`). However, the latest upstream `ingress-nginx` Kind manifest drops `ingress-ready: "true"` from its `nodeSelector`, allowing Kubernetes to schedule the Ingress pod onto the `worker` node — leaving `control-plane` ports `80/443` with no listener.
* **Fix:** Updated `kind/CreateKindCluster.ps1` to automatically patch `ingress-nginx-controller` with `nodeSelector: {"ingress-ready": "true"}` and wait cleanly using `kubectl rollout status`.

### 3. Headless Service (`clusterIP: None`) vs MySQL Replication
* **Decision:** To satisfy the 2-replica `StatefulSet` layout without burning ~1.5 GB+ extra RAM on a full MySQL Replication Operator, `db-service` was converted to a **Headless Service (`clusterIP: None`)** and Flask connects directly to `mysql-0.db-service`. This prevents split-brain while keeping `mysql-1` running as an idle standby until replication is added later.

### 4. Storage & Ingress Lifecycle Notes
* **Storage:** Uses KinD's default `standard` `StorageClass` (`rancher.io/local-path`) via `volumeClaimTemplates` to dynamically provision a 500Mi volume per replica (static `hostPath` PVs and NFS were not implemented locally).
* **Ingress Controller:** `kubernetes/ingress-nginx` is used to match the original project setup. Note that the community `ingress-nginx` project reached retirement in March 2026; greenfield production clusters should target the Kubernetes **Gateway API** or an actively maintained controller.

---

## 🚧 7. Roadmap (Toward `v2.0.0`)

- [x] **High-Cohesion Refactor & Split-Brain Mitigation:** Consolidated manifests into 6 cohesive files, switched `db-service` to a Headless Service (`clusterIP: None`) routing Flask to `mysql-0.db-service`, and pinned `ingress-nginx` to `control-plane`.
- [ ] **Packaging with Helm:** Package manifests into a parameterized Helm chart (`values.yaml` + `templates/`).
- [ ] **CI & Security Scanning:** Add GitHub Actions workflow for automated Docker builds and **Trivy** vulnerability/misconfiguration scans.
- [ ] **GitOps CD:** Deploy **Argo CD** inside KinD to auto-sync the Helm chart from GitHub.
- [ ] **Observability:** Add lightweight **Prometheus, Grafana, and Loki** for cluster metrics and centralized container logs.

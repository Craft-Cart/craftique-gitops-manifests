# Craftique — GitOps Manifests (Detailed File Map)

This document describes every folder and file present in this repository and explains exactly what each manifest, YAML, or configuration does. Use this as a reference when auditing the repository, onboarding, or preparing a GitOps deployment with Argo CD.

## 🔐 Secrets Management

**This repository uses GCP Secret Manager with External Secrets Operator for secure secrets management.**

📖 **Quick Start**: See [GCP-SECRETS-QUICKSTART.md](GCP-SECRETS-QUICKSTART.md) (5 minutes)  
📚 **Full Guide**: See [GCP-SECRETS-SETUP.md](GCP-SECRETS-SETUP.md) (complete documentation)

**Cost**: $0/month (within GCP free tier)

---

Repository root
- `LICENSE` — project license file.
- `.gitignore` — Git ignore rules (includes GCP key exclusions).
- `README.md` — this file.
- `GCP-SECRETS-QUICKSTART.md` — Quick 5-minute GCP Secret Manager setup guide.
- `GCP-SECRETS-SETUP.md` — Complete GCP Secret Manager documentation.

Top-level folders
- `apps/` — Kubernetes manifests for the application services (frontend and backend).
- `argocd/` — Argo CD Application definitions used to instruct Argo CD what to sync.
- `infrastructure/` — infrastructure components (Postgres, External Secrets Operator).
- `networking/` — Ingress and NetworkPolicy resources.
- `scripts/` — Automation scripts for setup.

------

Detailed file-by-file description

1) `apps/`

  a) `apps/backend/`
    - `backend-deployment.yaml`
      - Kind: `Deployment` (apiVersion: `apps/v1`).
      - Metadata: `name: craftique-backend`, `namespace: default`.
      - Purpose: Runs the backend API. Key configuration:
        - `replicas: 2` for availability.
        - `securityContext` on the Pod: runs processes as non-root (`runAsUser: 1001`, `runAsGroup: 1001`, `fsGroup: 1001`). This enforces least privilege for container process UIDs.
        - Container `image: craftique-backend:latest` (placeholder — replace with real image registry path before production).
        - Exposes container port `8000`.
        - Environment variables:
          - `PORT=8000` — default port used by the app.
          - `DATABASE_URL` — set to a connection string that points to the `postgres-service` (note: this currently contains a temporary password and should be replaced with a secret managed by an external secret manager).
        - Resource requests/limits present to reduce noisy-neighbor risk.
        - `livenessProbe` configured to `GET /health` on port `8000` (initialDelay 30s).

    - `backend-service.yaml`
      - Kind: `Service` (apiVersion: `v1`).
      - Metadata: `name: backend-service`, `namespace: default`.
      - Purpose: Exposes the backend `Deployment` internally.
      - Type: `ClusterIP` (internal only).
      - Port: `8000` -> `targetPort: 8000`.

  b) `apps/frontend/`
    - `frontend-deplyment.yaml` (note the filename typo: "deplyment")
      - Kind: `Deployment` (apiVersion: `apps/v1`).
      - Metadata: `name: craftique-frontend`, `namespace: default`.
      - Purpose: Runs the frontend (Next.js) application.
      - Key configuration:
        - `replicas: 2`.
        - `securityContext` runs as non-root (`runAsUser: 1001`).
        - Container `image: craftique-frontend:latest` (placeholder — replace with actual registry path).
        - Container port: `3000`.
        - Environment variable `NEXT_PUBLIC_API_BASE_URL` points to `https://craftique.chickenkiller.com/api/v1`.
        - Resource requests set (memory/cpu).

    - `frontend-service.yaml`
      - Kind: `Service` (apiVersion: `v1`).
      - Metadata: `name: frontend-service`, `namespace: default`.
      - Purpose: Exposes frontend Pods internally on port `3000`.
      - Type: `ClusterIP`.

2) `argocd/`
  - `craftique-app.yaml`
    - Kind: `Application` (apiVersion: `argoproj.io/v1alpha1`) for Argo CD.
    - Metadata: `name: craftique-platform`, located in Argo CD's `argocd` namespace.
    - Purpose: Tells Argo CD to track this repository (`repoURL: https://github.com/Craft-Cart/craftique-gitops-manifests.git`) at `targetRevision: main` and to sync the full repo (`path: .`, `directory.recurse: true`).
    - Destination: syncs to `https://kubernetes.default.svc` and `namespace: default` in-cluster.
    - `syncPolicy.automated` enabled with `prune: true` and `selfHeal: true`, and `CreateNamespace=true` in syncOptions (Argo CD will create the target namespace if missing).

3) `infrastructure/`

  a) `infrastructure/postgres/`
    - `postgres-configmap.yaml`
      - Kind: `ConfigMap` used to provide non-sensitive configuration values to the Postgres container.
      - Data keys:
        - `POSTGRES_DB: craftique`
        - `POSTGRES_USER: craftique`
      - **Security**: Non-sensitive values only. Sensitive credentials are managed via GCP Secret Manager.

    - `postgres-externalsecret.yaml`
      - Kind: `ExternalSecret` (external-secrets.io/v1beta1).
      - Purpose: Syncs secrets from GCP Secret Manager into a Kubernetes Secret named `postgres-credentials`.
      - Syncs three values: `POSTGRES_PASSWORD`, `POSTGRES_USER`, `POSTGRES_DB`.
      - Refresh interval: 1 hour (checks GCP for updates).
      - **Security**: Secrets never stored in Git, only synced from GCP at runtime.

    - `postgres-pvc.yaml`
      - Kind: `PersistentVolumeClaim`.
      - Purpose: Requests `10Gi` storage with access mode `ReadWriteOnce` and `storageClassName: standard-rwo` (GKE Standard RWO PD). This is intended to back the StatefulSet volume for durable database storage.

    - `postgres-service.yaml`
      - Kind: `Service` (ClusterIP headless).
      - Purpose: Headless service (`clusterIP: None`) used by the StatefulSet to give stable network identities to Postgres Pods. Exposes port `5432`.

    - `postgres-statefulset.yaml`
      - Kind: `StatefulSet` (apiVersion: `apps/v1`).
      - Purpose: Runs Postgres with persistent storage and a stable DNS identity. Key points:
        - `serviceName: postgres-service` matches the headless Service.
        - `replicas: 1` (single instance) — not highly available by default.
        - Container image: `postgres:15-alpine`.
        - `envFrom` reads values from `postgres-config` ConfigMap and `postgres-credentials` Secret (synced from GCP).
        - **Security**: All credentials loaded from GCP Secret Manager via ExternalSecret.
        - Mounts a `volumeClaimTemplates` based PVC named `postgres-data` that requests `10Gi` (so each replica gets its own PVC).
        - Resource requests/limits are set to avoid resource exhaustion.

  b) `infrastructure/external-secrets/`
    - `external-secrets-operator.yaml`
      - Kind: Multiple resources (Namespace, ServiceAccount, ClusterRole, ClusterRoleBinding, Deployment, CRDs).
      - Purpose: Deploys the External Secrets Operator that syncs secrets from external providers (GCP Secret Manager) into Kubernetes Secrets.
      - Image: `ghcr.io/external-secrets/external-secrets:v0.9.11`
      - **Security**: Runs as non-root (UID 65534) with read-only root filesystem.
      - Creates CRDs: `ExternalSecret`, `SecretStore`, `ClusterSecretStore`.

    - `gcp-secretstore.yaml`
      - Kind: `SecretStore` (external-secrets.io/v1beta1).
      - Purpose: Configures connection to GCP Secret Manager.
      - Requires: GCP project ID and service account credentials stored in Kubernetes Secret `gcp-secret-manager-key`.
      - **Setup**: See [GCP-SECRETS-SETUP.md](GCP-SECRETS-SETUP.md) for configuration instructions.

4) `networking/`
  - `ingress.yaml`
    - Kind: `Ingress` (networking.k8s.io/v1).
    - Purpose: Defines host `craftique.chickenkiller.com` with two path rules:
      - `/api` routes to `backend-service:8000`.
      - `/` routes to `frontend-service:3000`.
    - Annotations:
      - `kubernetes.io/ingress.class: nginx` — intended for the NGINX ingress controller.
      - `nginx.ingress.kubernetes.io/ssl-redirect: "false"` — currently disabled; should be `true` when TLS is configured.

  - `network-policies/allow-backend-to-db.yaml`
    - Kind: `NetworkPolicy` (networking.k8s.io/v1).
    - Purpose: Implements a default-allow rule specifically allowing Pods labeled `app: craftique-backend` to talk to Pods labeled `app: postgres` on TCP port `5432`.
    - Behavior: If a default-deny policy is in place elsewhere, this policy permits the backend-to-database traffic while leaving other access blocked (reduces lateral movement risk).

------

Security Implementation Summary

✅ **Secrets Management (Implemented)**
- **Solution**: External Secrets Operator + GCP Secret Manager
- **Status**: All database credentials synced from GCP (no plaintext in Git)
- **Features**:
  - Automatic secret rotation support (1-hour refresh interval)
  - Audit logging via GCP Cloud Logging
  - IAM-based access control
  - Encrypted at rest and in transit
- **Cost**: $0/month (within GCP free tier)
- **Documentation**: [GCP-SECRETS-SETUP.md](GCP-SECRETS-SETUP.md)

Security notes and TODOs (actionable)
- Images: Both `backend` and `frontend` images are placeholders (`craftique-backend:latest`, `craftique-frontend:latest`). Update manifests to point to immutable image digests (`myregistry/myimage@sha256:...`) from CI build artifacts.
- High availability: Postgres is configured as a single replica. Consider adding a managed cloud DB or a highly-available Postgres operator for production.
- TLS: `ingress.yaml` disables SSL redirect; add TLS secrets/certificate and enable HTTPS in production.

How to use this repo (quick references)

Apply everything directly (non-GitOps):

```bash
kubectl apply -R -f .
```

Install with Argo CD (GitOps):

1. Push the repository to your Git host.
2. Create an Argo CD `Application` that points to this repository and `path: .` (or use the included `argocd/craftique-app.yaml`).
3. Sync the Argo CD application and monitor health/refresh.

Maintenance checklist for operators
- Replace placeholder images with production image references.
- Remove plaintext passwords; integrate ExternalSecrets.
- Enable TLS for the Ingress and change `ssl-redirect: true`.
- Add resource limits/requests where missing and tune HPA if needed.
- Add a README or comments inside empty folders such as `infrastructure/redis/` to document intended uses.
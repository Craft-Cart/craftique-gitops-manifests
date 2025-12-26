# Craftique — GitOps Manifests (Detailed File Map)

This document describes every folder and file present in this repository and explains exactly what each manifest, YAML, or configuration does. Use this as a reference when auditing the repository, onboarding, or preparing a GitOps deployment with Argo CD.

Repository root
- `LICENSE` — project license file.
- `.gitignore` — Git ignore rules.
- `README.md` — this file.

Top-level folders
- `apps/` — Kubernetes manifests for the application services (frontend and backend).
- `argocd/` — Argo CD Application definitions used to instruct Argo CD what to sync.
- `infrastructure/` — infrastructure components such as Postgres and Redis.
- `networking/` — Ingress and NetworkPolicy resources.

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
      - Note: Credentials are not stored here; however the StatefulSet currently uses a plaintext `POSTGRES_PASSWORD` environment variable (see below). Replace with ExternalSecrets or K8s Secret in production.

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
        - `envFrom` reads values from `postgres-config`, and currently `POSTGRES_PASSWORD` is hard-coded to `craftique_temp_password` (marked TODO to be replaced by ExternalSecrets).
        - Mounts a `volumeClaimTemplates` based PVC named `postgres-data` that requests `10Gi` (so each replica gets its own PVC).
        - Resource requests/limits are set to avoid resource exhaustion.

  b) `infrastructure/redis/`
    - Folder currently empty. Placeholder for Redis manifests if cache or session storage is added later.

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

Security notes and TODOs (actionable)
- Secrets: The repository contains temporary plaintext credentials in `postgres-statefulset.yaml` (`POSTGRES_PASSWORD`) and `backend-deployment.yaml` (`DATABASE_URL` query string). Replace these with a secrets manager integration (ExternalSecrets Operator + cloud secrets store or Kubernetes Secrets encrypted with SealedSecrets/Vault).
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
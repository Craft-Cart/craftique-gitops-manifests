**Craftique GitOps Manifests — Project Overview**

This repository contains a GitOps-style collection of Kubernetes manifests, infrastructure definitions, and supporting configuration used to deploy the "Craftique" sample application. The primary intent of this repository is to represent a complete, declarative deployment layout that can be used with Argo CD (or other GitOps controllers) to provision and operate the application across environments.

**Table of Contents**
- **Project Summary** — high-level purpose and goals
- **Repository Layout** — major folders and their roles
- **Application Components** — backend and frontend manifests
- **Infrastructure Components** — database, storage, certificates, governance
- **Networking & Policies** — ingress and network policy design
- **GitOps & Deployment Flow** — how manifests are intended to be consumed
- **Security & Secrets** — recommended handling, where secrets appear
- **Operational Considerations** — scaling, backups, and upgrades

**Project Summary**
This repo stores all Kubernetes manifests and related infrastructure objects required to run the Craftique web application. The manifests are grouped to represent logical concerns (apps, infrastructure, network, argocd configuration). The repository is intended for a GitOps workflow where the Git repository is the single source of truth, and an automated controller (Argo CD) continuously reconciles a cluster with the declared state.

Goals
- Provide a clear, declarative layout for deploying the app
- Keep runtime configuration and infrastructure definitions versioned in Git
- Demonstrate GitOps patterns: environment separation, automated reconciliation, and promotion via Git

**Repository Layout (key folders)**
- `apps/` — Application manifests:
  - `apps/backend/` — Kubernetes Deployment/Service for the backend API (`backend-deployment.yaml`, `backend-service.yaml`).
  - `apps/frontend/` — Frontend deployment and service (`frontend-deplyment.yaml`, `frontend-service.yaml`).
- `infrastructure/` — Stateful and cluster-level infrastructure:
  - `infrastructure/postgres/` — ConfigMap, StatefulSet, PVCs, Service for Postgres.
  - `infrastructure/cert-manager/` — ACME issuer manifests used to request TLS certificates.
  - `infrastructure/governance/` — ResourceQuota, LimitRange, PodDisruptionBudgets.
  - `infrastructure/storage/` — Storage classes (encrypted storage classes manifest).
  - `infrastructure/redis/` — placeholder for Redis resources if used by the app.
- `networking/` — Ingress configuration and network policies that control traffic between pods and namespaces.
- `argocd/` — Argo CD application manifests used to point the GitOps controller at this repo.


**Application Components**
- Frontend: A stateless Deployment plus Service. The frontend is responsible for the client-side UI and connects to the backend API via the cluster network or ingress.
- Backend: A Deployment (or could be scaled) exposing a Service. The backend provides the REST/API endpoints and typically connects to Postgres and/or Redis.

Key manifest concerns
- Pod templates (resources, liveness/readiness probes)
- Service types (ClusterIP for internal, NodePort/LoadBalancer for external unless using Ingress)
- Environment variables and config from ConfigMap/Secrets

**Infrastructure Components**
- Postgres: Implemented as a StatefulSet with an associated PVC and Service to provide stable storage and network identity. See `infrastructure/postgres/postgres-statefulset.yaml` and `infrastructure/postgres/postgres-pvc.yaml`.
- Storage: StorageClass manifests define the class of persistent storage to request (including encryption settings) in `infrastructure/storage/`.
- Certificate management: `infrastructure/cert-manager/` contains Issuer/ClusterIssuer YAMLs to request TLS certs via ACME (Let's Encrypt). These are used by Ingress resources to provide HTTPS.

Important operations
- Database backups and restores must be added (not covered by these manifests). StatefulSet + PVC provide persistence but not backups.
- Schema migration strategy: use init jobs, migrations in CI/CD, or run-once Jobs during deploy.

**Networking & Policies**
- `networking/ingress.yaml` defines how external traffic is routed into the cluster and to which Service (frontend / backend).
- `networking/network-policies/` contains granular policies that restrict what can talk to what (e.g., only ingress can reach frontend, backend can reach Postgres, etc.). This minimizes blast radius.

Design patterns used
- Least privilege networking via NetworkPolicies
- Pod resource governance via LimitRange and ResourceQuota
- Use of PodDisruptionBudgets to control voluntary disruptions

**GitOps & Deployment Flow**
1. Developer updates manifests or application images in this Git repository.
2. A GitOps controller (Argo CD) monitors the repository and applies changes to the cluster automatically.
3. Promotion between environments (dev → staging → prod) is done by merging or branching strategies in Git, or via separate directories/Argo CD Applications per environment.

Files related to GitOps
- `argocd/craftique-app.yaml` — example Argo CD Application definition for installing the repo resources.

**Security & Secrets**
- Secrets: Kubernetes Secrets are the recommended way to store sensitive data, but they must be integrated with cluster secret management (e.g., SealedSecrets, External Secrets Operator, HashiCorp Vault). This repo contains manifests but sensitive values should not be stored in plaintext here.
- TLS: `cert-manager` issues certificates for Ingress; make sure issuers are configured for the intended cluster (staging vs production) and that ACME email/LE staging/production endpoints are set appropriately.
- RBAC: This repository does not appear to include Role/RoleBinding manifests; ensure Argo CD or the automation tool has the minimal necessary permissions.

**Operational Considerations**
- Observability: Add Prometheus, metrics, and log collection to monitor app health and resource usage.
- Scaling: Use HPA (HorizontalPodAutoscaler) if you want the backend/frontend to scale based on CPU/memory or custom metrics.
- Upgrades: Test DB migrations in a staging environment before applying to production.


**Appendix — Useful file pointers**
- Argo CD application: argocd/craftique-app.yaml
- Backend manifests: apps/backend/backend-deployment.yaml, apps/backend/backend-service.yaml
- Frontend manifests: apps/frontend/frontend-deplyment.yaml, apps/frontend/frontend-service.yaml
- Postgres infra: infrastructure/postgres/postgres-statefulset.yaml, infrastructure/postgres/postgres-pvc.yaml, infrastructure/postgres/postgres-service.yaml, infrastructure/postgres/postgres-configmap.yaml
- Networking and ingress: networking/ingress.yaml, networking/network-policies/
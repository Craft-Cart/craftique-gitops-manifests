**Application — Backend and Frontend (simple guide)**

This file explains the application manifests under `apps/` (backend and frontend) in plain language, shows where configuration and secrets are read, and includes short code snippets from the project's manifests.

High-level architecture
- Frontend: Next.js app served by a Deployment `craftique-frontend` + `frontend-service` (ClusterIP) on port 3000.
- Backend: API service served by a Deployment `craftique-backend` + `backend-service` (ClusterIP) on port 8000.
- The Ingress routes external requests to the frontend and backend paths.

Files covered
- `apps/backend/backend-deployment.yaml`
- `apps/backend/backend-service.yaml`
- `apps/frontend/frontend-deplyment.yaml`
- `apps/frontend/frontend-service.yaml`

1) Backend — key concepts
- Runs 2 replicas (scalable) and exposes port 8000 via `backend-service`.
- Reads DB config from `ConfigMap` and password from a Kubernetes Secret.
- Uses `imagePullSecrets` to pull images from GCP Artifact Registry.

Image and pull secret (snippet):

```yaml
image: europe-west10-docker.pkg.dev/craftique-482022/craftique-registry/backend:latest
imagePullSecrets:
  - name: gcp-pull-secret
```

Environment & secrets (snippet):

```yaml
- name: POSTGRES_USER
  valueFrom:
    configMapKeyRef:
      name: postgres-config
      key: POSTGRES_USER
- name: POSTGRES_PASSWORD
  valueFrom:
    secretKeyRef:
      name: postgres-password-secret
      key: POSTGRES_PASSWORD
- name: DATABASE_URL
  value: "postgresql://$(POSTGRES_USER):$(POSTGRES_PASSWORD)@postgres-service:5432/$(POSTGRES_DB)?schema=public"
```

Security & probes
- Runs as non-root (`runAsUser: 1001`) and disables privilege escalation.
- Liveness probe checks `/health` on port 8000.

Service (snippet):

```yaml
kind: Service
metadata:
  name: backend-service
spec:
  selector:
    app: craftique-backend
  ports:
    - port: 8000
      targetPort: 8000
  type: ClusterIP
```

Where to change image
- Update the `image:` field in `apps/backend/backend-deployment.yaml` to the new Artifact Registry image (prefer using image digest `@sha256:...` for immutability), then push commit and Argo CD will sync.

2) Frontend — key concepts
- Next.js app that needs both server-side API URL (`API_BASE_URL`) and client-side API URL (`NEXT_PUBLIC_API_BASE_URL`).
- Uses Auth0 credentials stored in a Kubernetes Secret named `auth0-credentials`.

Auth and API envs (snippet):

```yaml
- name: API_BASE_URL
  value: "http://backend-service:8000/api/v1"
- name: NEXT_PUBLIC_API_BASE_URL
  value: "https://craftique.chickenkiller.com/api/v1"
- name: AUTH0_CLIENT_ID
  valueFrom:
    secretKeyRef:
      name: auth0-credentials
      key: AUTH0_CLIENT_ID
```

Image and pull secret (snippet):

```yaml
image: europe-west10-docker.pkg.dev/craftique-482022/craftique-registry/frontend:latest
imagePullSecrets:
  - name: gcp-pull-secret
```

Service (snippet):

```yaml
kind: Service
metadata:
  name: frontend-service
spec:
  selector:
    app: craftique-frontend
  ports:
    - port: 3000
      targetPort: 3000
  type: ClusterIP
```

Security & runtime
- Frontend runs non-root and uses read-only filesystem and dropped capabilities where possible.

How the backend and frontend connect to Postgres and each other
- Backend uses `postgres-config` (ConfigMap) and a Secret for the password to build `DATABASE_URL`.
- Frontend talks to the backend via `backend-service:8000` inside the cluster and via the public host externally (configured in `NEXT_PUBLIC_API_BASE_URL`).

Useful commands
- Apply application manifests:
```bash
kubectl apply -f apps/backend/
kubectl apply -f apps/frontend/
```
- Check pods and services:
```bash
kubectl get pods -l app=craftique-backend
kubectl get svc backend-service frontend-service
```

Best practices (simple)
- Use image digests instead of `:latest` to avoid unexpected rollouts.
- Keep secrets out of Git (use External Secrets Operator or GitHub Actions + GSM as explained in `security_and_secrets.md`).
- Add resource requests/limits (already present) and tune them for production.
- Add readiness probes for graceful rollouts.

Next steps I can help with
- (A) Generate a GitHub Actions workflow that builds both images and updates manifests, or
- (B) Replace `:latest` with an example digest and show how to update via a script or PR.

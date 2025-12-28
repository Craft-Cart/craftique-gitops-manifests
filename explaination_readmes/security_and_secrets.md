**Security & Secrets — how this project uses Google Secret Manager (simple)**

This file explains, simply and with examples, where secrets live, how they are referenced, and the two recommended ways this repo can use Google Secret Manager (GSM) for Kubernetes workloads.

Goal
- Keep secrets out of Git and provide clear, reproducible ways to inject them into Kubernetes objects used by this repo (for example `apps/backend/backend-deployment.yaml`).

Two recommended patterns (short):
- Recommended (in-cluster): use External Secrets Operator (ESO) to sync GSM → Kubernetes Secret.
- Alternative (pipeline): GitHub Actions reads GSM and creates Kubernetes Secrets at deploy time.

Why not put raw secrets in Git
- Plain secret values in Git are a security risk. Use GSM + an operator or short-lived pipeline injection.

1) Recommended: External Secrets Operator (ESO)
- What it is: an in-cluster controller that reads secrets from external providers (GSM) and creates native Kubernetes Secrets.
- Benefits: no secret values in Git, Argo CD can manage only the `ExternalSecret` object (safe), easier rotations.

Minimal components you will create/see in this repo:
- A `ClusterSecretStore` or `SecretStore` (operator config) that tells ESO how to talk to GSM.
- An `ExternalSecret` that maps GSM secret keys → Kubernetes Secret keys.

Example: ClusterSecretStore (simple, using a JSON key secret — replace with Workload Identity for production)

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ClusterSecretStore
metadata:
  name: gcp-secret-store
spec:
  provider:
    gcp:
      projectID: YOUR_PROJECT_ID
      auth:
        secretRef:
          secretAccessKeySecretRef:
            name: gcp-credentials
            key: credentials.json
```

Example: ExternalSecret that creates a Kubernetes Secret named `postgres-credentials`

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: postgres-credentials-es
  namespace: default
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: gcp-secret-store
    kind: ClusterSecretStore
  target:
    name: postgres-credentials
    creationPolicy: Owner
  data:
    - secretKey: password
      remoteRef:
        key: projects/YOUR_PROJECT_ID/secrets/POSTGRES_PASSWORD
        version: latest
    - secretKey: username
      remoteRef:
        key: projects/YOUR_PROJECT_ID/secrets/POSTGRES_USER
        version: latest
```

How the app uses it: reference the created Kubernetes Secret in the backend Deployment

Example snippet from `apps/backend/backend-deployment.yaml` (envFrom / env):

```yaml
containers:
- name: backend
  image: us-central1-docker.pkg.dev/PROJECT/repo/backend:sha-abc1234
  env:
    - name: POSTGRES_USER
      valueFrom:
        secretKeyRef:
          name: postgres-credentials
          key: username
    - name: POSTGRES_PASSWORD
      valueFrom:
        secretKeyRef:
          name: postgres-credentials
          key: password
```

IAM and permissions (ESO approach)
- Grant the ESO service account (or the GCP service account) the `roles/secretmanager.secretAccessor` permission for each secret:

```bash
gcloud secrets add-iam-policy-binding projects/YOUR_PROJECT_ID/secrets/POSTGRES_PASSWORD \
  --member=serviceAccount:SERVICE_ACCOUNT_EMAIL \
  --role=roles/secretmanager.secretAccessor
```

Use Workload Identity (recommended) instead of storing JSON keys:
- Configure Workload Identity for the ESO pod/service account so it can access GSM without long-lived keys. This is the preferred production approach.

2) Alternative: GitHub Actions reads GSM and creates k8s Secrets at deploy time
- When to use: small projects or when you already run `kubectl` from CI and prefer pipeline-managed secrets.
- Drawback: secrets never live in Git, but Actions will need permission to read GSM and push secrets to the cluster.

Example GitHub Actions steps (pseudo):

```bash
# authenticate (prefer OIDC / Workload Identity; this example assumes gcloud is authenticated)
PASSWORD=$(gcloud secrets versions access latest --secret=POSTGRES_PASSWORD)
kubectl create secret generic postgres-credentials \
  --from-literal=password="$PASSWORD" \
  --from-literal=username="$USER" -n default --dry-run=client -o yaml | kubectl apply -f -
```

Then the `apps/backend/backend-deployment.yaml` uses the same `secretKeyRef` example above.

Where to look in this repo
- The Argo CD Application that watches the repo: `argocd/craftique-app.yaml` (Argo CD will apply your `ExternalSecret` objects).
- Backend Deployment where secrets are consumed: `apps/backend/backend-deployment.yaml` (edit the `env` section to use secretKeyRef as shown).
- Postgres resources that may reference secret data: `infrastructure/postgres/postgres-statefulset.yaml` and `infrastructure/postgres/postgres-configmap.yaml`.

Simple checklist to wire GSM → app (ESO approach)
1. Install External Secrets Operator in cluster.
2. Create a `ClusterSecretStore` or `SecretStore` telling ESO how to find GSM credentials (use Workload Identity for production).
3. Create `ExternalSecret` objects that map GSM keys to k8s Secret keys.
4. Ensure the ESO or its service account has `secretmanager.secretAccessor` for the GSM secrets.
5. Reference the created k8s Secret in `apps/backend/backend-deployment.yaml` via `valueFrom.secretKeyRef`.

Quick troubleshooting
- Secret not created: check ESO logs (`kubectl -n external-secrets logs deploy/external-secrets`), and confirm `ClusterSecretStore` is correct.
- Permission denied reading GSM: ensure IAM binding for `roles/secretmanager.secretAccessor` exists for the operator's service account.
- Secret values not visible to app: ensure secret name and key match those used in the Deployment's `valueFrom`.

Short recommendations (practical)
- Use ESO + Workload Identity in production.
- Keep `ExternalSecret` objects in Git (they are safe — they contain only references, not values).
- Do NOT commit raw secret values or JSON keys to Git. If a key was committed, rotate it immediately.

If you want, I can now:
- generate an `ExternalSecret` + `ClusterSecretStore` example pre-filled for your `POSTGRES_*` secrets and the minimal `gcloud` IAM commands, or
- create a small GitHub Actions workflow snippet that reads GSM and applies k8s Secrets during CI.

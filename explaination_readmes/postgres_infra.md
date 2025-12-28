**Postgres Infrastructure — simple guide**

This file explains the Postgres-related manifests in `infrastructure/postgres/` in plain language and shows short code snippets so you understand how the database is configured and used by the app.

Files covered
- `infrastructure/postgres/postgres-configmap.yaml` — non-sensitive DB settings
- `infrastructure/postgres/SECRET-SETUP.md` — instructions to create Kubernetes Secret (and GCP Secret Manager guidance)
- `infrastructure/postgres/postgres-pvc.yaml` — persistent volume claim for data storage
- `infrastructure/postgres/postgres-service.yaml` — headless Service for StatefulSet
- `infrastructure/postgres/postgres-statefulset.yaml` — StatefulSet running Postgres

Why this layout
- StatefulSet + PersistentVolumeClaim provides stable identity and persistent storage for Postgres.
- ConfigMap stores non-secret configuration (DB name, user).
- Secrets (passwords) are not in Git — see `SECRET-SETUP.md` for how to create them or sync from Google Secret Manager.

1) `postgres-configmap.yaml` — small, safe config

Snippet (actual):

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: postgres-config
  namespace: default
data:
  POSTGRES_DB: craftique
  POSTGRES_USER: craftique
  PGDATA: /var/lib/postgresql/data/pgdata
```

Simple: this sets the database name and user. Non-secret values go here so containers can read them via `envFrom: configMapRef`.

2) `SECRET-SETUP.md` — how to provide the password
- This file explains two options:
  - Create a Kubernetes Secret manually using `kubectl create secret generic postgres-credentials --from-literal=POSTGRES_PASSWORD=...` (for dev)
  - Use Google Secret Manager + External Secrets Operator (recommended for prod). See the file for commands and an example `ExternalSecret`.

Key point: the StatefulSet expects a Kubernetes Secret named `postgres-password-secret` (or `postgres-credentials` depending on which manifest you use). The StatefulSet reads `POSTGRES_PASSWORD` from a `secretKeyRef`.

3) `postgres-pvc.yaml` — persistent storage request

Snippet (actual):

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: postgres-pvc
  namespace: default
  labels:
    app: postgres
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 10Gi
  storageClassName: standard-rwo
```

Simple: this requests 10Gi of storage using the `standard-rwo` storage class (Google-managed encryption at rest in GKE by default).

4) `postgres-service.yaml` — headless Service used by StatefulSet

Snippet (actual):

```yaml
apiVersion: v1
kind: Service
metadata:
  name: postgres-service
  namespace: default
spec:
  ports:
    - port: 5432
      targetPort: 5432
  selector:
    app: postgres
  clusterIP: None # Headless service for StatefulSet
```

Simple: headless Service (`clusterIP: None`) means each pod in the StatefulSet gets its own DNS name (useful for clustering). The Service exposes Postgres on port 5432 to other pods.

5) `postgres-statefulset.yaml` — the running Postgres definition

Important parts (actual snippets):

Pod security and identity

```yaml
spec:
  serviceName: "postgres-service"
  replicas: 1
  selector:
    matchLabels:
      app: postgres
  template:
    metadata:
      labels:
        app: postgres
    spec:
      securityContext:
        fsGroup: 70
        runAsUser: 70
        runAsGroup: 70
```

Container config and secrets

```yaml
      containers:
        - name: postgres
          image: postgres:15-alpine
          envFrom:
            - configMapRef:
                name: postgres-config
          env:
            - name: POSTGRES_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: postgres-password-secret
                  key: POSTGRES_PASSWORD
```

Volume claim template

```yaml
  volumeClaimTemplates:
    - metadata:
        name: postgres-data
      spec:
        accessModes: ["ReadWriteOnce"]
        storageClassName: "standard-rwo"
        resources:
          requests:
            storage: 10Gi
```

Simple explanations:
- `securityContext` sets the user/group and fsGroup so the Postgres process can read/write the volume securely.
- `envFrom: configMapRef` loads the DB name and user from `postgres-config`.
- `env.valueFrom.secretKeyRef` loads the password from a Kubernetes Secret (name `postgres-password-secret`). This secret must exist before the Pod starts.
- `volumeClaimTemplates` creates a PVC per pod (managed by the StatefulSet) and mounts it at `/var/lib/postgresql/data`.

How the app connects
- Other pods (e.g., backend) connect to Postgres via the headless service DNS or service name `postgres-service` and port `5432`. The network policy `allow-backend-to-db.yaml` restricts connections so only backend pods may connect.

Quick commands (apply / verify)

Apply manifests:
```bash
kubectl apply -f infrastructure/postgres/postgres-configmap.yaml
kubectl apply -f infrastructure/postgres/postgres-pvc.yaml
kubectl apply -f infrastructure/postgres/postgres-service.yaml
kubectl apply -f infrastructure/postgres/postgres-statefulset.yaml
```

Verify pods and PVCs:
```bash
kubectl get pods -l app=postgres
kubectl get pvc -l app=postgres
kubectl describe pod postgres-0
kubectl logs postgres-0
```

Secret notes and mapping to the repo
- The StatefulSet expects a secret referenced as `postgres-password-secret` with key `POSTGRES_PASSWORD`. The repo contains `SECRET-SETUP.md` showing two options:
  - manual `kubectl create secret generic postgres-credentials` (for dev)
  - recommended: use Google Secret Manager + External Secrets Operator to sync GSM -> `postgres-credentials` (or `postgres-password-secret`) in-cluster for production.

Troubleshooting (simple)
- Pod won't start: check `kubectl describe pod` for `ImagePullBackOff`, `CrashLoopBackOff`, or `MountVolume` errors.
- Auth failures: ensure the Kubernetes Secret name and key match what the StatefulSet expects and that the password value is correct.
- Storage issues: check `kubectl get pvc` and `kubectl describe pvc postgres-data-0` for events.

Best practices (short)
- Do not store raw passwords in Git. Use GSM + External Secrets Operator for production.
- Keep ConfigMap for non-secret settings only.
- Use small resource requests and limits appropriate to your environment and increase for production.
- Backup strategy: add logical backups (pg_dump) or scheduled snapshot backups for PVCs — StatefulSet + PVC alone is not a backup.
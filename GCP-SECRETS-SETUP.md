# GCP Secret Manager Setup Guide

## Overview
This repository uses **External Secrets Operator (ESO)** with **GCP Secret Manager** for secure secrets management. Secrets are stored in GCP and automatically synced to Kubernetes.

## Why GCP Secret Manager?
- ✅ **Managed Service** - Google handles encryption, availability, and backups
- ✅ **Free Tier** - First 10,000 secret versions are free
- ✅ **IAM Integration** - Fine-grained access control
- ✅ **Audit Logging** - Track all secret access
- ✅ **Automatic Rotation** - Built-in rotation support
- ✅ **No External Dependencies** - Works with any Kubernetes cluster

## Cost (Within $300 Free Credit)
- First 10,000 secret versions: **FREE**
- Access operations: First 10,000/month **FREE**
- For this project: **~$0/month** (well within free tier)

## Architecture
```
GCP Secret Manager → External Secrets Operator → Kubernetes Secret → Pods
```

## Prerequisites
- GCP account with $300 free credits
- GCP project created
- `gcloud` CLI installed
- `kubectl` configured for your cluster

---

## Step-by-Step Setup

### 1. Install gcloud CLI (if not already installed)

**Windows:**
```powershell
# Download and run the installer
Invoke-WebRequest -Uri "https://dl.google.com/dl/cloudsdk/channels/rapid/GoogleCloudSDKInstaller.exe" -OutFile "$env:TEMP\GoogleCloudSDKInstaller.exe"
Start-Process -FilePath "$env:TEMP\GoogleCloudSDKInstaller.exe" -Wait
```

**macOS/Linux:**
```bash
curl https://sdk.cloud.google.com | bash
exec -l $SHELL
```

Authenticate:
```bash
gcloud auth login
gcloud config set project YOUR_PROJECT_ID
```

### 2. Enable GCP Secret Manager API

```bash
# Enable the Secret Manager API
gcloud services enable secretmanager.googleapis.com
```

### 3. Create Secrets in GCP Secret Manager

```bash
# Set your project ID
export PROJECT_ID="your-gcp-project-id"
gcloud config set project $PROJECT_ID

# Create PostgreSQL password secret
echo -n "$(openssl rand -base64 32)" | gcloud secrets create craftique-postgres-password \
  --data-file=- \
  --replication-policy="automatic"

# Create PostgreSQL user secret
echo -n "craftique" | gcloud secrets create craftique-postgres-user \
  --data-file=- \
  --replication-policy="automatic"

# Create PostgreSQL database name secret
echo -n "craftique" | gcloud secrets create craftique-postgres-db \
  --data-file=- \
  --replication-policy="automatic"
```

Verify secrets were created:
```bash
gcloud secrets list
```

### 4. Create GCP Service Account

```bash
# Create service account for External Secrets Operator
gcloud iam service-accounts create external-secrets-operator \
  --display-name="External Secrets Operator"

# Grant Secret Manager access
gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:external-secrets-operator@${PROJECT_ID}.iam.gserviceaccount.com" \
  --role="roles/secretmanager.secretAccessor"

# Create and download service account key
gcloud iam service-accounts keys create gcp-key.json \
  --iam-account=external-secrets-operator@${PROJECT_ID}.iam.gserviceaccount.com
```

⚠️ **IMPORTANT**: The `gcp-key.json` file contains sensitive credentials. Never commit it to Git!

### 5. Deploy External Secrets Operator

```bash
# Deploy the operator
kubectl apply -f infrastructure/external-secrets/external-secrets-operator.yaml

# Wait for it to be ready
kubectl wait --for=condition=available --timeout=120s \
  deployment/external-secrets -n external-secrets

# Verify
kubectl get pods -n external-secrets
```

### 6. Create Kubernetes Secret with GCP Service Account Key

```bash
# Create the secret in the external-secrets namespace
kubectl create secret generic gcp-secret-manager-key \
  -n external-secrets \
  --from-file=key.json=gcp-key.json

# Verify
kubectl get secret gcp-secret-manager-key -n external-secrets
```

### 7. Update and Deploy SecretStore

Edit `infrastructure/external-secrets/gcp-secretstore.yaml` and replace `YOUR_GCP_PROJECT_ID` with your actual project ID:

```yaml
spec:
  provider:
    gcpsm:
      projectID: "your-actual-project-id"  # Replace this!
```

Then apply it:
```bash
kubectl apply -f infrastructure/external-secrets/gcp-secretstore.yaml

# Verify the SecretStore is ready
kubectl get secretstore gcp-secret-manager -n default
kubectl describe secretstore gcp-secret-manager -n default
```

### 8. Deploy ExternalSecret

```bash
# Deploy the ExternalSecret
kubectl apply -f infrastructure/postgres/postgres-externalsecret.yaml

# Watch it sync (should create a Secret within 30 seconds)
kubectl get externalsecret postgres-credentials -w

# Verify the Kubernetes Secret was created
kubectl get secret postgres-credentials

# Check the secret data (base64 encoded)
kubectl get secret postgres-credentials -o yaml
```

### 9. Deploy Applications

```bash
# Deploy PostgreSQL
kubectl apply -f infrastructure/postgres/

# Deploy backend
kubectl apply -f apps/backend/

# Verify pods are running with secrets
kubectl describe statefulset postgres | grep -A 10 "Environment"
```

---

## Verification

### Check ExternalSecret Status
```bash
kubectl get externalsecret postgres-credentials
# Should show: READY, STATUS: SecretSynced
```

### Check Kubernetes Secret
```bash
kubectl get secret postgres-credentials -o jsonpath='{.data.POSTGRES_PASSWORD}' | base64 -d
# Should show your password from GCP
```

### Check Pod Environment
```bash
kubectl exec -it postgres-0 -- env | grep POSTGRES
```

---

## Secret Rotation

### Rotating a Secret

1. **Update the secret in GCP:**
```bash
echo -n "new-password-here" | gcloud secrets versions add craftique-postgres-password \
  --data-file=-
```

2. **Wait for ESO to sync** (default: 1 hour, or force refresh):
```bash
# Force immediate refresh by deleting and recreating ExternalSecret
kubectl delete externalsecret postgres-credentials
kubectl apply -f infrastructure/postgres/postgres-externalsecret.yaml
```

3. **Restart pods to use new secret:**
```bash
kubectl rollout restart statefulset postgres
kubectl rollout restart deployment craftique-backend
```

### Automated Rotation (Advanced)

Configure automatic rotation by updating the ExternalSecret:
```yaml
spec:
  refreshInterval: 5m  # Check for updates every 5 minutes
```

---

## Troubleshooting

### ExternalSecret not syncing
```bash
# Check ExternalSecret status
kubectl describe externalsecret postgres-credentials

# Check ESO operator logs
kubectl logs -n external-secrets deployment/external-secrets

# Common issues:
# 1. Wrong project ID in SecretStore
# 2. Service account doesn't have secretmanager.secretAccessor role
# 3. Secret names in GCP don't match remoteRef.key values
# 4. SecretStore not in READY state
```

### Check SecretStore connectivity
```bash
kubectl get secretstore gcp-secret-manager -o yaml
# Look for status.conditions
```

### Verify GCP permissions
```bash
# Test if service account can access secrets
gcloud secrets versions access latest --secret=craftique-postgres-password \
  --impersonate-service-account=external-secrets-operator@${PROJECT_ID}.iam.gserviceaccount.com
```

---

## Security Best Practices

### ✅ DO:
- Use separate GCP projects for dev/staging/prod
- Enable GCP audit logging for Secret Manager
- Use Workload Identity on GKE (eliminates service account keys)
- Rotate secrets every 90 days minimum
- Set `refreshInterval` to detect rotation
- Use least-privilege IAM roles
- Enable secret versioning in GCP

### ❌ DON'T:
- Commit `gcp-key.json` to Git (add to .gitignore!)
- Share service account keys
- Use overly permissive IAM roles
- Store secrets in ConfigMaps
- Hardcode secrets in manifests

---

## Upgrading to Workload Identity (GKE Only)

If you're using GKE, use Workload Identity instead of service account keys:

```bash
# Enable Workload Identity on cluster
gcloud container clusters update YOUR_CLUSTER \
  --workload-pool=${PROJECT_ID}.svc.id.goog

# Bind Kubernetes SA to GCP SA
gcloud iam service-accounts add-iam-policy-binding \
  external-secrets-operator@${PROJECT_ID}.iam.gserviceaccount.com \
  --role roles/iam.workloadIdentityUser \
  --member "serviceAccount:${PROJECT_ID}.svc.id.goog[external-secrets/external-secrets]"

# Annotate Kubernetes SA
kubectl annotate serviceaccount external-secrets \
  -n external-secrets \
  iam.gke.io/gcp-service-account=external-secrets-operator@${PROJECT_ID}.iam.gserviceaccount.com
```

Then update `gcp-secretstore.yaml` to use Workload Identity instead of key file.

---

## Adding More Secrets

To add additional secrets:

1. **Create in GCP:**
```bash
echo -n "my-api-key" | gcloud secrets create craftique-api-key --data-file=-
```

2. **Add to ExternalSecret:**
```yaml
data:
- secretKey: API_KEY
  remoteRef:
    key: craftique-api-key
```

3. **Reference in deployment:**
```yaml
env:
- name: API_KEY
  valueFrom:
    secretKeyRef:
      name: postgres-credentials  # or create a new ExternalSecret
      key: API_KEY
```

---

## Monitoring and Alerts

### View Secret Access Logs
```bash
# In GCP Console: Logging → Logs Explorer
# Filter: resource.type="secretmanager.googleapis.com/Secret"
```

### Monitor ESO metrics
```bash
kubectl port-forward -n external-secrets deployment/external-secrets 8080:8080
curl localhost:8080/metrics
```

---

## Cleanup (if needed)

```bash
# Delete Kubernetes resources
kubectl delete -f infrastructure/external-secrets/
kubectl delete -f infrastructure/postgres/postgres-externalsecret.yaml

# Delete GCP secrets
gcloud secrets delete craftique-postgres-password
gcloud secrets delete craftique-postgres-user
gcloud secrets delete craftique-postgres-db

# Delete service account
gcloud iam service-accounts delete external-secrets-operator@${PROJECT_ID}.iam.gserviceaccount.com
```

---

## Cost Breakdown

| Resource | Monthly Cost | Notes |
|----------|--------------|-------|
| Secret Manager (3 secrets) | $0 | Within free tier |
| Secret access operations | $0 | Within free tier |
| Secret versions | $0 | Within free tier |
| **TOTAL** | **$0** | ✅ Completely free |

**Free Tier Limits:**
- 10,000 secret versions: More than enough for this project
- 10,000 access operations/month: ~13 per hour sustained

---

## Additional Resources

- [External Secrets Operator Docs](https://external-secrets.io/)
- [GCP Secret Manager Docs](https://cloud.google.com/secret-manager/docs)
- [GCP Secret Manager Pricing](https://cloud.google.com/secret-manager/pricing)
- [ESO GCP Provider Guide](https://external-secrets.io/latest/provider/google-secrets-manager/)

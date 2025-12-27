# Quick Start: GCP Secret Manager with External Secrets

**5-minute setup for GCP Secret Manager integration**

## Prerequisites
- GCP account with $300 free credits
- `gcloud` CLI installed
- Kubernetes cluster running

---

## Step 1: Enable API & Create Secrets (2 min)

```bash
# Set project
export PROJECT_ID="your-gcp-project-id"
gcloud config set project $PROJECT_ID

# Enable API
gcloud services enable secretmanager.googleapis.com

# Create secrets
echo -n "$(openssl rand -base64 32)" | gcloud secrets create craftique-postgres-password --data-file=- --replication-policy="automatic"
echo -n "craftique" | gcloud secrets create craftique-postgres-user --data-file=- --replication-policy="automatic"
echo -n "craftique" | gcloud secrets create craftique-postgres-db --data-file=- --replication-policy="automatic"
```

## Step 2: Create Service Account (1 min)

```bash
# Create SA
gcloud iam service-accounts create external-secrets-operator

# Grant access
gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:external-secrets-operator@${PROJECT_ID}.iam.gserviceaccount.com" \
  --role="roles/secretmanager.secretAccessor"

# Create key
gcloud iam service-accounts keys create gcp-key.json \
  --iam-account=external-secrets-operator@${PROJECT_ID}.iam.gserviceaccount.com
```

⚠️ **Add `gcp-key.json` to `.gitignore` immediately!**

## Step 3: Deploy to Kubernetes (2 min)

```bash
# Deploy External Secrets Operator
kubectl apply -f infrastructure/external-secrets/external-secrets-operator.yaml
kubectl wait --for=condition=available --timeout=120s deployment/external-secrets -n external-secrets

# Create secret with GCP key
kubectl create secret generic gcp-secret-manager-key -n external-secrets --from-file=key.json=gcp-key.json

# Update SecretStore with your project ID
# Edit: infrastructure/external-secrets/gcp-secretstore.yaml
# Change: projectID: "YOUR_GCP_PROJECT_ID" → projectID: "your-actual-project-id"

# Apply SecretStore and ExternalSecret
kubectl apply -f infrastructure/external-secrets/gcp-secretstore.yaml
kubectl apply -f infrastructure/postgres/postgres-externalsecret.yaml

# Verify (wait ~30 seconds)
kubectl get externalsecret postgres-credentials
kubectl get secret postgres-credentials
```

## Verify It Works

```bash
# Check ExternalSecret status
kubectl get externalsecret postgres-credentials
# Should show: STATUS: SecretSynced

# Check secret content
kubectl get secret postgres-credentials -o jsonpath='{.data.POSTGRES_PASSWORD}' | base64 -d
# Should show the password from GCP
```

## Deploy Apps

```bash
git add .
git commit -m "feat: integrate GCP Secret Manager"
git push
# ArgoCD will sync automatically
```

---

## What Changed?

✅ **No plaintext passwords** - All in GCP Secret Manager  
✅ **Automatic sync** - ESO keeps Kubernetes secrets updated  
✅ **Audit trail** - GCP logs all secret access  
✅ **Free** - Well within GCP free tier ($0/month)

---

## Troubleshooting

**ExternalSecret not syncing?**
```bash
kubectl describe externalsecret postgres-credentials
kubectl logs -n external-secrets deployment/external-secrets
```

**Common fixes:**
- Wrong project ID in gcp-secretstore.yaml
- Secret names in GCP don't match (check: `gcloud secrets list`)
- Service account key not created properly

---

## Rotate Secrets

```bash
# Update in GCP
echo -n "new-password" | gcloud secrets versions add craftique-postgres-password --data-file=-

# Force refresh
kubectl delete externalsecret postgres-credentials
kubectl apply -f infrastructure/postgres/postgres-externalsecret.yaml

# Restart pods
kubectl rollout restart statefulset postgres
kubectl rollout restart deployment craftique-backend
```

---

## Cost: $0/month

Within GCP free tier:
- ✅ First 10,000 secret versions: FREE
- ✅ First 10,000 access operations/month: FREE

See [GCP-SECRETS-SETUP.md](GCP-SECRETS-SETUP.md) for complete documentation.

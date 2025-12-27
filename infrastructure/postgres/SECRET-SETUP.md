# Creating Kubernetes Secrets for PostgreSQL

This document explains how to create the required Kubernetes secret for PostgreSQL credentials.

## Manual Secret Creation

Create the `postgres-credentials` secret in your cluster:

```bash
# Create the secret with your PostgreSQL password
kubectl create secret generic postgres-credentials \
  --from-literal=POSTGRES_PASSWORD='your-secure-password-here' \
  --namespace=default

# Verify the secret was created
kubectl get secret postgres-credentials -n default
```

## Using a Different Password

If you need to update the password:

```bash
# Delete the existing secret
kubectl delete secret postgres-credentials -n default

# Create a new one with the updated password
kubectl create secret generic postgres-credentials \
  --from-literal=POSTGRES_PASSWORD='your-new-password' \
  --namespace=default
```

**Warning:** Changing the password after PostgreSQL is initialized requires:
1. Updating the secret
2. Restarting the PostgreSQL pod
3. Or manually changing the password inside PostgreSQL

## Using GCP Secret Manager (Recommended for Production)

For production, use External Secrets Operator to sync from GCP Secret Manager:

### 1. Create secret in GCP Secret Manager

```bash
# Create the secret in GCP
echo -n "your-secure-password" | gcloud secrets create postgres-password \
  --data-file=- \
  --project=craftique-482022

# Grant access to your GKE service account
gcloud secrets add-iam-policy-binding postgres-password \
  --member="serviceAccount:backend-sa@craftique-482022.iam.gserviceaccount.com" \
  --role="roles/secretmanager.secretAccessor" \
  --project=craftique-482022
```

### 2. Create ExternalSecret resource

```yaml
# infrastructure/postgres/postgres-external-secret.yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: postgres-credentials
  namespace: default
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: gcpsm-secret-store
    kind: SecretStore
  target:
    name: postgres-credentials
    creationPolicy: Owner
  data:
    - secretKey: POSTGRES_PASSWORD
      remoteRef:
        key: postgres-password
```

### 3. Apply the ExternalSecret

```bash
kubectl apply -f infrastructure/postgres/postgres-external-secret.yaml
```

The External Secrets Operator will automatically create the Kubernetes secret from GCP Secret Manager.

## Security Best Practices

1. **Never commit secrets to Git** - Always create them manually or via CI/CD
2. **Use strong passwords** - Minimum 16 characters, mix of characters
3. **Rotate regularly** - Change passwords periodically
4. **Limit access** - Use RBAC to restrict who can read secrets
5. **Use Secret Manager** - For production, sync from GCP Secret Manager

## Verifying the Setup

After creating the secret, verify the pods can access it:

```bash
# Check if the secret exists
kubectl get secret postgres-credentials -n default

# Check if PostgreSQL pod is running
kubectl get pods -l app=postgres

# Check PostgreSQL logs for any auth errors
kubectl logs postgres-0
```

## Troubleshooting

### Secret not found

```bash
# List all secrets in the namespace
kubectl get secrets -n default

# If missing, create it as shown above
```

### Permission denied

If using GCP Secret Manager:

```bash
# Verify service account has access
gcloud secrets get-iam-policy postgres-password --project=craftique-482022

# Add permission if missing
gcloud secrets add-iam-policy-binding postgres-password \
  --member="serviceAccount:YOUR-SA@craftique-482022.iam.gserviceaccount.com" \
  --role="roles/secretmanager.secretAccessor"
```

### Pod can't read secret

```bash
# Describe the pod to check for mount errors
kubectl describe pod postgres-0

# Check service account permissions
kubectl get serviceaccount default -o yaml
```

## Quick Start (For Development)

For quick local testing:

```bash
kubectl create secret generic postgres-credentials \
  --from-literal=POSTGRES_PASSWORD='craftique_dev_password' \
  --namespace=default
```

Then apply your manifests:

```bash
kubectl apply -f infrastructure/postgres/
```

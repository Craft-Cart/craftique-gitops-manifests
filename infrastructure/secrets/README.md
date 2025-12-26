# Secrets Management with External Secrets Operator

This directory contains the External Secrets configuration for secure secrets management in the Craftique platform.

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    GCP Secret Manager                            │
│  ┌──────────────────┐  ┌──────────────────┐  ┌───────────────┐ │
│  │ craftique-db-    │  │ craftique-jwt-   │  │ craftique-    │ │
│  │ password         │  │ secret           │  │ auth0-client  │ │
│  └────────┬─────────┘  └────────┬─────────┘  └───────┬───────┘ │
└───────────┼─────────────────────┼────────────────────┼─────────┘
            │                     │                    │
            ▼                     ▼                    ▼
┌─────────────────────────────────────────────────────────────────┐
│              External Secrets Operator (ESO)                     │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │              ClusterSecretStore                           │   │
│  │              (gcp-secret-manager)                         │   │
│  └──────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
            │                     │                    │
            ▼                     ▼                    ▼
┌─────────────────────────────────────────────────────────────────┐
│                    Kubernetes Secrets                            │
│  ┌──────────────────┐  ┌──────────────────┐                     │
│  │ craftique-       │  │ craftique-       │                     │
│  │ database-        │  │ backend-         │                     │
│  │ credentials      │  │ secrets          │                     │
│  └────────┬─────────┘  └────────┬─────────┘                     │
└───────────┼─────────────────────┼───────────────────────────────┘
            │                     │
            ▼                     ▼
┌─────────────────────────────────────────────────────────────────┐
│                    Application Pods                              │
│  ┌──────────────────┐  ┌──────────────────┐                     │
│  │    PostgreSQL    │  │     Backend      │                     │
│  │    StatefulSet   │  │    Deployment    │                     │
│  └──────────────────┘  └──────────────────┘                     │
└─────────────────────────────────────────────────────────────────┘
```

## Prerequisites

### 1. Install External Secrets Operator

```bash
# Add the External Secrets Helm repository
helm repo add external-secrets https://charts.external-secrets.io
helm repo update

# Install the operator
helm install external-secrets external-secrets/external-secrets \
  --namespace external-secrets \
  --create-namespace \
  --set installCRDs=true
```

### 2. Configure GCP Secret Manager Access

```bash
# Create a GCP Service Account
gcloud iam service-accounts create eso-secret-accessor \
  --display-name="External Secrets Operator"

# Grant Secret Accessor role
gcloud projects add-iam-policy-binding YOUR_PROJECT_ID \
  --member="serviceAccount:eso-secret-accessor@YOUR_PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/secretmanager.secretAccessor"

# Create and download key
gcloud iam service-accounts keys create sa-key.json \
  --iam-account=eso-secret-accessor@YOUR_PROJECT_ID.iam.gserviceaccount.com

# Store the key in Kubernetes
kubectl create secret generic gcp-sm-sa \
  --from-file=secret-access-credentials=./sa-key.json \
  --namespace=external-secrets

# Clean up local key file
rm sa-key.json
```

### 3. Create Secrets in GCP Secret Manager

```bash
# Database credentials
echo -n "your-secure-db-password" | gcloud secrets create craftique-db-password --data-file=-
echo -n "craftique" | gcloud secrets create craftique-db-username --data-file=-

# Application secrets
echo -n "your-jwt-secret-min-32-characters" | gcloud secrets create craftique-jwt-secret --data-file=-
echo -n "your-cookie-secret-min-32-chars" | gcloud secrets create craftique-cookie-secret --data-file=-

# Auth0 secrets
echo -n "your-auth0-client-secret" | gcloud secrets create craftique-auth0-client-secret --data-file=-

# Payment gateway secrets
echo -n "your-paymob-api-key" | gcloud secrets create craftique-paymob-api-key --data-file=-
echo -n "your-paymob-hmac-secret" | gcloud secrets create craftique-paymob-hmac-secret --data-file=-
```

## Files in this Directory

| File | Purpose |
|------|---------|
| `cluster-secret-store.yaml` | Defines the connection to GCP Secret Manager |
| `database-external-secret.yaml` | Pulls database credentials and creates K8s Secret |
| `backend-external-secret.yaml` | Pulls backend app secrets and creates K8s Secret |

## Secrets Created

After applying these manifests, the following Kubernetes Secrets will be created:

### `craftique-database-credentials`
| Key | Description |
|-----|-------------|
| `POSTGRES_PASSWORD` | Database password |
| `POSTGRES_USER` | Database username |
| `DATABASE_URL` | Full connection string |

### `craftique-backend-secrets`
| Key | Description |
|-----|-------------|
| `JWT_SECRET` | JWT signing key |
| `COOKIE_SECRET` | Cookie encryption key |
| `AUTH0_CLIENT_SECRET` | Auth0 OAuth secret |
| `PAYMOB_API_KEY` | Payment gateway API key |
| `PAYMOB_HMAC_SECRET` | Payment webhook HMAC secret |

## Verification

```bash
# Check if ExternalSecrets are syncing correctly
kubectl get externalsecrets -n default

# Check the created Kubernetes Secrets
kubectl get secrets -n default | grep craftique

# Verify secret contents (base64 encoded)
kubectl get secret craftique-database-credentials -o jsonpath='{.data}'
```

## Secret Rotation

Secrets are automatically synced every hour (`refreshInterval: 1h`). To force an immediate sync:

```bash
# Delete the K8s Secret to trigger recreation
kubectl delete secret craftique-database-credentials
kubectl delete secret craftique-backend-secrets

# The External Secrets Operator will recreate them within seconds
```

## Troubleshooting

```bash
# Check ESO operator logs
kubectl logs -n external-secrets -l app.kubernetes.io/name=external-secrets

# Check ExternalSecret status
kubectl describe externalsecret craftique-database-credentials

# Verify ClusterSecretStore connection
kubectl describe clustersecretstore gcp-secret-manager
```

## Security Best Practices

1. **Least Privilege**: The GCP Service Account only has `secretmanager.secretAccessor` role
2. **No Plaintext**: Secrets never appear in Git repositories
3. **Audit Trail**: GCP Secret Manager provides access logging
4. **Rotation**: Secrets can be rotated in GCP without redeploying applications
5. **Encryption**: Secrets are encrypted at rest in both GCP and etcd

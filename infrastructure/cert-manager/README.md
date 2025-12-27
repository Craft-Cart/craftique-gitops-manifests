# cert-manager Installation Guide

cert-manager automates TLS certificate provisioning and renewal for the Craftique application.

## Prerequisites

- Kubernetes cluster (GKE free tier compatible)
- kubectl configured
- Helm 3.x installed

## Installation

### 1. Install cert-manager using kubectl

```bash
# Install cert-manager CRDs
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.0/cert-manager.crds.yaml

# Create namespace
kubectl create namespace cert-manager

# Install cert-manager
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.0/cert-manager.yaml
```

### 2. Verify Installation

```bash
# Check cert-manager pods are running
kubectl get pods -n cert-manager

# Expected output:
# NAME                                       READY   STATUS    RESTARTS   AGE
# cert-manager-7d9f4c8f9d-xxxxx             1/1     Running   0          1m
# cert-manager-cainjector-5c7d9f9d-xxxxx    1/1     Running   0          1m
# cert-manager-webhook-5f7d9f9d-xxxxx       1/1     Running   0          1m
```

### 3. Apply ClusterIssuers

```bash
# Apply staging issuer (for testing)
kubectl apply -f infrastructure/cert-manager/letsencrypt-staging.yaml

# Apply production issuer (for production use)
kubectl apply -f infrastructure/cert-manager/letsencrypt-prod.yaml

# Verify issuers
kubectl get clusterissuer
```

### 4. Apply Updated Ingress

```bash
# The ingress will now automatically request a TLS certificate
kubectl apply -f networking/ingress.yaml

# Check certificate status
kubectl get certificate -n default
kubectl describe certificate craftique-tls-cert -n default
```

## Testing Certificate

### Using Staging First (Recommended)

To avoid Let's Encrypt rate limits, test with staging first:

1. Edit `networking/ingress.yaml`:
   ```yaml
   annotations:
     cert-manager.io/cluster-issuer: "letsencrypt-staging"  # Use staging
   ```

2. Apply and verify:
   ```bash
   kubectl apply -f networking/ingress.yaml
   
   # Wait for certificate (can take 1-2 minutes)
   kubectl wait --for=condition=ready certificate/craftique-tls-cert --timeout=300s
   
   # Check certificate
   kubectl get certificate
   ```

3. Test HTTPS access:
   ```bash
   # You'll get a browser warning (staging cert not trusted) - this is expected
   curl -k https://craftique.chickenkiller.com
   ```

4. Switch to production:
   ```yaml
   annotations:
     cert-manager.io/cluster-issuer: "letsencrypt-prod"  # Use production
   ```

## Troubleshooting

### Certificate Not Issuing

```bash
# Check certificate status
kubectl describe certificate craftique-tls-cert

# Check certificate request
kubectl get certificaterequest
kubectl describe certificaterequest <name>

# Check cert-manager logs
kubectl logs -n cert-manager deployment/cert-manager
```

### Common Issues

1. **DNS not pointing to ingress:**
   ```bash
   # Get ingress IP
   kubectl get ingress craftique-ingress
   
   # Verify DNS
   nslookup craftique.chickenkiller.com
   ```

2. **HTTP-01 challenge failing:**
   - Ensure port 80 is accessible
   - Check firewall rules
   - Verify ingress controller is running

3. **Rate limits (production only):**
   - Use staging for testing
   - Let's Encrypt has limits: 50 certs/week per domain

## Certificate Renewal

Certificates are automatically renewed by cert-manager 30 days before expiry. No manual intervention needed.

### Monitor Renewal

```bash
# Check certificate validity
kubectl get certificate craftique-tls-cert -o jsonpath='{.status.notAfter}'

# Watch for renewal events
kubectl get events --sort-by='.lastTimestamp' -n default | grep certificate
```

## Cost Implications

- **cert-manager:** Free and open source
- **Let's Encrypt:** Free certificates
- **GCP Cost:** None (uses existing ingress controller)

**Total additional cost:** $0

## Security Notes

- Certificates use 2048-bit RSA keys (secure)
- Auto-renewal prevents certificate expiry incidents
- Private keys stored securely in Kubernetes secrets
- HTTPS/TLS 1.2+ enforced via ingress annotations

## Alternative: Manual Certificate

If cert-manager is too complex for your setup:

```bash
# Create TLS secret manually (if you have your own cert)
kubectl create secret tls craftique-tls-cert \
  --cert=path/to/cert.pem \
  --key=path/to/key.pem
```

## References

- [cert-manager Documentation](https://cert-manager.io/docs/)
- [Let's Encrypt Rate Limits](https://letsencrypt.org/docs/rate-limits/)
- [GKE Ingress with TLS](https://cloud.google.com/kubernetes-engine/docs/how-to/ingress-multi-ssl)

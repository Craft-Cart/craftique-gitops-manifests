# Supply Chain Security Policies

This directory contains Kyverno policies for enforcing supply chain security in the Craftique platform.

## Overview

These policies implement the SLSA (Supply-chain Levels for Software Artifacts) framework requirements:

```
┌─────────────────────────────────────────────────────────────────────────┐
│                        CI/CD Pipeline                                    │
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────┐                 │
│  │   Build     │───▶│    Sign     │───▶│   Attest    │                 │
│  │   Image     │    │  (cosign)   │    │   (SLSA)    │                 │
│  └─────────────┘    └─────────────┘    └─────────────┘                 │
│                            │                  │                         │
│                            ▼                  ▼                         │
│                     ┌─────────────────────────────┐                    │
│                     │     Container Registry       │                    │
│                     │  (ghcr.io with signatures)  │                    │
│                     └──────────────┬──────────────┘                    │
└────────────────────────────────────┼────────────────────────────────────┘
                                     │
                                     ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                      Kubernetes Cluster                                  │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │                    Kyverno Admission Controller                  │   │
│  │  ┌───────────────┐ ┌───────────────┐ ┌───────────────────────┐ │   │
│  │  │ Verify Image  │ │ Verify SLSA   │ │ Require Image Digests │ │   │
│  │  │  Signatures   │ │  Provenance   │ │  (Block :latest)      │ │   │
│  │  └───────────────┘ └───────────────┘ └───────────────────────┘ │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                     │                                   │
│                                     ▼                                   │
│                          ✅ Allow / ❌ Deny                             │
└─────────────────────────────────────────────────────────────────────────┘
```

## Policies

| Policy | File | Action | Purpose |
|--------|------|--------|---------|
| Verify Image Signatures | `verify-image-signatures.yaml` | Enforce | Ensures images are signed with cosign |
| Verify SLSA Provenance | `verify-slsa-provenance.yaml` | Audit | Checks for SLSA provenance attestations |
| Require Image Digests | `require-image-digests.yaml` | Enforce | Blocks mutable tags like `:latest` |

## Prerequisites

### Install Kyverno

```bash
# Add Helm repo
helm repo add kyverno https://kyverno.github.io/kyverno/
helm repo update

# Install Kyverno
helm install kyverno kyverno/kyverno \
  --namespace kyverno \
  --create-namespace \
  --set replicaCount=3 \
  --set webhookTimeoutSeconds=30
```

### Verify Installation

```bash
kubectl get pods -n kyverno
kubectl get clusterpolicies
```

## How It Works

### 1. Image Signature Verification

When a Pod is created, Kyverno intercepts the request and:
1. Extracts the image reference from the Pod spec
2. Queries Sigstore Rekor transparency log for the signature
3. Verifies the signature was created by GitHub Actions (OIDC issuer check)
4. Allows or denies the Pod creation

```bash
# Manual verification command
cosign verify \
  --certificate-identity-regexp="https://github.com/Craft-Cart/YOUR_REPO/*" \
  --certificate-oidc-issuer="https://token.actions.githubusercontent.com" \
  us-central1-docker.pkg.dev/your-project/craftique/backend@sha256:abc123...
```

### 2. SLSA Provenance Verification

The provenance attestation contains:
- Source repository URL
- Git commit SHA
- Build workflow reference
- Builder identity

Kyverno verifies:
- Attestation signature is valid
- Attestation was created by GitHub Actions
- Build was from main/master branch

### 3. Digest Requirement

Forces use of immutable image references:
- ❌ `us-central1-docker.pkg.dev/project/repo/backend:latest` - Blocked
- ❌ `us-central1-docker.pkg.dev/project/repo/backend:v1.0.0` - Blocked
- ✅ `us-central1-docker.pkg.dev/project/repo/backend@sha256:abc123...` - Allowed

## Testing Policies

### Test with a signed image (should pass)

```bash
kubectl run test-signed \
  --image=us-central1-docker.pkg.dev/your-project/craftique/backend@sha256:your-signed-digest \
  --dry-run=server
```

### Test with unsigned image (should fail)

```bash
kubectl run test-unsigned \
  --image=nginx:latest \
  --dry-run=server
# Expected: Error from server (Forbidden)
```

### Check policy reports

```bash
# View policy violations
kubectl get policyreport -A

# Detailed report
kubectl describe policyreport -n default
```

## Troubleshooting

### Policy not enforcing

```bash
# Check policy status
kubectl get clusterpolicy verify-image-signatures -o yaml

# Check Kyverno logs
kubectl logs -n kyverno -l app.kubernetes.io/name=kyverno --tail=100
```

### Signature verification failing

```bash
# Verify image has signature in Rekor
rekor-cli search --email your-github-actions-email

# Check cosign tree
cosign tree us-central1-docker.pkg.dev/your-project/craftique/backend@sha256:abc123
```

### Timeout issues

If verification takes too long:
1. Increase `webhookTimeoutSeconds` in policy
2. Check network connectivity to `rekor.sigstore.dev`
3. Consider caching with Kyverno's image verification cache

## Security Considerations

1. **Fail Closed**: Policies use `failurePolicy: Fail` to deny pods if verification fails
2. **Transparency Log**: All signatures are recorded in Sigstore Rekor for auditability
3. **OIDC Identity**: Keyless signing ties signatures to GitHub Actions workflow identity
4. **Immutability**: Digest pinning prevents tag manipulation attacks

## Related Resources

- [Sigstore Documentation](https://docs.sigstore.dev/)
- [Kyverno Image Verification](https://kyverno.io/docs/writing-policies/verify-images/)
- [SLSA Framework](https://slsa.dev/)
- [GitHub Artifact Attestations](https://docs.github.com/en/actions/security-guides/using-artifact-attestations-to-establish-provenance-for-builds)

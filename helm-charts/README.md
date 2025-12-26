# Craftique Helm Charts

Security-hardened Helm charts for deploying Craftique e-commerce platform components.

## Overview

This directory contains production-ready Helm charts with built-in security best practices:

- **Security Contexts**: Non-root execution, read-only filesystems, dropped capabilities
- **Network Policies**: Default-deny with explicit allow rules
- **Resource Management**: CPU/memory limits, autoscaling, PodDisruptionBudgets
- **Supply Chain Security**: Digest-pinned images, signed images, SLSA provenance
- **Asset Tagging**: Comprehensive Kubernetes and governance labels
- **High Availability**: Multi-replica deployments with pod anti-affinity

## Charts

### 1. craftique-backend
REST API backend service with PostgreSQL integration.

**Features:**
- External Secrets integration for secure credential management
- Network policies for database and external API access
- Health probes for liveness and readiness
- HorizontalPodAutoscaler support
- PodDisruptionBudget for high availability

### 2. craftique-frontend
Next.js web application frontend.

**Features:**
- Public-facing web interface
- Network policies for backend API communication
- CDN-ready configuration
- Static asset optimization

## Security Features

### Container Security
All charts enforce strict container security:

```yaml
securityContext:
  allowPrivilegeEscalation: false
  readOnlyRootFilesystem: true
  runAsNonRoot: true
  runAsUser: 1001
  capabilities:
    drop:
      - ALL
```

### Network Isolation
Default-deny network policies with explicit allow rules:

- Backend ↔ Database communication
- Frontend ↔ Backend API communication
- Backend → External APIs (Auth0, Paymob)
- All → DNS resolution
- Ingress Controller → Frontend/Backend

### Supply Chain Security
Images must be:
- Signed with cosign (keyless via Sigstore)
- Digest-pinned (no mutable tags)
- SLSA Level 3 provenance attestations
- Scanned for vulnerabilities and license compliance

### Governance Labels
All resources include comprehensive labels:

```yaml
labels:
  # Standard Kubernetes labels
  app.kubernetes.io/name: craftique
  app.kubernetes.io/component: backend|frontend
  app.kubernetes.io/part-of: craftique-ecommerce
  
  # Governance labels
  craftique.io/owner: platform-team
  craftique.io/environment: production
  craftique.io/cost-center: eng-backend
  craftique.io/criticality: critical
  craftique.io/monitoring: enabled
```

## Installation

### Prerequisites

1. **Kubernetes cluster** (1.24+)
2. **Helm** (3.10+)
3. **External Secrets Operator** (for secret management)
4. **Kyverno** (for policy enforcement)
5. **GCP Artifact Registry** credentials

### Install Backend

```bash
# Add custom values
cat > backend-values.yaml <<EOF
image:
  tag: "@sha256:abc123..."  # Replace with actual digest

governanceLabels:
  craftique.io/environment: production
  craftique.io/owner: platform-team

resources:
  requests:
    memory: "256Mi"
    cpu: "200m"
  limits:
    memory: "512Mi"
    cpu: "500m"

autoscaling:
  enabled: true
  minReplicas: 3
  maxReplicas: 10
EOF

# Install chart
helm install craftique-backend ./craftique-backend \
  --namespace default \
  --values backend-values.yaml

# Verify deployment
helm status craftique-backend
kubectl get pods -l app.kubernetes.io/name=craftique,app.kubernetes.io/component=backend
```

### Install Frontend

```bash
# Custom values
cat > frontend-values.yaml <<EOF
image:
  tag: "@sha256:def456..."

env:
  NEXT_PUBLIC_API_BASE_URL: "https://api.craftique.io/v1"

autoscaling:
  enabled: true
  minReplicas: 3
EOF

# Install chart
helm install craftique-frontend ./craftique-frontend \
  --namespace default \
  --values frontend-values.yaml
```

## Configuration

### Environment-Specific Values

**Development:**
```yaml
# dev-values.yaml
replicaCount: 1
autoscaling:
  enabled: false
governanceLabels:
  craftique.io/environment: development
  craftique.io/auto-shutdown: enabled
resources:
  requests:
    memory: "64Mi"
    cpu: "50m"
networkPolicy:
  enabled: false  # For easier debugging
```

**Staging:**
```yaml
# staging-values.yaml
replicaCount: 2
autoscaling:
  enabled: true
  minReplicas: 2
  maxReplicas: 5
governanceLabels:
  craftique.io/environment: staging
  craftique.io/criticality: medium
```

**Production:**
```yaml
# prod-values.yaml
replicaCount: 3
autoscaling:
  enabled: true
  minReplicas: 3
  maxReplicas: 20
governanceLabels:
  craftique.io/environment: production
  craftique.io/criticality: critical
podDisruptionBudget:
  minAvailable: 2  # Higher availability
```

### Custom Security Context

Override security settings (not recommended):

```yaml
securityContext:
  allowPrivilegeEscalation: false
  readOnlyRootFilesystem: false  # If app needs writable filesystem
  runAsUser: 2000  # Custom UID
```

### Network Policy Customization

Add additional egress rules:

```yaml
networkPolicy:
  egress:
    # Default rules (DNS, database, etc.)
    - to:
        - namespaceSelector: {}
      ports:
        - protocol: TCP
          port: 443
    # Custom: Allow Redis cache
    - to:
        - podSelector:
            matchLabels:
              app: redis
      ports:
        - protocol: TCP
          port: 6379
```

## Validation

### Template Validation
```bash
# Dry-run to check rendered templates
helm install --dry-run --debug craftique-backend ./craftique-backend

# Template output
helm template craftique-backend ./craftique-backend > rendered.yaml

# Validate with kubectl
kubectl apply --dry-run=server -f rendered.yaml
```

### Security Validation
```bash
# Check security contexts
helm template craftique-backend ./craftique-backend | \
  grep -A 10 "securityContext:"

# Verify network policies
helm template craftique-backend ./craftique-backend | \
  grep -A 20 "kind: NetworkPolicy"

# Check resource limits
helm template craftique-backend ./craftique-backend | \
  grep -A 10 "resources:"
```

### Label Validation
```bash
# Verify all required labels present
helm template craftique-backend ./craftique-backend | \
  yq '.metadata.labels' | grep -E 'app.kubernetes.io|craftique.io'
```

## Upgrade Strategy

### Rolling Update
```bash
# Update image digest
helm upgrade craftique-backend ./craftique-backend \
  --set image.tag="@sha256:newdigest123" \
  --namespace default

# Monitor rollout
kubectl rollout status deployment/craftique-backend

# Rollback if needed
helm rollback craftique-backend
```

### Blue-Green Deployment
```bash
# Install new version alongside existing
helm install craftique-backend-v2 ./craftique-backend \
  --set image.tag="@sha256:newversion" \
  --set fullnameOverride=craftique-backend-v2

# Test new version
kubectl port-forward svc/craftique-backend-v2 8000:8000

# Switch traffic (update Ingress)
kubectl patch ingress craftique-ingress -p '...'

# Delete old version
helm uninstall craftique-backend
```

## Monitoring

### Prometheus Integration
```yaml
monitoring:
  enabled: true
  serviceMonitor:
    enabled: true
    interval: 30s
    path: /metrics
```

### Metrics Endpoints
- Backend: `http://backend:8000/metrics`
- Frontend: `http://frontend:3000/metrics`

### Grafana Dashboards
Import dashboard for Helm-deployed apps:
- Deployment status
- Resource usage by cost-center
- Network policy compliance
- Security context violations

## Troubleshooting

### Pod Failing to Start
```bash
# Check pod events
kubectl describe pod <pod-name>

# Check security context issues
kubectl logs <pod-name>
# Look for: "permission denied", "read-only file system"

# Temporary: Disable read-only filesystem
helm upgrade craftique-backend ./craftique-backend \
  --set securityContext.readOnlyRootFilesystem=false
```

### Network Policy Blocking Traffic
```bash
# Temporarily disable network policy
helm upgrade craftique-backend ./craftique-backend \
  --set networkPolicy.enabled=false

# Check network policy rules
kubectl describe networkpolicy craftique-backend

# Test connectivity
kubectl run test-pod --rm -it --image=busybox -- sh
$ wget -O- http://craftique-backend:8000/health
```

### Resource Quota Exceeded
```bash
# Check current resource usage
kubectl describe resourcequota

# Reduce resource requests
helm upgrade craftique-backend ./craftique-backend \
  --set resources.requests.memory=64Mi \
  --set resources.requests.cpu=50m
```

## Best Practices

### DO's ✅
- **Always use digest-pinned images** (`@sha256:...`)
- **Set resource limits** for predictable scheduling
- **Enable network policies** in production
- **Use PodDisruptionBudgets** for high availability
- **Apply governance labels** for cost tracking
- **Test in staging** before production deployment
- **Use HPA** for auto-scaling workloads
- **Version your values files** in Git

### DON'Ts ❌
- **Don't use mutable tags** like `:latest`
- **Don't disable security contexts** in production
- **Don't run as root** (always `runAsNonRoot: true`)
- **Don't skip health probes** (they're critical for zero-downtime)
- **Don't ignore resource limits** (causes unpredictable behavior)
- **Don't commit secrets** to values files (use External Secrets)
- **Don't disable network policies** without security review

## Compliance

These charts implement:

- **CIS Kubernetes Benchmark**: Non-root, no privilege escalation, capabilities dropped
- **NIST 800-190**: Read-only filesystems, minimal attack surface
- **PCI-DSS**: Network segmentation, encryption in transit, access controls
- **FinOps**: Resource limits, cost-center labels, auto-shutdown tags

## References

- [Helm Best Practices](https://helm.sh/docs/chart_best_practices/)
- [Kubernetes Security Best Practices](https://kubernetes.io/docs/concepts/security/pod-security-standards/)
- [CIS Kubernetes Benchmark](https://www.cisecurity.org/benchmark/kubernetes)
- [NIST 800-190](https://nvlpubs.nist.gov/nistpubs/SpecialPublications/NIST.SP.800-190.pdf)

---

**Maintained by:** Platform Team  
**Last Updated:** 2025-12-26  
**Chart Version:** 1.0.0

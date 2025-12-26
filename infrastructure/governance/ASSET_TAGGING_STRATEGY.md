# Kubernetes Asset Tagging Strategy

## Overview

This document defines the standardized labeling and annotation strategy for all Kubernetes resources in the Craftique platform. Consistent tagging enables cost tracking, ownership mapping, environment segmentation, and automated governance.

## Label Taxonomy

All Kubernetes resources MUST include the following labels according to the [Kubernetes Recommended Labels](https://kubernetes.io/docs/concepts/overview/working-with-objects/common-labels/) specification.

### Required Labels

#### Application Identity Labels
| Label | Description | Example | Mutability |
|-------|-------------|---------|------------|
| `app.kubernetes.io/name` | Application name | `craftique` | Immutable |
| `app.kubernetes.io/component` | Component within architecture | `backend`, `frontend`, `database`, `cache` | Immutable |
| `app.kubernetes.io/part-of` | Higher-level application group | `craftique-ecommerce` | Immutable |
| `app.kubernetes.io/managed-by` | Tool managing the resource | `argocd`, `helm`, `kubectl` | Immutable |
| `app.kubernetes.io/version` | Application version | `v1.2.3`, `1.0.0` | Mutable |
| `app.kubernetes.io/instance` | Unique instance identifier | `craftique-prod`, `craftique-staging` | Immutable |

#### Governance Labels
| Label | Description | Example | Purpose |
|-------|-------------|---------|---------|
| `craftique.io/owner` | Team/individual responsible | `platform-team`, `backend-team`, `devops` | Accountability |
| `craftique.io/environment` | Deployment environment | `production`, `staging`, `development` | Cost allocation |
| `craftique.io/cost-center` | Financial cost center | `eng-platform`, `product-alpha`, `cc-9901` | Billing/chargeback |
| `craftique.io/criticality` | Business criticality level | `critical`, `high`, `medium`, `low` | SLA/priority |
| `craftique.io/data-classification` | Data sensitivity level | `public`, `internal`, `confidential`, `restricted` | Compliance |
| `craftique.io/compliance` | Compliance requirements | `pci-dss`, `gdpr`, `hipaa`, `sox` | Audit trail |

#### Operational Labels
| Label | Description | Example | Purpose |
|-------|-------------|---------|---------|
| `craftique.io/backup-policy` | Backup retention policy | `daily`, `weekly`, `never` | Disaster recovery |
| `craftique.io/monitoring` | Monitoring configuration | `enabled`, `disabled` | Observability |
| `craftique.io/auto-shutdown` | Auto-shutdown for cost savings | `enabled`, `disabled` | FinOps |
| `craftique.io/public-facing` | Exposed to internet | `true`, `false` | Security posture |

### Optional Labels
| Label | Description | Example |
|-------|-------------|---------|
| `craftique.io/contact` | Technical contact | `backend-oncall@craftique.io` |
| `craftique.io/jira-project` | Associated JIRA project | `CRAFT-123` |
| `craftique.io/repository` | Source code repository | `github.com/org/craftique` |

---

## Annotations

Annotations provide non-identifying metadata and operational context.

### Recommended Annotations
| Annotation | Description | Example |
|------------|-------------|---------|
| `craftique.io/description` | Human-readable description | `Backend API service for Craftique e-commerce` |
| `craftique.io/documentation` | Link to documentation | `https://docs.craftique.io/backend` |
| `craftique.io/runbook` | Operational runbook URL | `https://runbooks.craftique.io/backend-incidents` |
| `craftique.io/sla` | Service Level Agreement | `99.9% uptime, <200ms p95 latency` |
| `craftique.io/change-ticket` | Change management ticket | `CHG-2025-001234` |
| `craftique.io/deployed-by` | User/system that deployed | `argocd-controller`, `john.doe@craftique.io` |
| `craftique.io/deployment-date` | ISO 8601 deployment timestamp | `2025-12-26T10:30:00Z` |

### Supply Chain Security Annotations (Already Implemented)
| Annotation | Description | Example |
|------------|-------------|---------|
| `supply-chain.craftique.io/signed` | Image signature status | `true` |
| `supply-chain.craftique.io/signing-method` | Signing mechanism | `cosign-keyless` |
| `supply-chain.craftique.io/provenance` | Build provenance | `slsa-github-actions` |

---

## Labeling Standards by Resource Type

### Deployments & StatefulSets
```yaml
metadata:
  labels:
    # Standard Kubernetes labels
    app.kubernetes.io/name: craftique
    app.kubernetes.io/component: backend
    app.kubernetes.io/part-of: craftique-ecommerce
    app.kubernetes.io/managed-by: argocd
    app.kubernetes.io/version: "1.2.3"
    app.kubernetes.io/instance: craftique-prod
    
    # Governance labels
    craftique.io/owner: platform-team
    craftique.io/environment: production
    craftique.io/cost-center: eng-platform
    craftique.io/criticality: critical
    craftique.io/data-classification: internal
    craftique.io/compliance: pci-dss
    
    # Operational labels
    craftique.io/backup-policy: daily
    craftique.io/monitoring: enabled
    craftique.io/public-facing: "true"
```

### Services
```yaml
metadata:
  labels:
    app.kubernetes.io/name: craftique
    app.kubernetes.io/component: backend
    app.kubernetes.io/part-of: craftique-ecommerce
    craftique.io/owner: platform-team
    craftique.io/environment: production
    craftique.io/cost-center: eng-platform
```

### ConfigMaps & Secrets
```yaml
metadata:
  labels:
    app.kubernetes.io/name: craftique
    app.kubernetes.io/component: database
    app.kubernetes.io/managed-by: external-secrets-operator
    craftique.io/owner: platform-team
    craftique.io/environment: production
    craftique.io/data-classification: confidential
```

### PersistentVolumeClaims
```yaml
metadata:
  labels:
    app.kubernetes.io/name: craftique
    app.kubernetes.io/component: database
    craftique.io/backup-policy: daily
    craftique.io/data-classification: confidential
    craftique.io/cost-center: eng-platform
```

### Namespaces
```yaml
metadata:
  labels:
    craftique.io/environment: production
    craftique.io/cost-center: eng-platform
    craftique.io/owner: platform-team
    craftique.io/monitoring: enabled
```

---

## Label Values by Environment

### Production Environment
```yaml
craftique.io/environment: production
craftique.io/criticality: critical
craftique.io/backup-policy: daily
craftique.io/monitoring: enabled
craftique.io/auto-shutdown: disabled
```

### Staging Environment
```yaml
craftique.io/environment: staging
craftique.io/criticality: medium
craftique.io/backup-policy: weekly
craftique.io/monitoring: enabled
craftique.io/auto-shutdown: enabled  # Shutdown outside business hours
```

### Development Environment
```yaml
craftique.io/environment: development
craftique.io/criticality: low
craftique.io/backup-policy: never
craftique.io/monitoring: disabled
craftique.io/auto-shutdown: enabled  # Aggressive shutdown
```

---

## Cost Allocation Strategy

### Cost Center Mapping
| Cost Center | Team/Project | Resources |
|-------------|--------------|-----------|
| `eng-platform` | Platform Engineering | Core infrastructure, databases, monitoring |
| `eng-backend` | Backend Team | Backend API services |
| `eng-frontend` | Frontend Team | Frontend web application |
| `product-alpha` | Product Alpha | Feature-specific resources |
| `shared-services` | Shared Services | Ingress, service mesh, logging |

### Cost Tracking Queries

**Total cost by environment:**
```bash
kubectl get pods -A -L craftique.io/environment
kubectl get svc -A -L craftique.io/environment
kubectl get pvc -A -L craftique.io/environment
```

**Total cost by cost center:**
```bash
kubectl get all -A -L craftique.io/cost-center=eng-platform
```

**Total cost by owner:**
```bash
kubectl get all -A -L craftique.io/owner=backend-team
```

**Public-facing resources (higher security scrutiny):**
```bash
kubectl get all -A -L craftique.io/public-facing=true
```

---

## Compliance & Audit

### Data Classification Levels
| Level | Description | Example Resources | Controls Required |
|-------|-------------|-------------------|-------------------|
| `public` | Publicly available data | Frontend assets, public docs | Minimal |
| `internal` | Internal business data | Application logs, metrics | Access control |
| `confidential` | Sensitive business data | User data, payment info | Encryption, access logs |
| `restricted` | Highly sensitive data | PCI data, PHI, PII | Encryption, audit logs, DLP |

### Compliance Frameworks
| Framework | Label Value | Resources | Requirements |
|-----------|-------------|-----------|--------------|
| `pci-dss` | `pci-dss` | Payment processing | Network segmentation, encryption, logging |
| `gdpr` | `gdpr` | EU user data | Data residency, retention policies, deletion |
| `sox` | `sox` | Financial data | Audit trails, change management |
| `hipaa` | `hipaa` | Healthcare data | Encryption, access controls, audit logs |

---

## Kyverno Policy Enforcement

The following Kyverno policies enforce labeling standards:

### Required Labels Policy
```yaml
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: require-labels
spec:
  validationFailureAction: Enforce
  rules:
    - name: require-app-labels
      match:
        any:
          - resources:
              kinds:
                - Deployment
                - StatefulSet
                - Service
      validate:
        message: "Required labels missing: app.kubernetes.io/name, app.kubernetes.io/component, craftique.io/owner, craftique.io/environment"
        pattern:
          metadata:
            labels:
              app.kubernetes.io/name: "?*"
              app.kubernetes.io/component: "?*"
              craftique.io/owner: "?*"
              craftique.io/environment: "?*"
```

### Valid Environment Values Policy
```yaml
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: validate-environment-label
spec:
  validationFailureAction: Enforce
  rules:
    - name: check-environment
      match:
        any:
          - resources:
              kinds:
                - Deployment
                - StatefulSet
      validate:
        message: "craftique.io/environment must be one of: production, staging, development"
        pattern:
          metadata:
            labels:
              craftique.io/environment: "production | staging | development"
```

---

## Best Practices

### DO's ✅
- **Always include required labels** on all resources
- **Use consistent values** across resources (e.g., `production` not `prod`)
- **Update version labels** during deployments
- **Document custom labels** in this strategy
- **Automate label application** via CI/CD or GitOps
- **Propagate labels to pods** via Deployment/StatefulSet templates
- **Use labels for querying**, not annotations

### DON'Ts ❌
- **Don't use spaces** in label values (use hyphens: `backend-team` not `backend team`)
- **Don't exceed 63 characters** for label values
- **Don't use uppercase** letters (use lowercase with hyphens)
- **Don't put PII** in labels (they're indexed and searchable)
- **Don't change immutable labels** after creation
- **Don't use labels for large data** (use annotations instead)

---

## Migration Strategy

### Phase 1: Add Labels to New Resources
- All new manifests MUST include required labels
- CI/CD pipelines validate labels before deployment
- ArgoCD health checks verify label presence

### Phase 2: Update Existing Resources
- Run label migration script on existing resources
- Update GitOps manifests with complete label sets
- Force sync via ArgoCD to apply labels

### Phase 3: Enforce via Policy
- Deploy Kyverno policies in Audit mode (warning only)
- Review policy reports and fix violations
- Switch policies to Enforce mode

### Phase 4: Integrate with Monitoring
- Configure Prometheus to scrape labels
- Build Grafana dashboards by environment/owner/cost-center
- Set up cost allocation reports

---

## Label Migration Script

```bash
#!/bin/bash
# migrate-labels.sh - Adds standard labels to existing resources

NAMESPACE=${1:-default}
ENVIRONMENT=${2:-production}
OWNER=${3:-platform-team}
COST_CENTER=${4:-eng-platform}

echo "Migrating labels in namespace: $NAMESPACE"

# Label Deployments
kubectl label deployments -n $NAMESPACE \
  app.kubernetes.io/part-of=craftique-ecommerce \
  app.kubernetes.io/managed-by=argocd \
  craftique.io/owner=$OWNER \
  craftique.io/environment=$ENVIRONMENT \
  craftique.io/cost-center=$COST_CENTER \
  craftique.io/criticality=critical \
  craftique.io/monitoring=enabled \
  --overwrite

# Label Services
kubectl label services -n $NAMESPACE \
  app.kubernetes.io/part-of=craftique-ecommerce \
  craftique.io/owner=$OWNER \
  craftique.io/environment=$ENVIRONMENT \
  craftique.io/cost-center=$COST_CENTER \
  --overwrite

# Label ConfigMaps
kubectl label configmaps -n $NAMESPACE \
  app.kubernetes.io/part-of=craftique-ecommerce \
  craftique.io/owner=$OWNER \
  craftique.io/environment=$ENVIRONMENT \
  --overwrite

echo "Migration complete!"
```

---

## Validation

### Check Label Coverage
```bash
# Find resources missing required labels
kubectl get all -A -o json | jq -r '
  .items[] |
  select(.metadata.labels["app.kubernetes.io/name"] == null or
         .metadata.labels["craftique.io/owner"] == null or
         .metadata.labels["craftique.io/environment"] == null) |
  "\(.kind)/\(.metadata.name) in \(.metadata.namespace)"
'
```

### Generate Cost Report
```bash
# List all resources by cost center
for cc in eng-platform eng-backend eng-frontend; do
  echo "=== Cost Center: $cc ==="
  kubectl get all -A -l craftique.io/cost-center=$cc
done
```

### Audit Compliance Labels
```bash
# Find PCI-DSS resources
kubectl get all -A -l craftique.io/compliance=pci-dss

# Find confidential data resources
kubectl get all -A -l craftique.io/data-classification=confidential
```

---

## Integration with Cloud Providers

### GCP Resource Tagging
Map Kubernetes labels to GCP resource labels for unified cost tracking:

```yaml
# In GKE cluster configuration
metadata:
  labels:
    environment: production
    cost-center: eng-platform
    owner: platform-team
    managed-by: terraform
```

### AWS Resource Tagging
Map to AWS tags for cost allocation:

```yaml
# In EKS cluster tags
Tags:
  Environment: production
  CostCenter: eng-platform
  Owner: platform-team
  ManagedBy: terraform
```

---

## References

- [Kubernetes Recommended Labels](https://kubernetes.io/docs/concepts/overview/working-with-objects/common-labels/)
- [Kubernetes Well-Known Labels](https://kubernetes.io/docs/reference/labels-annotations-taints/)
- [FinOps Foundation Tagging Best Practices](https://www.finops.org/framework/capabilities/tagging-labeling/)
- [CIS Kubernetes Benchmark - Asset Management](https://www.cisecurity.org/benchmark/kubernetes)
- [NIST 800-53 CM-8 - Information System Component Inventory](https://nvlpubs.nist.gov/nistpubs/SpecialPublications/NIST.SP.800-53r5.pdf)

---

**Version:** 1.0.0  
**Last Updated:** 2025-12-26  
**Owner:** Platform Team  
**Status:** Active

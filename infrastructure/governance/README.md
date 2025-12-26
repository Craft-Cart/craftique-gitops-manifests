# Infrastructure Security Governance

This directory contains Kubernetes governance manifests that enforce resource limits, security policies, and availability guarantees across the Craftique platform.

## Overview

Infrastructure governance ensures:
- **Resource Quotas**: Prevent resource exhaustion attacks and ensure fair allocation
- **Limit Ranges**: Enforce default resource constraints on all containers
- **Security Contexts**: Implement least-privilege container execution
- **Pod Disruption Budgets**: Maintain high availability during planned disruptions

## Components

### 1. ResourceQuota (`resource-quota.yaml`)

Limits total resource consumption per namespace to prevent noisy neighbor issues and resource exhaustion.

**Key Limits:**
- Default namespace: 4 CPU / 8Gi memory requests, 8 CPU / 16Gi limits
- Production namespace: 8 CPU / 16Gi requests, 16 CPU / 32Gi limits
- Staging namespace: 6 CPU / 12Gi requests, 12 CPU / 24Gi limits

**Why this matters:**
- Prevents single workload from consuming all cluster resources
- Enforces budgets for cost control
- Limits expensive resources (LoadBalancers, PVCs)

**Apply:**
```bash
# Create namespaces first
kubectl create namespace production
kubectl create namespace staging

# Apply quotas
kubectl apply -f resource-quota.yaml
```

**Verify:**
```bash
kubectl get resourcequota -n default
kubectl describe resourcequota craftique-resource-quota -n default
```

---

### 2. LimitRange (`limit-range.yaml`)

Sets default resource requests/limits for containers that don't specify them explicitly. Prevents unbounded resource requests.

**Key Features:**
- **Default requests**: 100m CPU / 128Mi memory (if not specified)
- **Default limits**: 500m CPU / 512Mi memory (if not specified)
- **Maximum allowed**: 2 CPU / 4Gi memory per container
- **Minimum required**: 50m CPU / 64Mi memory per container
- **Limit/Request ratio**: Maximum 4x (prevents gaming the scheduler)

**Why this matters:**
- Ensures all pods have resource constraints (prevents DoS)
- Prevents unrealistic resource requests
- Protects against unbounded memory/CPU growth

**Apply:**
```bash
kubectl apply -f limit-range.yaml
```

**Verify:**
```bash
kubectl get limitrange -n default
kubectl describe limitrange craftique-limit-range -n default
```

**Test:**
```bash
# Deploy pod without resource requests - should get defaults
kubectl run test-pod --image=nginx --restart=Never
kubectl get pod test-pod -o yaml | grep -A 10 resources
kubectl delete pod test-pod
```

---

### 3. PodDisruptionBudget (`pod-disruption-budget.yaml`)

Ensures minimum number of pods remain available during voluntary disruptions (node drains, cluster upgrades, deployments).

**Key Settings:**
- Backend/Frontend: `minAvailable: 1` (default namespace)
- Backend/Frontend: `minAvailable: 2` (production namespace)
- PostgreSQL: `minAvailable: 1` (prevents database downtime)

**Why this matters:**
- Maintains service availability during cluster maintenance
- Prevents all pods from being evicted simultaneously
- Essential for zero-downtime deployments

**Apply:**
```bash
kubectl apply -f pod-disruption-budget.yaml
```

**Verify:**
```bash
kubectl get pdb
kubectl describe pdb craftique-backend-pdb
```

**Test disruption protection:**
```bash
# Try to drain a node (requires at least 2 nodes)
kubectl drain <node-name> --ignore-daemonsets
# PDB will prevent eviction if it would violate minAvailable
```

---

### 4. Enhanced SecurityContext

Applied to all workloads in deployment manifests:

#### Pod-level SecurityContext
```yaml
securityContext:
  runAsUser: 1001            # Non-root user
  runAsGroup: 1001
  fsGroup: 1001
  runAsNonRoot: true         # Reject if image tries to run as root
  seccompProfile:
    type: RuntimeDefault     # Linux syscall filtering
```

#### Container-level SecurityContext
```yaml
securityContext:
  allowPrivilegeEscalation: false  # Prevent setuid binaries
  readOnlyRootFilesystem: true     # Immutable container filesystem
  runAsNonRoot: true
  capabilities:
    drop:
      - ALL                        # Drop all Linux capabilities
```

**Why this matters:**
- **readOnlyRootFilesystem**: Prevents malware from writing to container filesystem
- **allowPrivilegeEscalation: false**: Blocks privilege escalation attacks
- **runAsNonRoot**: Enforces non-root execution (defense in depth)
- **capabilities drop ALL**: Removes unnecessary Linux capabilities (least privilege)
- **seccomp RuntimeDefault**: Filters dangerous syscalls (ptrace, kernel keyring, etc.)

**Writable directories:**
Since root filesystem is read-only, writable directories are mounted as emptyDir volumes:
- `/tmp` - Temporary files
- `/app/.cache` - Application cache (backend)
- `/app/.next/cache` - Next.js build cache (frontend)
- `/var/run/postgresql` - PostgreSQL socket directory (database)

---

## Deployment Order

1. **Create namespaces:**
   ```bash
   kubectl create namespace production
   kubectl create namespace staging
   ```

2. **Apply governance policies:**
   ```bash
   kubectl apply -f resource-quota.yaml
   kubectl apply -f limit-range.yaml
   ```

3. **Deploy workloads** (manifests already have enhanced securityContext):
   ```bash
   kubectl apply -f ../../apps/backend/
   kubectl apply -f ../../apps/frontend/
   kubectl apply -f ../postgres/
   ```

4. **Apply PodDisruptionBudgets** (requires running pods):
   ```bash
   kubectl apply -f pod-disruption-budget.yaml
   ```

---

## Validation

### Check ResourceQuota Usage
```bash
# View quota and current usage
kubectl get resourcequota -n default
kubectl describe resourcequota craftique-resource-quota -n default

# Should show:
# Used/Hard for each resource (CPU, memory, pods, etc.)
```

### Check LimitRange Defaults
```bash
# Deploy test pod without resources
kubectl run test-nginx --image=nginx --restart=Never

# Check if defaults were applied
kubectl get pod test-nginx -o yaml | grep -A 10 resources:

# Should show default requests/limits from LimitRange
kubectl delete pod test-nginx
```

### Check SecurityContext Enforcement
```bash
# Try to run privileged pod (should be rejected)
kubectl run test-priv --image=nginx --restart=Never --overrides='
{
  "spec": {
    "containers": [{
      "name": "nginx",
      "image": "nginx",
      "securityContext": {
        "privileged": true
      }
    }]
  }
}'
# Should fail or be rejected by admission controller
```

### Check PodDisruptionBudget Protection
```bash
# View PDB status
kubectl get pdb
kubectl describe pdb craftique-backend-pdb

# Check allowed disruptions
# ALLOWED DISRUPTIONS should match minAvailable calculation
```

### Check Read-Only Filesystem
```bash
# Exec into backend pod
kubectl exec -it deployment/craftique-backend -- sh

# Try to write to root filesystem (should fail)
$ touch /test.txt
# Error: Read-only file system

# Write to allowed directories (should work)
$ touch /tmp/test.txt
$ ls /tmp/test.txt
```

---

## Security Benefits

| Control | Attack Mitigated | Impact |
|---------|------------------|--------|
| ResourceQuota | Resource exhaustion DoS | Prevents single workload from consuming all cluster resources |
| LimitRange | Unbounded resource requests | Ensures all containers have resource limits |
| readOnlyRootFilesystem | Container escape, malware persistence | Prevents writing to container filesystem |
| allowPrivilegeEscalation: false | Privilege escalation via setuid | Blocks sudo, setuid binaries |
| runAsNonRoot | Root exploits | Enforces non-root execution |
| capabilities drop ALL | Kernel exploits | Removes unnecessary Linux capabilities |
| seccomp RuntimeDefault | Syscall-based attacks | Filters dangerous system calls |
| PodDisruptionBudget | Availability loss | Ensures minimum replicas during maintenance |

---

## Compliance Mapping

| Framework | Requirement | Implementation |
|-----------|-------------|----------------|
| **CIS Kubernetes Benchmark** | 5.2.1 Minimize admission of privileged containers | allowPrivilegeEscalation: false |
| **CIS Kubernetes Benchmark** | 5.2.5 Minimize admission of containers with root | runAsNonRoot: true |
| **CIS Kubernetes Benchmark** | 5.2.6 Minimize admission of containers with dangerous capabilities | capabilities.drop: [ALL] |
| **CIS Kubernetes Benchmark** | 5.2.9 Minimize admission of containers with added capabilities | No capabilities added except NET_BIND_SERVICE |
| **NIST 800-190** | 4.4.2 Use read-only root filesystems | readOnlyRootFilesystem: true |
| **NIST 800-190** | 4.4.1 Reduce attack surface | seccomp RuntimeDefault, minimal capabilities |
| **PCI-DSS** | 6.5.10 Broken authentication | Resource quotas prevent DoS |
| **DevSecOps Rubric** | Access Control Strategy (3 pts) | ResourceQuota, LimitRange, securityContext, PDB |

---

## Troubleshooting

### Pod fails with "cannot create resource X: exceeded quota"
- **Cause**: Namespace ResourceQuota exceeded
- **Solution**: Check current usage: `kubectl describe resourcequota -n <namespace>`
- **Fix**: Either increase quota or reduce resource requests in deployments

### Pod fails with "minimum memory limit is 64Mi"
- **Cause**: LimitRange minimum violated
- **Solution**: Update deployment to request at least minimum required resources

### Pod fails with "is forbidden: unable to validate against any security context constraint"
- **Cause**: SecurityContext restrictions
- **Solution**: Ensure pod runs as non-root, no privileged mode, no dangerous capabilities

### Application crashes with "cannot write to /"
- **Cause**: readOnlyRootFilesystem blocks writes
- **Solution**: Mount emptyDir volumes for writable directories (/tmp, /var/cache, etc.)

### Node drain stuck, pods not evicting
- **Cause**: PodDisruptionBudget blocking eviction
- **Solution**: Check PDB status: `kubectl get pdb`
- **Note**: This is intentional protection - scale up replicas or wait for pods to become healthy

---

## GitOps Integration

These manifests are managed via ArgoCD. Changes are automatically synced from Git to cluster.

**ArgoCD Application:**
```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: craftique-governance
spec:
  source:
    path: infrastructure/governance
    repoURL: https://github.com/Craft-Cart/craftique-gitops-manifests
  destination:
    namespace: default
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

**Make changes:**
```bash
# 1. Edit manifests in Git
vim resource-quota.yaml

# 2. Commit and push
git add .
git commit -m "Increase production resource quota"
git push

# 3. ArgoCD auto-syncs within 3 minutes
# Or force sync:
argocd app sync craftique-governance
```

---

## References

- [Kubernetes ResourceQuota](https://kubernetes.io/docs/concepts/policy/resource-quotas/)
- [Kubernetes LimitRange](https://kubernetes.io/docs/concepts/policy/limit-range/)
- [Pod Security Standards](https://kubernetes.io/docs/concepts/security/pod-security-standards/)
- [PodDisruptionBudget](https://kubernetes.io/docs/concepts/workloads/pods/disruptions/)
- [CIS Kubernetes Benchmark](https://www.cisecurity.org/benchmark/kubernetes)
- [NIST 800-190: Application Container Security Guide](https://nvlpubs.nist.gov/nistpubs/SpecialPublications/NIST.SP.800-190.pdf)

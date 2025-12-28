**Cert-manager, Governance & Storage — simple guide**

This file explains the cluster-level infrastructure manifests under `infrastructure/cert-manager/`, `infrastructure/governance/`, and `infrastructure/storage/` in plain language with short code snippets from the repo.

1) Cert-manager (TLS certificates)
- Files: `infrastructure/cert-manager/letsencrypt-prod.yaml` and `letsencrypt-staging.yaml`.
- Purpose: these are ClusterIssuers that tell cert-manager how to request certificates from Let's Encrypt (production and staging).

Key snippet (production issuer):

```yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: omar.samir.galal@gmail.com
    privateKeySecretRef:
      name: letsencrypt-prod
    solvers:
      - http01:
          ingress:
            class: nginx
```

Simple explanation:
- `server`: Let's Encrypt API endpoint (use staging for testing).
- `email`: used for account registration and important notices.
- `privateKeySecretRef`: name of k8s Secret where cert-manager stores its ACME account key.
- `solvers.http01.ingress.class`: cert-manager will create temporary solver pods/ingress rules to respond to HTTP-01 challenges via the nginx ingress controller.

Notes / How it ties to the repo
- `networking/ingress.yaml` uses `cert-manager.io/cluster-issuer: "letsencrypt-prod"` in annotations so Ingresses request certificates from this ClusterIssuer.
- Ensure `allow-cert-manager-solver.yaml` (network policy) allows HTTP-01 solver traffic (in this repo it does).

Quick verify commands
```bash
kubectl get clusterissuer letsencrypt-prod
kubectl describe clusterissuer letsencrypt-prod
```

2) Governance (resource controls and availability)
- Files: `infrastructure/governance/limit-range.yaml`, `pod-disruption-budgets.yaml`, `resource-quota.yaml`.
- Purpose: enforce resource defaults/limits, control how many resources the namespace can create, and control availability during maintenance.

LimitRange (sets defaults/max/min for containers)

Snippet:

```yaml
apiVersion: v1
kind: LimitRange
metadata:
  name: craftique-limits
spec:
  limits:
    - type: Container
      default:
        cpu: "500m"
        memory: "512Mi"
      defaultRequest:
        cpu: "100m"
        memory: "128Mi"
      max:
        cpu: "1"
        memory: "1Gi"
      min:
        cpu: "10m"
        memory: "64Mi"
```

Simple: if a Pod does not specify resource requests/limits, Kubernetes will use the `defaultRequest` and `default` values. The `max` prevents a container asking for excessive resources.

ResourceQuota (limits total resource usage and object counts)

Snippet:

```yaml
apiVersion: v1
kind: ResourceQuota
metadata:
  name: craftique-quota
spec:
  hard:
    requests.cpu: "2"
    requests.memory: "2Gi"
    limits.cpu: "4"
    limits.memory: "4Gi"
    pods: "10"
    services: "5"
    persistentvolumeclaims: "3"
    secrets: "10"
```

Simple: this prevents the `default` namespace from creating more than the specified number of pods, PVCs, etc., and caps total requested CPU/memory.

PodDisruptionBudget (PDB)

Snippet (backend PDB):

```yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: backend-pdb
spec:
  minAvailable: 1
  selector:
    matchLabels:
      app: craftique-backend
```

Simple: PDB prevents voluntary evictions (e.g., during node drain) from reducing available replicas below `minAvailable`. For single-replica deployments, `minAvailable: 1` means don't evict.

Why governance matters (plain):
- Avoid noisy neighbors (one app consuming all cluster resources).
- Prevent accidental mass creation of objects.
- Ensure some pods remain available during upgrades or maintenance.

3) Storage (storage classes for encrypted disks)
- File: `infrastructure/storage/encrypted-storage-classes.yaml`.
- Purpose: defines StorageClass objects that determine how PVCs provision disks (type, performance, encryption behavior).

Key snippet (balanced SSD example):

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: pd-balanced-encrypted
provisioner: kubernetes.io/gce-pd
parameters:
  type: pd-balanced
  fstype: ext4
volumeBindingMode: WaitForFirstConsumer
allowVolumeExpansion: true
```

Simple explanation:
- `provisioner`: GKE/Compute Engine persistent disk driver.
- `type`: disk type (`pd-standard`, `pd-ssd`, `pd-balanced`) — affects cost and performance.
- `volumeBindingMode: WaitForFirstConsumer` delays provisioning until a Pod is scheduled (useful for topology-aware provisioning).
- `allowVolumeExpansion`: lets you increase PVC size later.
- These classes are configured to use Google-managed encryption at rest by default.

Mapping to repo manifests
- `infrastructure/postgres/postgres-pvc.yaml` and `postgres-statefulset.yaml` request `storageClassName: standard-rwo`. If you want encrypted PDs, consider using one of the `pd-*-encrypted` StorageClasses or updating the PVC to reference `pd-balanced-encrypted` for production databases.

Apply & verify (commands)
```bash
# apply cert-manager issuers
kubectl apply -f infrastructure/cert-manager/letsencrypt-staging.yaml
kubectl apply -f infrastructure/cert-manager/letsencrypt-prod.yaml

# apply governance
kubectl apply -f infrastructure/governance/limit-range.yaml
kubectl apply -f infrastructure/governance/resource-quota.yaml
kubectl apply -f infrastructure/governance/pod-disruption-budgets.yaml

# apply storage classes
kubectl apply -f infrastructure/storage/encrypted-storage-classes.yaml

# verify
kubectl get clusterissuer
kubectl get limitrange -n default
kubectl get resourcequota -n default
kubectl get storageclass
```

Short recommendations (practical)
- Use `letsencrypt-staging` to verify ACME flow before switching to `letsencrypt-prod` to avoid rate limits during testing.
- Ensure DNS for your host points to the ingress controller so HTTP-01 validation succeeds.
- Align `storageClassName` used by PVCs (e.g., Postgres) with the production class you want (e.g., `pd-balanced-encrypted`).
- Set reasonable `LimitRange` defaults and `ResourceQuota` to protect cluster stability.
- Use PDBs for stateful or critical services so maintenance does not bring them fully down.

If you want, I can now:
- update `postgres-pvc.yaml` to use `pd-balanced-encrypted` (suggested for prod), or
- produce a short checklist of commands to validate cert issuance and storage provisioning in your cluster.

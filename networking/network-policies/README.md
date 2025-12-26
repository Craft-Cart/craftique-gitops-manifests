# Craftique Network Policies - Documentation

## Overview

Network policies implement **default-deny** security with explicit allow rules for legitimate traffic flows. This follows the principle of least privilege and provides defense-in-depth against lateral movement attacks.

## Architecture

```
                    ┌──────────────────┐
                    │  Ingress Nginx   │
                    │  (Ingress Ctrl)  │
                    └────────┬─────────┘
                             │
              ┌──────────────┼──────────────┐
              │              │              │
              ▼              ▼              │
        ┌──────────┐   ┌──────────┐        │
        │ Frontend │   │ Backend  │        │
        │  Pods    │──▶│  Pods    │        │
        └──────────┘   └────┬─────┘        │
                             │              │
                             ▼              │
                       ┌──────────┐        │
                       │PostgreSQL│        │
                       │  Pods    │        │
                       └──────────┘        │
                             │              │
                             ▼              ▼
                       ┌──────────────────────┐
                       │   CoreDNS (DNS)      │
                       │   kube-system        │
                       └──────────────────────┘
```

## Network Policies

### 1. Default-Deny Baseline (`default-deny.yaml`)

**Policy:** `default-deny-all`  
**Namespaces:** default, production, staging  
**Effect:** Blocks ALL ingress and egress traffic by default

```yaml
spec:
  podSelector: {}  # Applies to all pods
  policyTypes:
    - Ingress
    - Egress
  # Empty rules = deny all
```

**Why this matters:**
- **Zero-trust security**: No traffic is allowed unless explicitly permitted
- **Lateral movement prevention**: Compromised pods can't reach other pods
- **Compliance**: Meets PCI-DSS, NIST 800-53 network segmentation requirements

**Alternative:** `default-deny-ingress` (blocks ingress only, allows egress)

---

### 2. DNS Resolution (`allow-policies.yaml`)

**Policy:** `allow-dns`  
**Effect:** Allows all pods to query CoreDNS for service discovery

```yaml
egress:
  - to:
      - namespaceSelector:
          matchLabels:
            kubernetes.io/metadata.name: kube-system
      - podSelector:
          matchLabels:
            k8s-app: kube-dns
    ports:
      - protocol: UDP
        port: 53
      - protocol: TCP
        port: 53
```

**Required for:** Service name resolution (e.g., `backend-service.default.svc.cluster.local`)

---

### 3. Backend Database Access (`allow-backend-to-db.yaml`)

**Policy:** `allow-backend-to-db`  
**Effect:** Allows backend pods to connect to PostgreSQL on port 5432

```yaml
spec:
  podSelector:
    matchLabels:
      app: postgres
  ingress:
    - from:
        - podSelector:
            matchLabels:
              app: craftique-backend
      ports:
        - protocol: TCP
          port: 5432
```

**Traffic flow:** Backend → PostgreSQL (port 5432)

---

### 4. Frontend to Backend API (`allow-policies.yaml`)

**Policy:** `allow-frontend-to-backend`  
**Effect:** Allows frontend to make HTTP requests to backend API

```yaml
spec:
  podSelector:
    matchLabels:
      app: craftique-backend
  ingress:
    - from:
        - podSelector:
            matchLabels:
              app: craftique-frontend
      ports:
        - protocol: TCP
          port: 8000
```

**Traffic flow:** Frontend → Backend (port 8000)

---

### 5. Ingress Controller Access (`allow-policies.yaml`)

**Policies:** 
- `allow-ingress-to-frontend`
- `allow-ingress-to-backend`

**Effect:** Allows ingress-nginx to route external traffic to services

```yaml
ingress:
  - from:
      - namespaceSelector:
          matchLabels:
            name: ingress-nginx
      - podSelector:
          matchLabels:
            app.kubernetes.io/name: ingress-nginx
    ports:
      - protocol: TCP
        port: 3000  # or 8000 for backend
```

**Traffic flow:** Internet → Ingress Controller → Frontend/Backend

---

### 6. External API Access (`allow-policies.yaml`)

**Policy:** `allow-backend-external-egress`  
**Effect:** Allows backend to reach external APIs (Auth0, Paymob)

```yaml
egress:
  - to:
      - namespaceSelector: {}
    ports:
      - protocol: TCP
        port: 443  # HTTPS
      - protocol: TCP
        port: 80   # HTTP redirects
```

**Traffic flow:** Backend → External APIs (Auth0, Paymob, etc.)

---

### 7. Database Replication (`allow-policies.yaml`)

**Policy:** `allow-postgres-internal`  
**Effect:** Allows PostgreSQL pods to communicate for replication

```yaml
ingress:
  - from:
      - podSelector:
          matchLabels:
            app: postgres
    ports:
      - protocol: TCP
        port: 5432
```

**Traffic flow:** PostgreSQL Primary ↔ PostgreSQL Replicas

---

### 8. Prometheus Monitoring (`allow-policies.yaml`)

**Policy:** `allow-prometheus-scraping`  
**Effect:** Allows Prometheus to scrape metrics from pods

```yaml
ingress:
  - from:
      - namespaceSelector:
          matchLabels:
            name: monitoring
      - podSelector:
          matchLabels:
            app: prometheus
    ports:
      - protocol: TCP
        port: 8000  # Backend metrics
      - protocol: TCP
        port: 3000  # Frontend metrics
```

**Traffic flow:** Prometheus → Application Pods (metrics endpoints)

---

## Traffic Matrix

| Source | Destination | Port | Protocol | Policy |
|--------|-------------|------|----------|--------|
| Internet | Ingress Controller | 80, 443 | TCP | External |
| Ingress Controller | Frontend | 3000 | TCP | allow-ingress-to-frontend |
| Ingress Controller | Backend | 8000 | TCP | allow-ingress-to-backend |
| Frontend | Backend | 8000 | TCP | allow-frontend-to-backend |
| Backend | PostgreSQL | 5432 | TCP | allow-backend-to-db |
| Backend | External APIs | 443 | TCP | allow-backend-external-egress |
| All Pods | CoreDNS | 53 | UDP/TCP | allow-dns |
| PostgreSQL | PostgreSQL | 5432 | TCP | allow-postgres-internal |
| Prometheus | All Pods | 8000, 3000 | TCP | allow-prometheus-scraping |

---

## Deployment Order

**CRITICAL:** Deploy in this order to avoid connectivity issues:

1. **Default-deny policy** (blocks all traffic)
   ```bash
   kubectl apply -f default-deny.yaml
   ```

2. **DNS policy** (allows service discovery)
   ```bash
   kubectl apply -f allow-policies.yaml
   # Extract just the allow-dns policy
   ```

3. **Application-specific policies** (in order of dependency)
   ```bash
   # Database access first
   kubectl apply -f allow-backend-to-db.yaml
   
   # Then frontend-backend communication
   kubectl apply -f allow-policies.yaml
   ```

4. **Ingress policies** (last, for external access)
   ```bash
   kubectl apply -f allow-policies.yaml
   # Extract ingress policies
   ```

---

## Validation

### Test Connectivity

```bash
# Test DNS resolution
kubectl run test-dns --rm -it --image=busybox -- nslookup backend-service
# Should succeed (DNS allowed)

# Test blocked traffic
kubectl run test-blocked --rm -it --image=busybox -- wget -O- http://postgres-service:5432
# Should timeout (no policy allowing busybox → postgres)

# Test allowed traffic (from backend pod)
kubectl exec -it deployment/craftique-backend -- curl http://postgres-service:5432
# Should connect (backend → postgres allowed)

# Test frontend → backend
kubectl exec -it deployment/craftique-frontend -- curl http://backend-service:8000/health
# Should succeed
```

### View Active Policies

```bash
# List all network policies
kubectl get networkpolicy -A

# Describe specific policy
kubectl describe networkpolicy default-deny-all -n default

# Check policy for specific pod
kubectl get pods -l app=craftique-backend -o wide
kubectl describe networkpolicy allow-backend-to-db
```

### Troubleshooting

**Symptom:** Pods can't communicate despite policy

```bash
# 1. Check if NetworkPolicy CRD is installed
kubectl api-resources | grep networkpolicies

# 2. Verify CNI supports NetworkPolicy (Calico, Cilium, etc.)
kubectl get nodes -o wide
# Check CNI plugin in use

# 3. Check pod labels match policy selectors
kubectl get pod <pod-name> --show-labels
kubectl get networkpolicy <policy-name> -o yaml

# 4. Temporarily disable default-deny for testing
kubectl delete networkpolicy default-deny-all -n default
# Test connectivity, then re-apply
```

---

## Security Benefits

| Attack Vector | Mitigation | Impact |
|---------------|------------|--------|
| **Lateral movement** | Default-deny blocks pod-to-pod traffic | High - Prevents compromise spread |
| **Data exfiltration** | Egress policies restrict external access | High - Blocks unauthorized outbound connections |
| **Service scanning** | Only specific ports allowed | Medium - Reduces attack surface |
| **DNS spoofing** | DNS traffic only to kube-dns | Medium - Prevents DNS hijacking |
| **Database exposure** | Only backend can access database | High - Prevents unauthorized DB access |
| **External attacks** | Ingress policies limit entry points | High - Controlled internet exposure |

---

## Compliance Mapping

| Framework | Requirement | Implementation |
|-----------|-------------|----------------|
| **PCI-DSS 1.2.1** | Network segmentation for cardholder data | Default-deny + database isolation |
| **PCI-DSS 1.3.4** | Restrict outbound traffic | Egress policies for backend |
| **NIST 800-53 SC-7** | Boundary protection | Default-deny baseline |
| **NIST 800-53 AC-4** | Information flow enforcement | Explicit allow policies |
| **CIS Kubernetes 5.3.2** | Ensure default-deny policy exists | default-deny-all policy |
| **ISO 27001 A.13.1.3** | Segregation of networks | Namespace + NetworkPolicy isolation |

---

## Best Practices

### DO's ✅
- **Start with default-deny** then add allow rules
- **Test policies in staging** before production
- **Use specific selectors** (avoid broad wildcards)
- **Document all policies** with comments
- **Version control policies** in Git
- **Monitor denied connections** via CNI logs

### DON'Ts ❌
- **Don't apply allow policies before default-deny** (leaves window of exposure)
- **Don't use `{}` selectors** for ingress/egress (allows all)
- **Don't disable policies in production** for debugging
- **Don't forget DNS policy** (pods won't resolve services)
- **Don't use IP addresses** in policies (use label selectors)

---

## References

- [Kubernetes Network Policies](https://kubernetes.io/docs/concepts/services-networking/network-policies/)
- [CIS Kubernetes Benchmark 5.3](https://www.cisecurity.org/benchmark/kubernetes)
- [NIST 800-53 SC-7 Boundary Protection](https://nvlpubs.nist.gov/nistpubs/SpecialPublications/NIST.SP.800-53r5.pdf)
- [PCI-DSS Network Segmentation Guide](https://www.pcisecuritystandards.org/)
- [Calico Network Policy Guide](https://docs.tigera.io/calico/latest/network-policy/)

---

**Last Updated:** 2025-12-26  
**Maintained by:** Platform Team  
**Status:** Production-Ready

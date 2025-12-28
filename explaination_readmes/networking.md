**Networking — simple guide to the repo's Ingress and NetworkPolicies**

This file explains the networking manifests in this repository in plain language and shows short, relevant code snippets from the actual YAML files so you can follow along.

Why networking files matter
- They control how external traffic reaches your app (`Ingress`) and how pods talk to each other (`NetworkPolicy`). The files live under `networking/` and `networking/network-policies/`.

Files covered
- `networking/ingress.yaml` — routes external HTTP(S) traffic to frontend and backend.
- `networking/network-policies/allow-ingress-to-frontend.yaml` — limits who can reach the frontend pods.
- `networking/network-policies/allow-ingress-to-backend.yaml` — limits who can reach the backend pods.
- `networking/network-policies/allow-frontend-egress.yaml` — controls where frontend pods can send traffic.
- `networking/network-policies/allow-backend-egress.yaml` — controls backend outbound traffic.
- `networking/network-policies/allow-backend-to-db.yaml` — allows backend to connect to Postgres.
- `networking/network-policies/allow-cert-manager-solver.yaml` — allows cert-manager HTTP-01 solver traffic.

1) `networking/ingress.yaml` — routes and TLS
Key idea: Ingress maps host+path → Service inside the cluster. TLS is provided by `cert-manager`.

Snippet:

```yaml
spec:
  tls:
    - hosts:
        - craftique.chickenkiller.com
      secretName: craftique-tls-cert
  rules:
    - host: craftique.chickenkiller.com
      http:
        paths:
          - path: /api
            backend:
              service:
                name: backend-service
                port:
                  number: 8000
          - path: /
            backend:
              service:
                name: frontend-service
                port:
                  number: 3000
```

What to understand (simple):
- Requests to `craftique.chickenkiller.com/api` go to the `backend-service` on port `8000`.
- Requests to `/` go to `frontend-service` on port `3000`.
- TLS: certificate stored in the `craftique-tls-cert` secret (managed by `cert-manager`).

2) NetworkPolicies — short, plain explanation
NetworkPolicies are additive firewall rules for pods. A pod without any matching NetworkPolicy is allowed all traffic. Once any NetworkPolicy selects a pod, only the allowed traffic in those policies is permitted.

Important examples from this repo (short):

- `allow-ingress-to-frontend.yaml` — allows traffic to frontend pods on port 3000. Example:

```yaml
spec:
  podSelector:
    matchLabels:
      app: craftique-frontend
  policyTypes:
    - Ingress
  ingress:
    - from:
        - namespaceSelector:
            matchLabels:
              name: ingress-nginx
      ports:
        - protocol: TCP
          port: 3000
```

Simple: only the ingress controller namespace (label `name: ingress-nginx`) may reach frontend on port 3000.

- `allow-ingress-to-backend.yaml` — allows ingress controller and frontend to reach backend on port 8000; also includes a permissive "allow all" rule used for free-tier simplicity.

Snippet (core parts):

```yaml
spec:
  podSelector:
    matchLabels:
      app: craftique-backend
  ingress:
    - from:
        - namespaceSelector:
            matchLabels:
              name: ingress-nginx
      ports:
        - protocol: TCP
          port: 8000
    - from:
        - podSelector:
            matchLabels:
              app: craftique-frontend
      ports:
        - protocol: TCP
          port: 8000
```

Meaning: the frontend (pod label `app: craftique-frontend`) can call the backend directly. The ingress controller can also forward public requests to the backend.

- `allow-backend-to-db.yaml` — allows backend pods to connect to Postgres pods on port 5432.

Snippet:

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

Meaning: only pods labeled `app: craftique-backend` can talk to pods labeled `app: postgres` on Postgres port.

- `allow-frontend-egress.yaml` and `allow-backend-egress.yaml` — control outbound traffic from frontend and backend pods (DNS, and specific service ports such as backend->db).

Example (frontend egress to backend):

```yaml
spec:
  podSelector:
    matchLabels:
      app: craftique-frontend
  egress:
    - to:
        - podSelector:
            matchLabels:
              app: craftique-backend
      ports:
        - protocol: TCP
          port: 8000
```

Meaning: frontend pods can send traffic to backend pods on port 8000; DNS traffic is also allowed so pods can resolve names.

- `allow-cert-manager-solver.yaml` — permits cert-manager HTTP-01 solver pods to receive HTTP validation requests and to reach the internet (Let's Encrypt). It also allows DNS egress.

Small notes & recommendations (practical)
- Labeling: NetworkPolicies use labels (`app: craftique-backend`, `app: postgres`) — ensure your Deployments/StatefulSets set these labels so policies match pods.
- Default deny: if you add a NetworkPolicy that selects a pod, remember to include rules for necessary traffic (DNS, kube-api access if needed, etc.).
- Test incrementally: apply policies one at a time and test access (frontend, backend, DB) so you do not accidentally block required traffic.
- Ingress TLS: `cert-manager` handles the certificate; check `infrastructure/cert-manager/` for issuers.

Where to look next in this repo
- Ingress manifest: `networking/ingress.yaml`.
- Policies: `networking/network-policies/` (all YAMLs listed above).
- If you change service ports, update both the Service manifests and NetworkPolicies to match.

If you want, I can now:
- (A) generate a checklist script to validate labels and ports across `apps/` and `infrastructure/` manifests, or
- (B) produce a small test plan (kubectl commands) to verify connectivity after applying policies.

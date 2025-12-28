**Deployment Flow — simple version**

This file explains, in plain language, how code moves from your laptop into the cluster for this repo. It uses GitHub Actions to build images, Google Cloud (Artifact Registry + GKE) to host them and the cluster, and Google Secret Manager for secrets.

Quick 5-step overview
- Build: GitHub Actions builds a container image from your code.
- Push: Actions pushes the image to Artifact Registry.
- Update Git: Actions updates the GitOps manifests (image reference) and pushes a commit or opens a PR.
- Sync: Argo CD notices the change and applies the updated manifests to the cluster.
- Verify: health checks, smoke tests, or rollbacks happen if needed.

Why these steps? Keep code and infrastructure declarative in Git and let Argo CD make the cluster match Git.

Simple example: Argo CD watches this repo
Here is the actual `argocd/craftique-app.yaml` from this project — Argo CD is configured to auto-apply changes:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: craftique-platform
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/Craft-Cart/craftique-gitops-manifests.git
    targetRevision: main
    path: .
    directory:
      recurse: true
  destination:
    server: https://kubernetes.default.svc
    namespace: default
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```

What this means (simple):
- Argo CD watches `main` branch of the repo and applies any changes under the repo to the `default` namespace.
- `selfHeal: true` makes Argo CD fix drift automatically.
- `prune: true` deletes resources that are removed from Git.

Where to change the image (example)
- Open `apps/backend/backend-deployment.yaml` and find the container `image:` line. Replace it with the new image pushed by CI, e.g.:

```yaml
containers:
- name: backend
  image: us-central1-docker.pkg.dev/PROJECT/repo/backend:sha-abc1234
```

Simple GitHub Actions workflow (short)
- Trigger: push to `main` (or tag). Steps: build image → push → update manifest → open PR or push commit.

Minimal example steps (pseudo-commands you can copy):

1) Build and push image
```bash
IMAGE=us-central1-docker.pkg.dev/PROJECT/repo/backend:sha-$SHORT
docker build -t $IMAGE ./apps/backend
docker push $IMAGE
```

2) Update manifest (simple script)
```bash
sed -i "s|image: .*backend:.*|image: $IMAGE|" apps/backend/backend-deployment.yaml
git add apps/backend/backend-deployment.yaml
git commit -m "chore: backend -> $IMAGE"
git push origin main
```

Secrets — keep them out of Git
- Recommended: use External Secrets Operator (ESO) to sync Google Secret Manager → Kubernetes. Then your manifests in Git only reference the `ExternalSecret` object, not raw secret values.
- If you must inject secrets from Actions, read them from GSM during the workflow and create Kubernetes Secrets with `kubectl create secret` (avoid committing them to Git).

Best practices (plain)
- Use OIDC (Workload Identity) so GitHub Actions can authenticate to GCP without long-lived keys.
- Push immutable image digests (sha256) into manifests for reproducible deploys.
- Keep secrets encrypted or managed by an in-cluster operator (ESO or SOPS/SealedSecrets).
- Add a smoke-test step after deploy to verify the app works.

Next steps I can do for you
- Generate a simple, ready-to-run GitHub Actions workflow file that builds the backend and updates `apps/backend/backend-deployment.yaml`.
- Create `ExternalSecret` example manifest and the minimal IAM commands needed to allow ESO to read GSM.
- Add a tiny shell script to update image references and open a PR instead of pushing to `main`.
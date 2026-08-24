# Project 27 — Kubernetes GitOps with Argo CD

A production-style GitOps lab where Kubernetes desired state lives in Git and Argo CD continuously reconciles the cluster from that source of truth.

## Architecture

```text
Application Repository
        |
        | CI builds immutable image
        v
    Container Registry
        |
        | image tag update
        v
   GitOps Repository (this repo)
        |
        +---- base/
        +---- overlays/staging/
        +---- overlays/production/
        |
        v
      Argo CD
        |
        +---- staging cluster/namespace
        +---- production cluster/namespace
        |
        +---- drift detection
        +---- self-healing
        +---- sync history
        +---- rollback to Git revision
```

## GitOps rules

- Kubernetes desired state is stored in Git.
- Production changes happen through Git commits/PRs, not direct `kubectl apply`.
- CI validates manifests and may update an image tag in Git after a successful build.
- Argo CD is responsible for synchronization and drift reconciliation.
- Production uses a manual promotion PR rather than automatically promoting every staging build.

## Layout

```text
apps/
  base/
    deployment.yaml
    service.yaml
    kustomization.yaml
  overlays/
    staging/
      kustomization.yaml
      namespace.yaml
      patch-replicas.yaml
    production/
      kustomization.yaml
      namespace.yaml
      patch-replicas.yaml
argocd/
  project.yaml
  app-of-apps.yaml
  staging-app.yaml
  production-app.yaml
scripts/
  validate.sh
.github/workflows/
  validate.yml
  update-image-tag.yml
```

## Image promotion workflow

1. CI in the application repository builds an immutable image such as `ghcr.io/example/myapp:<git-sha>`.
2. CI opens or updates a PR against this GitOps repository changing the staging image tag.
3. Review/merge updates staging desired state.
4. Argo CD detects the Git change and syncs staging.
5. After staging verification, a separate PR promotes the same immutable image digest/tag to production.
6. Argo CD syncs production.

## Argo CD setup

Update `argocd/staging-app.yaml` and `argocd/production-app.yaml` with your GitOps repository URL and real cluster destinations before applying the Argo CD objects.

```bash
kubectl apply -f argocd/project.yaml
kubectl apply -f argocd/staging-app.yaml
kubectl apply -f argocd/production-app.yaml
```

The production Application is configured with automated sync plus self-healing, so Git remains authoritative. In a real organization, place a protected PR/approval process around production Git changes.

## Validation

```bash
bash scripts/validate.sh
```

The same validation runs in GitHub Actions. The workflow does not deploy anything.

## Rollback

Rollback is a Git operation: revert the production image or manifest change, merge the PR, and let Argo CD reconcile the previous desired state. Argo CD also maintains sync history that can be used for controlled rollback workflows.

## Notes

This repository is intentionally the GitOps repository, not the application source repository. The separation demonstrates the production pattern where application CI and deployment state are decoupled.

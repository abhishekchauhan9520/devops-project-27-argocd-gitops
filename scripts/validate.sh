#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

command -v python3 >/dev/null 2>&1 || { echo 'python3 is required' >&2; exit 1; }

python3 - <<'PY'
from pathlib import Path
import re, sys

try:
    import yaml
except Exception as exc:
    print(f'PyYAML is required: {exc}', file=sys.stderr)
    sys.exit(1)

root = Path('.')
files = sorted(root.glob('apps/**/*.yaml')) + sorted(root.glob('argocd/**/*.yaml'))
assert files, 'No YAML files discovered'

for path in files:
    docs = list(yaml.safe_load_all(path.read_text()))
    assert docs, f'{path}: no YAML document'
    for doc in docs:
        assert isinstance(doc, dict), f'{path}: document is not a mapping'
        assert 'apiVersion' in doc and 'kind' in doc, f'{path}: missing apiVersion/kind'

base = yaml.safe_load(Path('apps/base/deployment.yaml').read_text())
container = base['spec']['template']['spec']['containers'][0]
assert container['image'].startswith('ghcr.io/example/gitops-demo:'), 'Base image reference invalid'
assert container['readinessProbe']['httpGet']['path'] == '/health'
assert container['livenessProbe']['httpGet']['path'] == '/health'
assert container['securityContext']['runAsNonRoot'] is True

for env in ('staging', 'production'):
    k = yaml.safe_load(Path(f'apps/overlays/{env}/kustomization.yaml').read_text())
    expected = 'v1.0.0'
    image = next(i for i in k['images'] if i['name'] == 'ghcr.io/example/gitops-demo')
    assert image['newTag'] == expected, f'{env}: unexpected initial tag'

for env in ('staging', 'production'):
    app = yaml.safe_load(Path(f'argocd/apps/{env}-app.yaml').read_text())
    assert app['kind'] == 'Application'
    assert app['spec']['source']['path'] == f'apps/overlays/{env}'
    assert app['spec']['syncPolicy']['automated']['selfHeal'] is True

root_app = yaml.safe_load(Path('argocd/app-of-apps.yaml').read_text())
assert root_app['spec']['source']['path'] == 'argocd/apps'
assert root_app['spec']['syncPolicy']['automated']['selfHeal'] is True

project = yaml.safe_load(Path('argocd/project.yaml').read_text())
assert 'gitops-demo' == project['metadata']['name']
assert 'https://github.com/abhishekchauhan9520/devops-project-27-argocd-gitops.git' in project['spec']['sourceRepos']

print(f'Validated {len(files)} GitOps/Argo manifests and policy checks.')
PY

if command -v kubectl >/dev/null 2>&1; then
  kubectl kustomize apps/overlays/staging >/tmp/gitops-staging.yaml
  kubectl kustomize apps/overlays/production >/tmp/gitops-production.yaml
  echo 'kubectl kustomize build: PASS'
else
  echo 'kubectl not installed locally; YAML semantic checks passed.'
fi

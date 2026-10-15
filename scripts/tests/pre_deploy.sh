#!/usr/bin/env bash
# Tests exécutés AVANT tout déploiement. Un seul échec => code retour != 0.
set -euo pipefail

ENV="${1:?Usage : $0 <env>}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

ok() { echo "  [OK] $1"; }

echo "[TEST 1] Fichier de variables de l'environnement présent"
test -f "envs/$ENV.tfvars"
ok "envs/$ENV.tfvars"

echo "[TEST 2] Format du code Terraform (terraform fmt -check)"
terraform -chdir=terraform fmt -check -recursive -diff
ok "format conforme"

echo "[TEST 3] Validation syntaxique et sémantique (terraform validate)"
terraform -chdir=terraform init -input=false >/dev/null
terraform -chdir=terraform validate
ok "configuration Terraform valide"

echo "[TEST 4] Syntaxe du playbook Ansible"
ANSIBLE_CONFIG="$ROOT/ansible/ansible.cfg" \
  ansible-playbook --syntax-check -i localhost, ansible/site.yml >/dev/null
ok "playbook valide"

echo "[TEST 5] Aucun secret valorisé dans le dépôt"
if grep -RInE '(password|passwd|secret|token|api_key)[[:space:]]*[:=][[:space:]]*["'"'"']?[A-Za-z0-9/+_-]{6,}' \
     --exclude-dir=.git --exclude-dir=.terraform --exclude-dir=preuves --exclude-dir=dist \
     --exclude=.env --exclude=.env.example --exclude='*.tfstate*' -i . ; then
  echo "  [KO] Secret potentiel détecté ci-dessus"
  exit 1
fi
ok "aucun secret détecté"

echo "Tests pré-déploiement : SUCCÈS"

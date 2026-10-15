#!/usr/bin/env bash
# Commande unique de déploiement UrbanHub.
#   Usage : ./scripts/deploy.sh <dev|prod>
# Enchaîne : tests pré-déploiement -> Terraform (instance + inventaire)
#            -> Ansible (serveur web) -> supervision -> tests post-déploiement.
# Toute étape en échec arrête la chaîne (set -euo pipefail + trap).
set -Eeuo pipefail

ENV="${1:-}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if [[ ! "$ENV" =~ ^(dev|prod)$ ]]; then
  echo "Usage : $0 <dev|prod>" >&2
  exit 2
fi

VARS_FILE="$ROOT/envs/$ENV.tfvars"

# Variables sensibles : uniquement via l'environnement ou un fichier .env non versionné
if [[ -f "$ROOT/.env" ]]; then
  set -a; source "$ROOT/.env"; set +a
fi
: "${GF_ADMIN_PASSWORD:?Variable GF_ADMIN_PASSWORD absente (copier .env.example en .env et la renseigner)}"

# Journal horodaté de l'exécution (sert de preuve)
mkdir -p "$ROOT/preuves"
LOG="$ROOT/preuves/deploy_${ENV}_$(date +%Y%m%d-%H%M%S).log"
exec > >(tee -a "$LOG") 2>&1

STEP="initialisation"
step() { STEP="$1"; echo; echo "=== [$(date '+%F %T')] ÉTAPE : $STEP ==="; }
on_error() {
  echo
  echo "!!! [$(date '+%F %T')] ÉCHEC à l'étape « $STEP » — chaîne de déploiement ARRÊTÉE (env=$ENV)"
}
trap on_error ERR

step "prérequis"
for bin in docker terraform ansible-playbook ansible-galaxy curl; do
  command -v "$bin" >/dev/null || { echo "Outil manquant : $bin"; false; }
done
docker info >/dev/null

step "tests pré-déploiement (validation du code)"
"$ROOT/scripts/tests/pre_deploy.sh" "$ENV"

step "Terraform : création de l'instance $ENV"
terraform -chdir=terraform workspace select -or-create "$ENV"
terraform -chdir=terraform apply -input=false -auto-approve -var-file="$VARS_FILE"
APP_URL="$(terraform -chdir=terraform output -raw app_url)"
echo "Instance : $(terraform -chdir=terraform output -raw instance_name) — IP $(terraform -chdir=terraform output -raw instance_ip) — URL $APP_URL"
echo "--- Inventaire généré ---"
cat "ansible/inventory/$ENV.ini"

step "Ansible : configuration du serveur web"
export ANSIBLE_CONFIG="$ROOT/ansible/ansible.cfg"
ansible-galaxy collection install -r ansible/requirements.yml >/dev/null
ansible-playbook -i "ansible/inventory/$ENV.ini" ansible/site.yml

step "supervision : Prometheus / Grafana"
docker compose -f monitoring/docker-compose.yml up -d

step "tests post-déploiement (le service répond)"
"$ROOT/scripts/tests/smoke_test.sh" "$APP_URL" "$ENV"

echo
echo "=== [$(date '+%F %T')] DÉPLOIEMENT $ENV RÉUSSI ==="
echo "Application : $APP_URL"
echo "Grafana     : http://localhost:3000 (tableau de bord « UrbanHub — Supervision »)"
echo "Prometheus  : http://localhost:9090/alerts"
echo "Journal     : preuves/$(basename "$LOG")"

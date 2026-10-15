#!/usr/bin/env bash
# Destruction d'un environnement.
#   Usage : ./scripts/destroy.sh <dev|prod> [--with-monitoring]
set -euo pipefail

ENV="${1:-}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
[[ "$ENV" =~ ^(dev|prod)$ ]] || { echo "Usage : $0 <dev|prod> [--with-monitoring]" >&2; exit 2; }

terraform -chdir=terraform workspace select "$ENV"
terraform -chdir=terraform destroy -input=false -auto-approve -var-file="$ROOT/envs/$ENV.tfvars"

if [[ "${2:-}" == "--with-monitoring" ]]; then
  GF_ADMIN_PASSWORD="${GF_ADMIN_PASSWORD:-unused}" docker compose -f monitoring/docker-compose.yml down -v
fi

echo "Environnement $ENV détruit. Vérification :"
docker ps -a --filter "label=project=urbanhub" --filter "label=env=$ENV" --format '{{.Names}}' | grep . \
  && { echo "Des conteneurs subsistent"; exit 1; } || echo "  aucune instance $ENV restante"

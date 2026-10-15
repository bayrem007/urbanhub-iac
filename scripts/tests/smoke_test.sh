#!/usr/bin/env bash
# Test APRÈS déploiement : le service répond, avec le bon contenu et le bon environnement.
#   Usage : smoke_test.sh <url> <env>
set -euo pipefail

URL="${1:?Usage : $0 <url> <env>}"
ENV="${2:?Usage : $0 <url> <env>}"
TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT

CODE_TIME="000 0"
echo "[SMOKE] GET $URL/ (10 tentatives max)"
for i in $(seq 1 10); do
  if CODE_TIME="$(curl -sS -o "$TMP" -w '%{http_code} %{time_total}' "$URL/")"; then
    break
  fi
  echo "  tentative $i : pas de réponse, nouvel essai dans 2 s"
  sleep 2
done

CODE="${CODE_TIME%% *}"
TIME="${CODE_TIME##* }"
echo "  code HTTP=$CODE  temps=${TIME}s"

[[ "$CODE" == "200" ]] || { echo "  [KO] code HTTP attendu 200"; exit 1; }
grep -q "UrbanHub" "$TMP" || { echo "  [KO] page sans 'UrbanHub'"; exit 1; }
grep -q "data-env=\"$ENV\"" "$TMP" || { echo "  [KO] la page ne correspond pas à l'environnement $ENV"; exit 1; }
echo "  [OK] page UrbanHub de l'environnement $ENV"

echo "[SMOKE] GET $URL/health"
[[ "$(curl -fsS "$URL/health")" == "OK" ]] || { echo "  [KO] /health"; exit 1; }
echo "  [OK] /health = OK"

echo "Tests post-déploiement : SUCCÈS"

#!/usr/bin/env bash
# Construit l'archive de rendu anonymisée :
#   dist/EC04-P1_NomPrenom_UrbanHub_Cloud.zip
#     01_depot_git/   clone du dépôt avec son historique (.git)
#     02_preuves/     journaux et captures (dossier preuves/)
#     03_README.md    copie du README
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
NAME="${1:-EC04-P1_NomPrenom_UrbanHub_Cloud}"
OUT="$ROOT/dist/$NAME"

rm -rf "$OUT" "$OUT.zip"
mkdir -p "$OUT/02_preuves"

git clone -q "$ROOT" "$OUT/01_depot_git"
git -C "$OUT/01_depot_git" remote remove origin
cp README.md "$OUT/03_README.md"
cp -R preuves/. "$OUT/02_preuves/" 2>/dev/null || true
rm -f "$OUT/02_preuves/.gitkeep"

# Anonymisation des journaux : chemins personnels et nom d'utilisateur
for f in "$OUT"/02_preuves/*.log "$OUT"/02_preuves/*.txt; do
  [[ -f "$f" ]] || continue
  sed -i.bak -e "s#$HOME#~#g" -e "s#$(whoami)#candidat#g" "$f" && rm -f "$f.bak"
done
# Métadonnées des captures (si exiftool est installé)
command -v exiftool >/dev/null && exiftool -q -overwrite_original -all= "$OUT"/02_preuves/*.{png,jpg,jpeg} 2>/dev/null || true

echo "Identités présentes dans l'historique Git (doivent être anonymes) :"
git -C "$OUT/01_depot_git" log --format='  %an <%ae>' | sort -u
if grep -RIl -i -e "$(whoami)" "$OUT" --exclude-dir=.git >/dev/null 2>&1; then
  echo "ATTENTION : '$(whoami)' apparaît encore dans :"; grep -RIl -i -e "$(whoami)" "$OUT" --exclude-dir=.git
fi

(cd "$ROOT/dist" && zip -qr "$NAME.zip" "$NAME")
echo "Archive : dist/$NAME.zip"

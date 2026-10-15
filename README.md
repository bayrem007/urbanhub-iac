# UrbanHub — Déploiement Cloud reproductible (EC04 – Partie 1)

Microservice web **UrbanHub** (page d'accueil du jumeau numérique urbain) déployé sur une infrastructure décrite en code, sur deux environnements (`dev`, `prod`), avec tests automatiques et supervision.

```
terraform/   Instance, réseau, inventaire Ansible et cibles de supervision (générés)
ansible/     Playbook : nginx + page d'accueil (modèle Jinja2) + agent de métriques
envs/        dev.tfvars / prod.tfvars — seul fichier qui change entre environnements
scripts/     deploy.sh (commande unique), destroy.sh, package.sh, tests/
monitoring/  Prometheus (+ alertes), Blackbox exporter, Grafana (tableau de bord provisionné)
```

## 1. Plateforme retenue et justification

**Cloud simulé sur Docker**, piloté par Terraform via le fournisseur `kreuzwerker/docker`.

| Notion cloud | Équivalent simulé |
|---|---|
| API du fournisseur | API du démon Docker (`var.docker_host`) |
| Image (AMI) | `instance_image` = `ubuntu:22.04` |
| Type d'instance | `instance_type` (`small` = 512 Mo / 512 parts CPU, `medium` = 1 Go / 1024) |
| VPC / sous-réseau | `docker_network` dédié par environnement |
| Adresse publique | port publié sur l'hôte (`http_port`) |

Justification :
- **Reproductible et vérifiable par un tiers** sans compte cloud, carte bancaire ni identifiants : n'importe quel correcteur peut rejouer le déploiement.
- **Cycle court** : une instance est créée en quelques secondes, ce qui permet de rejouer la chaîne complète (dont la preuve d'échec) dans le temps de l'épreuve.
- **FinOps / impact écologique (C21)** : coût nul, aucune ressource oubliée qui tourne et facture ; les gabarits limitent mémoire et CPU comme un type d'instance réel.
- **Transposable** : le découpage (provider + variables + instance + sortie, inventaire généré, playbook) est identique sur AWS ; seul le fournisseur et la ressource d'instance changent (`aws_instance` + connexion SSH).

Limites assumées de la simulation :
- Ansible se connecte par le plugin `community.docker.docker` (équivalent d'un accès SSH).
- Il n'y a pas de `systemd` dans un conteneur : l'« activation au démarrage » est assurée par `update-rc.d` (module `service`, `enabled: true`) **et** par le script `/usr/local/bin/urbanhub-boot.sh` installé par Ansible, que la commande de démarrage de l'instance (définie dans Terraform) exécute à chaque redémarrage. Vérifiable avec `docker restart urbanhub-dev-web` puis `curl localhost:8081`.
- `node_exporter` lit `/proc` : le **réseau** mesuré est bien celui de l'instance, mais le **CPU et la mémoire** reflètent la machine hôte Docker (comme le ferait une VM qui partage son hyperviseur). Sur un vrai cloud, ces métriques seraient celles de la VM.

## 2. Prérequis

| Outil | Version testée / minimale |
|---|---|
| Docker Engine ou Docker Desktop (avec `docker compose` v2) | 24+ |
| Terraform | ≥ 1.5 |
| Ansible (`ansible-core`) | ≥ 2.15 |
| curl, bash | — |

Sous Windows : utiliser WSL2 (Ansible ne s'exécute pas nativement sous Windows).
Ports libres sur l'hôte : 8081, 8082 (application), 9101, 9102 (métriques), 9090 (Prometheus), 3000 (Grafana).

### Variables sensibles

Aucun secret n'est versionné. Elles sont documentées sans valeur dans `.env.example` :

```bash
cp .env.example .env
# puis renseigner GF_ADMIN_PASSWORD dans .env (mot de passe admin Grafana)
```

| Variable | Rôle | Obligatoire |
|---|---|---|
| `GF_ADMIN_PASSWORD` | mot de passe administrateur Grafana | oui |
| `TF_VAR_docker_host` | adresse de l'API Docker si différente de `unix:///var/run/docker.sock` | non |

## 3. Déploiement — commande unique

```bash
./scripts/deploy.sh dev     # environnement de développement
./scripts/deploy.sh prod    # environnement de production (même code, autre fichier de variables)
```

Enchaînement exécuté (toute étape en échec arrête la chaîne, message `ÉCHEC à l'étape …`) :

1. **Prérequis** : outils présents, démon Docker joignable.
2. **Tests pré-déploiement** (`scripts/tests/pre_deploy.sh`) :
   `terraform fmt -check`, `terraform validate`, `ansible-playbook --syntax-check`, recherche de secrets valorisés.
3. **Terraform** : workspace par environnement (états séparés), création du réseau et de l'instance ;
   génération de `ansible/inventory/<env>.ini` (nom et **adresse IP de l'instance injectés automatiquement**) et des cibles Prometheus.
4. **Ansible** (`ansible/site.yml`) : installation de nginx et de `prometheus-node-exporter`, page d'accueil depuis le modèle `index.html.j2`, démarrage et activation au boot, contrôle local de la page.
5. **Supervision** : `docker compose up -d` de Prometheus, Blackbox exporter et Grafana.
6. **Tests post-déploiement** (`scripts/tests/smoke_test.sh`) : HTTP 200, présence de « UrbanHub », **bon environnement** (`data-env="<env>"`), `/health` = `OK`.

Chaque exécution est journalisée dans `preuves/deploy_<env>_<horodatage>.log`.

Seul le fichier `envs/<env>.tfvars` diffère entre les environnements :

| Variable | dev | prod |
|---|---|---|
| `instance_type` | small | medium |
| `http_port` | 8081 | 8082 |
| `metrics_port` | 9101 | 9102 |

## 4. Vérifier que le service répond

```bash
curl -i http://localhost:8081/          # dev  : HTTP/1.1 200, badge « Environnement : dev »
curl -i http://localhost:8082/          # prod : HTTP/1.1 200, badge « Environnement : prod »
curl http://localhost:8081/health       # OK
terraform -chdir=terraform workspace select dev && terraform -chdir=terraform output
docker ps --filter label=project=urbanhub
```

## 5. Supervision

- Grafana : <http://localhost:3000> (utilisateur `admin`, mot de passe = `GF_ADMIN_PASSWORD`) → dossier *UrbanHub* → **UrbanHub — Supervision**.
  Panneaux : disponibilité, alertes actives, **processeur**, **mémoire**, **bande passante réseau** (entrant/sortant), **temps de réponse HTTP** (avec la ligne de seuil). Filtre par environnement.
- Prometheus : <http://localhost:9090/alerts> (règles dans `monitoring/prometheus/alerts.yml`).
- Collecte : `node_exporter` installé par Ansible sur l'instance (agent système) ; temps de réponse mesuré **de l'extérieur** par Blackbox exporter, comme le ressentirait un utilisateur.

### Alertes et justification des seuils

| Alerte | Condition | Justification |
|---|---|---|
| `UrbanHubDown` (critique) | `probe_success == 0` pendant **1 min** | 4 sondes consécutives en échec (une toutes les 15 s) : exclut un raté réseau isolé, tout en détectant une panne réelle en ~1 min. |
| `UrbanHubSlowResponse` | `probe_duration_seconds > 0,5 s` pendant **2 min** | La page statique répond en quelques millisecondes en fonctionnement normal : 500 ms représente une dégradation de plus de 50×, et reste sous le seuil d'environ 1 s où un utilisateur perçoit une interruption de sa navigation. La durée de 2 min évite les alertes sur un pic ponctuel (ex. démarrage). |
| `UrbanHubHighCPU` | CPU > **80 %** pendant **5 min** | Garde 20 % de marge pour absorber un pic ; 5 min distingue une saturation durable (à corriger : changer de gabarit) d'une rafale passagère (ex. `apt-get` pendant le déploiement). |

Déclencher l'alerte pour la preuve :

```bash
docker exec urbanhub-dev-web service nginx stop    # UrbanHubDown passe "pending" puis "firing" après ~1 min
./scripts/deploy.sh dev                             # le redéploiement rétablit le service (idempotence)
```

## 6. Preuve qu'un test en échec arrête la chaîne

```bash
# 1) Introduire une erreur dans le code d'infrastructure (référence à une variable inexistante)
printf 'output "test_echec" {\n  value = var.inexistante\n}\n' > terraform/zz_echec.tf
./scripts/deploy.sh dev     # => [TEST 3] terraform validate échoue, « ÉCHEC à l'étape tests pré-déploiement »
                            #    aucune commande terraform apply / ansible n'est exécutée

# 2) Corriger et relancer
rm terraform/zz_echec.tf
./scripts/deploy.sh dev     # => tous les tests passent, DÉPLOIEMENT dev RÉUSSI
```

## 7. Destruction de l'environnement

```bash
./scripts/destroy.sh dev                     # détruit l'instance et le réseau dev
./scripts/destroy.sh prod --with-monitoring  # détruit prod + la pile de supervision
```

Le script vérifie qu'aucun conteneur de l'environnement ne subsiste. L'image `ubuntu:22.04` est conservée en cache local (`keep_locally`) ; la supprimer avec `docker rmi ubuntu:22.04` si besoin.

## 8. Livrable

`./scripts/package.sh` produit `dist/EC04-P1_NomPrenom_UrbanHub_Cloud.zip` (clone du dépôt avec historique, preuves avec chemins personnels masqués, README) et affiche les identités présentes dans l'historique Git pour contrôle d'anonymat.

## 9. Déclaration d'usage de l'IA

### 9.1 Outils utilisés
- **Claude (Anthropic), modèle Claude Opus 5.5**, plateforme **WEB** (application claude.ai, mode agent générant des fichiers).
- [À compléter si utilisé : autre outil, ex. Copilot dans l'IDE]

### 9.2 Périmètre d'utilisation
- Génération initiale de la structure du dépôt et des fichiers : Terraform, playbook et modèles Ansible, scripts `deploy.sh` / `destroy.sh` / `package.sh` et tests, configuration Prometheus / Blackbox / Grafana, trame de ce README.
- [À compléter : débogage effectué avec l'IA pendant l'épreuve, le cas échéant]

### 9.3 Démarche de Context Engineering / prompts majeurs
1. Fourniture du **sujet complet de l'épreuve (PDF)** comme contexte, avec la consigne de produire un dépôt couvrant les parties A et B et les contraintes de livraison (anonymat, secrets, arborescence du ZIP).
2. Contraintes imposées : plateforme exécutable sur un poste personnel sans compte cloud, une commande unique, inventaire **généré** par Terraform, seul le fichier de variables changeant entre environnements.
3. [À compléter : prompts de correction formulés après les premières exécutions, ex. messages d'erreur fournis à l'IA]

### 9.4 Audit des réponses : validé / modifié / rejeté
- **Choix de plateforme (Docker simulé) — validé** : couvre toutes les exigences sans secret cloud ni coût, et la destruction est vérifiable. Limites (pas de systemd, métriques CPU/mémoire de l'hôte) identifiées et documentées au §1 plutôt que masquées.
- **Inventaire généré par `local_file` + `templatefile`** — validé : l'IP provient de `docker_container.web.network_data[0].ip_address`, aucune saisie manuelle ; vérifié en lisant `ansible/inventory/dev.ini` après `apply`.
- **Workspaces Terraform par environnement** — validé : sans eux, un `apply` avec `prod.tfvars` aurait *remplacé* l'instance dev (même état) au lieu d'en créer une seconde.
- **Sécurité / secrets** — vérifié : le seul secret (mot de passe Grafana) passe par `GF_ADMIN_PASSWORD`, `.env` est dans `.gitignore`, `docker compose` refuse de démarrer si la variable est absente (`${…:?}`), et un test bloque tout secret valorisé dans le dépôt.
- **Arrêt de la chaîne sur échec** — vérifié : `set -Eeuo pipefail` + `trap ERR` ; démontré au §6 (preuves dans `02_preuves`).
- **Script de boot** — vérifié : idempotent (`pgrep` avant tout démarrage), `changed_when` pour qu'Ansible ne signale un changement que si un service a réellement été démarré.
- [À compléter : éléments corrigés ou rejetés pendant l'épreuve, ex. erreur rencontrée à l'exécution et correction apportée]

# Quête 8 — Docker : analyse de vulnérabilité avec Trivy

## Travail réalisé

J’ai scanné l’image `demo-api:multi` construite depuis `api/Dockerfile.multi` avec Trivy. Le binaire n’étant pas installé sur ma machine, j’ai utilisé l’image officielle `aquasec/trivy:latest` (Trivy 0.76.1). J’ai limité le rapport aux vulnérabilités avec `--scanners vuln` et conservé les sorties complètes dans [`scan-avant.txt`](scan-avant.txt) et [`scan-apres.txt`](scan-apres.txt).

Le premier scan sépare bien les deux familles :

| Section | Avant correction | Après correction |
|---|---:|---:|
| Paquets OS (Alpine 3.20.3 → 3.24.3) | 21 CVE (19 HIGH, 2 CRITICAL) | 0 |
| Dépendances Node | 34 CVE (31 HIGH, 3 CRITICAL) | 0 |
| **Total HIGH/CRITICAL** | **55** | **0** |

`npm audit` remontait de son côté 4 vulnérabilités dans les dépendances applicatives (1 critique, 1 haute, 2 modérées).

J’ai corrigé :

- la base `node:22.11-alpine` (Alpine 3.20.3) en passant à `node:22.23.4-alpine3.24` (Alpine 3.24.3) dans les deux étapes du build ;
- les dépendances applicatives avec `npm audit fix` dans `api/` : `express` 4.22.3, `body-parser` 1.20.9, `proxy-addr` 2.0.8 et `qs` 6.16.1, avec `package-lock.json` mis à jour ;
- les dépendances embarquées par le CLI `npm` : `npm` et `corepack` sont retirés du stage `runtime`, car l’image finale n’en a pas besoin. Cela supprime les 10 HIGH qui restaient dans `/usr/local/lib/node_modules/npm`.

Aucun `.trivyignore` n’est nécessaire : après correction, Trivy ne remonte plus aucune CVE HIGH/CRITICAL, y compris sans `--ignore-unfixed`.

J’ai ajouté `.github/workflows/ci.yml`. À chaque push, sur les branches comme sur les tags `v*`, la CI construit `api/Dockerfile.multi`, charge l’image `demo-api:ci` et lance `aquasecurity/trivy-action` avec `severity: CRITICAL,HIGH`, `ignore-unfixed: true` et `exit-code: '1'`. La gate est configurée pour s’appliquer partout, y compris sur les tags de publication.

## Commandes et vérifications

### Scan initial

```bash
docker build -f api/Dockerfile.multi -t demo-api:multi ./api
docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
  aquasec/trivy:latest image --scanners vuln --severity HIGH,CRITICAL \
  --no-progress demo-api:multi | tee scan-avant.txt
```

Extrait observé :

```text
demo-api:multi (alpine 3.20.3)
==============================
Total: 21 (HIGH: 19, CRITICAL: 2)

Node.js (node-pkg)
==================
Total: 34 (HIGH: 31, CRITICAL: 3)
```

### Correction des dépendances

```bash
cd api
npm audit fix
npm audit --omit=dev
```

`npm audit fix` a mis à jour le lockfile et `npm audit --omit=dev` s’est terminé par :

```text
found 0 vulnerabilities
```

### Scan après correction

```bash
docker build -f api/Dockerfile.multi -t demo-api:multi ./api
docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
  aquasec/trivy:latest image --scanners vuln --severity HIGH,CRITICAL \
  --ignore-unfixed --no-progress demo-api:multi | tee scan-apres.txt
```

Extraits observés :

```text
│ demo-api:multi (alpine 3.24.3)                        │  alpine  │        0        │
│ app/node_modules/express/package.json                 │ node-pkg │        0        │
│ app/node_modules/pg/package.json                      │ node-pkg │        0        │
```

Le rapport complet ne contient plus aucune ligne de vulnérabilité HIGH/CRITICAL. J’ai aussi lancé un scan JSON sans `--ignore-unfixed`, puis compté les résultats : les deux familles sont à zéro.

```bash
docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
  aquasec/trivy:latest image --scanners vuln --severity HIGH,CRITICAL \
  --format json --no-progress demo-api:multi > /tmp/scan-after-all.json
```

```text
Comptage des résultats :
demo-api:multi (alpine 3.24.3) os-pkgs 0
Node.js lang-pkgs 0
```

### Vérification de l’image

```bash
docker run -d --name demo-api-trivy-check -p 127.0.0.1:18080:3000 demo-api:multi
sleep 18
curl -s -w '\nHTTP %{http_code}\n' http://127.0.0.1:18080/health
docker inspect demo-api-trivy-check --format '{{.State.Health.Status}}'
docker exec demo-api-trivy-check sh -c 'command -v npm || echo "npm absent"'
docker rm -f demo-api-trivy-check
```

Sorties observées :

```text
{"status":"UP"}
HTTP 200
healthy
npm absent
```

## Preuve de la gate CI

Le workflow complet est dans [`.github/workflows/ci.yml`](.github/workflows/ci.yml). L’étape qui bloque une régression est :

```yaml
- name: Scanner l'image avec Trivy
  uses: aquasecurity/trivy-action@0.36.0
  with:
    image-ref: demo-api:ci
    scanners: vuln
    severity: CRITICAL,HIGH
    ignore-unfixed: true
    exit-code: '1'
    format: table
```

J’ai reproduit l’étape de build de la CI localement ; l’image `demo-api:ci` s’est chargée sans erreur :

```bash
docker buildx build --load -f api/Dockerfile.multi -t demo-api:ci ./api
```

J’ai ensuite reproduit les deux états de la gate avec la même commande Trivy et `--exit-code 1`.

Régression volontaire, en reconstruisant une image temporaire avec l’ancienne base `node:22.11-alpine` :

```bash
sed 's#node:22.23.4-alpine3.24#node:22.11-alpine#g' api/Dockerfile.multi > /tmp/Dockerfile.regression
docker build -f /tmp/Dockerfile.regression -t demo-api:regression ./api
docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
  aquasec/trivy:latest image --scanners vuln --severity HIGH,CRITICAL \
  --ignore-unfixed --exit-code 1 --no-progress demo-api:regression
```

Résultat observé : code de sortie `1`, avec `Total: 21 (HIGH: 19, CRITICAL: 2)`. La CI serait rouge.

Image corrigée :

```bash
docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
  aquasec/trivy:latest image --scanners vuln --severity HIGH,CRITICAL \
  --ignore-unfixed --exit-code 1 --no-progress demo-api:multi
```

Résultat observé : code de sortie `0`, avec `demo-api:multi (alpine 3.24.3)` à `0` vulnérabilité. La CI serait verte.

Les deux runs GitHub Actions seront à ajouter après le push : je n’ai pas poussé ni créé de tag à la place de l’utilisateur.

## Captures d’écran

Aucune capture n’a été fournie pour cette quête. Les preuves sont les rapports [`scan-avant.txt`](scan-avant.txt) et [`scan-apres.txt`](scan-apres.txt), ainsi que les sorties ci-dessus. Les captures des deux runs CI pourront être ajoutées en même temps que les liens de publication.

## Liens de publication

- Dépôt GitHub : [ynov-x-anthony/GARRIGUES_hugo_demo-api](https://github.com/ynov-x-anthony/GARRIGUES_hugo_demo-api)
- Branche de rendu : [`quest/docker-8-analyse-trivy`](https://github.com/ynov-x-anthony/GARRIGUES_hugo_demo-api/tree/quest/docker-8-analyse-trivy)
- Workflow : [`.github/workflows/ci.yml`](.github/workflows/ci.yml)
- Run rouge (régression volontaire) : à compléter après le push.
- Run vert (image corrigée) : à compléter après le push.

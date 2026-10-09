set -e

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NETWORK="demo-volumes-hugo-garrigues"

cleanup() {
  docker rm -f demo-api demo-db >/dev/null 2>&1 || true
  docker network rm "$NETWORK" >/dev/null 2>&1 || true
}
trap cleanup EXIT

wait_for_db() {
  until docker exec demo-db pg_isready -U demo >/dev/null 2>&1; do
    sleep 1
  done
  echo "PostgreSQL est prêt."
}

wait_for_api() {
  until curl -fsS http://localhost:8080/ready >/dev/null 2>&1; do
    sleep 1
  done
  echo "L'API est prête."
}

start_db() {
  docker run -d --name demo-db \
    --network "$NETWORK" \
    -v demo_pgdata:/var/lib/postgresql/data \
    -v "$ROOT_DIR/db/init.sql:/docker-entrypoint-initdb.d/init.sql:ro" \
    -e POSTGRES_USER=demo \
    -e POSTGRES_PASSWORD=demo \
    -e POSTGRES_DB=demo \
    postgres:16-alpine
  wait_for_db
}

start_api() {
  docker run -d --name demo-api \
    --network "$NETWORK" \
    -p 8080:3000 \
    -e PGHOST=demo-db \
    -e PGUSER=demo \
    -e PGPASSWORD=demo \
    -e PGDATABASE=demo \
    demo-api:1.0
  wait_for_api
}

docker rm -f demo-api demo-db >/dev/null 2>&1 || true

docker build -t demo-api:1.0 ./api
docker volume create demo_pgdata
docker network create "$NETWORK"

echo "Démarrage initial de PostgreSQL et de l'API..."
start_db
start_api

echo "Ajout du produit :"
curl -fsS -X POST -H 'content-type: application/json' \
  -d '{"name":"Casquette Démo","price_cents":1200}' \
  http://localhost:8080/products
echo

echo "Produits avant recréation de PostgreSQL :"
BEFORE_PRODUCTS="$(curl -fsS http://localhost:8080/products)"
printf '%s\n' "$BEFORE_PRODUCTS"

echo "Suppression des conteneurs, puis recréation de PostgreSQL avec demo_pgdata..."
docker rm -f demo-api demo-db
start_db
start_api

echo "Produits après recréation de PostgreSQL :"
FINAL_PRODUCTS="$(curl -fsS http://localhost:8080/products)"
printf '%s\n' "$FINAL_PRODUCTS"

if [[ "$FINAL_PRODUCTS" != *"Casquette Démo"* ]]; then
  echo "ERREUR : Casquette Démo n'est pas présent après la recréation." >&2
  exit 1
fi

echo "Volume conservé :"
docker volume ls | grep demo_pgdata

echo ""
echo "Casquette Démo a bien survécu à la suppression ainsi que la recréation du conteneur de base."
echo ""
echo  "N'oublie pas de nettoyer en fin de script avec docker volume rm demo_pgdata."
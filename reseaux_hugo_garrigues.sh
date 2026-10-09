#!/usr/bin/env bash
set -e

docker build -t demo-api:1.0 ./api
docker network create demo_front
docker network create demo_back

docker run -d --name demo-db \
  --network demo_back \
  -v "$(pwd)/db/init.sql:/docker-entrypoint-initdb.d/init.sql:ro" \
  -e POSTGRES_USER=demo \
  -e POSTGRES_PASSWORD=demo \
  -e POSTGRES_DB=demo \
  postgres:16-alpine

until docker exec demo-db pg_isready -U demo; do
  sleep 1
done

docker run -d --name demo-api \
  --network demo_front \
  -p 8080:3000 \
  -e PGHOST=demo-db \
  -e PGUSER=demo \
  -e PGPASSWORD=demo \
  -e PGDATABASE=demo \
  demo-api:1.0
docker network connect demo_back demo-api

echo "Résolution DNS depuis l'API :"
docker exec demo-api getent hosts demo-db

echo "Test depuis demo_front seul (échec attendu) :"
if docker run --rm --network demo_front alpine nc -zv -w 3 demo-db 5432; then
  echo "ERREUR : demo-db est joignable depuis demo_front."
  exit 1
else
  echo "Échec attendu : demo-db n'est pas joignable depuis demo_front seul."
fi

echo "Adresses IPv4 de demo-db :"
docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAMConfig}} {{.IPAddress}}{{"\n"}}{{end}}' demo-db

echo "Adresses IPv4 de demo-api :"
docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAMConfig}} {{.IPAddress}}{{"\n"}}{{end}}' demo-api

echo "Produits :"
curl -s localhost:8080/products
echo

docker rm -f demo-api demo-db
docker network rm demo_front demo_back

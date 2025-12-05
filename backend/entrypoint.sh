#!/bin/sh
set -e
echo "Waiting for database to be ready..."
# wait-for-postgres loop
retries=0
until pg_isready -q -d "$DATABASE_URL"; do
  retries=$((retries+1))
  echo "Postgres is unavailable - sleeping (attempt $retries)..."
  sleep 2
  if [ $retries -gt 60 ]; then
    echo "Postgres did not become available in time, exiting."
    exit 1
  fi
done
echo "Postgres is ready - running migrations"
if [ -n "$DATABASE_URL" ]; then
  psql "$DATABASE_URL" -f migrations/001_create_schema.sql || true
  psql "$DATABASE_URL" -f migrations/002_refresh_tokens.sql || true
  psql "$DATABASE_URL" -f seeds/001_seed_demo.sql || true
else
  echo "DATABASE_URL not set, skipping migrations"
fi
echo "Starting server..."
exec node server.js

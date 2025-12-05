# Fitness Social — Express Backend (with JWT auth)

1. Copy .env.example to .env and set DATABASE_URL and JWT_SECRET
2. npm install
3. Run migrations: psql $DATABASE_URL -f migrations/001_create_schema.sql
4. Seed demo data: psql $DATABASE_URL -f seeds/001_seed_demo.sql
5. npm start


Docker:
Run `docker-compose up --build` at project root. Backend will connect to Postgres service.

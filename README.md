# Fitness Social — Starter (Fitness/gym social app)

This repository contains a starter Expo frontend and an Express backend with JWT auth, refresh tokens, Docker, and migrations.

## Quickstart (Docker)

1. Copy `.env.example` in `backend/` to `backend/.env` and (optionally) update `JWT_SECRET`.
2. Run: `docker-compose up --build`
3. Backend will be available at `http://localhost:4000` and Postgres at `localhost:5432`.
   The entrypoint will run migrations and seed demo data automatically on container startup.

## Quickstart (local)

See `backend/README.md` and `frontend/README.md`.

# Pockie Saints Remake — backend

Laravel 12 JSON API for accounts, auth tokens (Sanctum personal access tokens)
and characters. The contract is [`docs/api.md`](../docs/api.md).

## Requirements

- PHP 8.3 with `pdo_sqlite` (or `pdo_mysql` / `pdo_pgsql`)
- Composer 2

## Setup

```bash
cd backend
composer install
cp .env.example .env
php artisan key:generate
touch database/database.sqlite
php artisan migrate
```

## Run

```bash
php artisan serve        # http://localhost:8000
```

The API lives under `http://localhost:8000/api`, which is the game client's
default API base URL.

## Test

```bash
php artisan test         # PHPUnit, in-memory SQLite
./vendor/bin/pint        # code style
```

## Configuration

| Env var | Default | Notes |
|---|---|---|
| `DB_CONNECTION` | `sqlite` | Set to `mysql` or `pgsql` and fill `DB_HOST`, `DB_PORT`, `DB_DATABASE`, `DB_USERNAME`, `DB_PASSWORD`. |
| `CORS_ALLOWED_ORIGINS` | `*` | Comma-separated list of origins allowed to call `api/*` (e.g. `https://play.example.com`). The Godot web build runs on a different origin, so dev allows all. |

Game rules (birth sign ids, max characters per account) are in
`config/game.php`. Birth sign ids must match `game/data/zodiac_signs.json`.

Auth routes (`/api/auth/register`, `/api/auth/login`) are rate-limited to 10
requests per minute per IP.

## Endpoints

| Method | Path | Auth |
|---|---|---|
| POST | `/api/auth/register` | — |
| POST | `/api/auth/login` | — |
| POST | `/api/auth/logout` | bearer |
| GET | `/api/me` | bearer |
| GET | `/api/characters` | bearer |
| POST | `/api/characters` | bearer |
| GET | `/api/characters/{id}` | bearer |
| DELETE | `/api/characters/{id}` | bearer |

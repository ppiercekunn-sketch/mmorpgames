# Backend API contract (M0)

Base URL: `/api`. JSON in and out. Auth uses bearer tokens
(`Authorization: Bearer <token>`, Laravel Sanctum personal access tokens).
Errors use Laravel's default shape: `422` with `{ "message": "...", "errors": { "field": ["..."] } }`,
`401` with `{ "message": "Unauthenticated." }`.

## Auth

`POST /api/auth/register`
```json
{ "username": "alice", "email": "alice@example.com", "password": "secret123", "password_confirmation": "secret123" }
```
→ `201`
```json
{ "token": "1|abc...", "account": { "id": 1, "username": "alice", "email": "alice@example.com" } }
```
Rules: username 3–20 chars, letters/digits/underscore, unique; email unique;
password min 8, confirmed.

`POST /api/auth/login`
```json
{ "login": "alice", "password": "secret123" }
```
`login` is a username or email. → `200`, same shape as register. Wrong
credentials → `422` with `errors.login`.

`POST /api/auth/logout` (auth) → `204`, revokes the current token.

`GET /api/me` (auth) → `200` `{ "account": { ... } }`

## Characters

Character object:
```json
{
  "id": 7,
  "name": "Aldric",
  "class": "warrior",
  "birth_sign": "aries",
  "level": 1,
  "xp": 0,
  "gold": 0,
  "created_at": "2026-10-27T12:00:00Z"
}
```

`GET /api/characters` (auth) → `200` `{ "characters": [ ... ] }` (own characters only)

`POST /api/characters` (auth)
```json
{ "name": "Aldric", "birth_sign": "aries" }
```
→ `201` `{ "character": { ... } }`. Rules: name 3–16 chars, letters/digits,
globally unique (case-insensitive); `birth_sign` one of the 12 ids in
`game/data/zodiac_signs.json`; class is always `warrior` in the MVP; at most
3 characters per account.

`GET /api/characters/{id}` (auth) → `200` `{ "character": { ... } }`, `404` if not yours.

`DELETE /api/characters/{id}` (auth) → `204`.

Saving progress (`PUT /api/characters/{id}/state`) arrives in M2.

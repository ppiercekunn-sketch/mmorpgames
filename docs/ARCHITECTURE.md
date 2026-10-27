# Architecture & conventions (MVP, M0–M1)

```
game/      Godot 4.3 project (GDScript only, GL Compatibility renderer for web)
backend/   Laravel API: accounts, auth tokens, characters
docs/      Design and contracts (this file, api.md)
.github/   CI workflows
```

## Godot project layout and ownership

Each folder has one owner so work can proceed in parallel. Touch another
folder only through the contracts below; if a contract must change, change it
here too.

| Folder | Owns |
|---|---|
| `game/core/` | Shared contracts: `Actor`, `Stats`, `Events`, `GameData`, `Session`. Change rarely. |
| `game/scenes/` | `boot.tscn` (entry) and `game.tscn` (integration scene that assembles everything). |
| `game/world/` | Isometric tile map, zones, navigation, click-to-move input, camera, spawn markers. |
| `game/combat/` | Player character, damage formula, skills, cooldowns, hotbar, targeting, enemies + AI, combat HUD. |
| `game/progression/` | XP and levels, loot drops and pickup, inventory, equipment, item UI, starter pet. |
| `game/ui/login/`, `game/net/`, `game/web/`, `game/export_presets.cfg` | Login, character creation, API client, web shell / loading screen, export presets. |
| `game/data/` | JSON data tables (one file per table, keyed by id). Each table has one owner; see below. |
| `game/tests/` | Headless tests: `test_<area>_*.gd`, extending `TestCase`. |

## Rules

- **Server-shareable logic** (formulas, cooldown math, XP curves, loot rolls,
  inventory ops) lives in plain scripts or `Resource`s with no scene or
  autoload dependencies, so the M2 headless server reuses them. Take random
  number generators as parameters (`RandomNumberGenerator`) so tests are
  deterministic.
- **No direct cross-system references.** Systems communicate through the
  `Events` autoload (`game/core/events.gd`) and the node groups listed below.
- **Build nodes in code where practical.** Keep `.tscn` files small (a root
  node + script, a few children). Omit `uid=` attributes in hand-written
  scenes. Placeholder art is drawn with `_draw()`, `Polygon2D` or
  `ColorRect` — no binary assets yet. Real art is added through Git LFS.
  Character images (`art/characters/<id>.png`, see `game/art/README.md`)
  replace an actor's placeholder body when present: actors call
  `CharacterSprite.try_attach(self, id, height)` (`core/character_sprite.gd`,
  which loads via `core/character_art.gd`) and skip their placeholder
  drawing when it returns a node; HP bars, labels and rings stay in `_draw()`.
- **Indentation:** tabs. Typed GDScript (`var x: int`, `-> void`). Lint with
  `gdlint` and parse with `gdparse` (gdtoolkit 4.x).
- **Tests:** `godot --headless --path game --script res://tests/run_tests.gd`.
  Autoloads are not available inside tests; test plain scripts.

## Node groups (the runtime contract)

| Group | Members | Used by |
|---|---|---|
| `player` | The local player `Actor` (exactly one) | enemies, pet, progression, camera |
| `enemies` | Every enemy `Actor` | targeting, pet AI |
| `pets` | Pet `Actor`s | — |
| `enemy_spawns` | `Marker2D` placed by world. Meta: `enemy_id` (String), `count` (int), `radius` (float) | enemy spawner (combat) |
| `player_spawn` | One `Marker2D` where the player appears | game scene |
| `clickable` | Nodes with a pickable `Area2D` that handle their own clicks (loot bags) | zone click handler |
| `progression`, `progression_ui` | The Progression node and its UI | game scene, UI binding |

**Clicks.** Zone handles left clicks in `_unhandled_input`, but first runs a
physics point query at the cursor: if it hits an area or body belonging to a
node in `enemies` or `clickable`, it leaves the click alone so that node's
`Area2D.input_event` handles it. Enemy click areas use physics layer 4,
loot bags layer 10. The game scene turns on `Viewport.physics_object_picking`.

**Levels.** Progression owns `stats.level` and attribute growth (including
applying a saved level on load). Combat reads the level but never sets it.
`Session.character.xp` is XP within the current level. Gold uses item id
`"gold"` in `Events.loot_dropped` / `item_picked_up`.

**API URL.** Defaults to `http://localhost:8000/api`. Web builds take
`?api=<url>` (or `window.POCKIE_API_URL`); desktop takes `-- --api=<url>`.

Actors are added as children of the zone's **entities root**
(`Zone.get_entities_root()`, a y-sorted `Node2D`).

## Integration contracts

**World — `res://world/zone.tscn`, root script `Zone` (`world/zone.gd`)**
- `get_entities_root() -> Node2D`
- `get_player_spawn() -> Vector2`
- `get_navigation_map() -> RID`
- Left click on walkable ground emits `Events.ground_clicked(world_pos)` unless
  the click hit an enemy or UI.
- Camera: `world/follow_camera.gd` (`Camera2D`), `follow(target: Node2D)`.

**Combat — `res://combat/player/player.tscn` (`Player extends Actor`)**
- Joins group `player`. Listens to `Events.ground_clicked` and moves.
- `current_target: Actor`, set by clicking an enemy; emits `Events.target_changed`.
- `res://combat/enemies/enemy_spawner.gd` (`EnemySpawner extends Node`):
  `setup(entities_root: Node2D)` — spawns enemies at every `enemy_spawns`
  marker and respawns them after death.
- `res://combat/ui/combat_hud.tscn` (`CanvasLayer`): HP/MP, hotbar, target frame.
- Enemy data: `data/enemies.json` (fields include `xp` and `loot_table`).

**Progression — `res://progression/progression.gd` (`Progression extends Node`)**
- `setup(player: Actor, entities_root: Node2D)`.
- Awards XP on `Events.actor_died` for enemies, levels the player
  (`player.stats.level`), drops loot from `data/loot_tables.json`, owns the
  inventory and equipment, and writes gear bonuses into
  `player.stats.bonuses` (key prefix-free; it rebuilds the full dict from
  birth sign + gear each time).
- Spawns the starter pet (`res://progression/pet/pet.tscn`) next to the player.
- `res://progression/ui/progression_ui.tscn` (`CanvasLayer`): XP bar, gold,
  inventory/equipment window (toggle with `toggle_inventory`, key I).
- Data: `data/items.json`, `data/loot_tables.json`, `data/pets.json`,
  `data/xp_curve.json`.

**Login — `res://ui/login/login.tscn`**
- Register / log in / pick or create a character (name + birth sign), fill
  `Session`, then `change_scene_to_file("res://scenes/game.tscn")`.
- "Play offline" button calls `Session.start_offline()`.

## Data table owners

| File | Owner |
|---|---|
| `zodiac_signs.json` | core |
| `skills.json`, `enemies.json` | combat |
| `items.json`, `loot_tables.json`, `pets.json`, `xp_curve.json` | progression |

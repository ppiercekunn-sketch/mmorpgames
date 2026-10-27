# Architecture & conventions (MVP, M0–M1)

The game is currently **single-player and offline with local save slots**.
There are no accounts in the game flow. The Laravel backend, `game/net/` and
`game/ui/login/` stay in the repo for a later online mode but nothing routes
to them.

```
game/      Godot 4.3 project (GDScript only, GL Compatibility renderer for web)
backend/   Laravel API: accounts, auth tokens, characters (unused by the game for now)
docs/      Design and contracts (this file, api.md)
.github/   CI workflows
```

## Godot project layout and ownership

Each folder has one owner so work can proceed in parallel. Touch another
folder only through the contracts below; if a contract must change, change it
here too.

| Folder | Owns |
|---|---|
| `game/core/` | Shared contracts: `Actor`, `Stats`, `Events`, `GameData`, `Session`, `SaveGame` (save format + slot files). Change rarely. |
| `game/scenes/` | `boot.tscn` (entry), `game.tscn` (integration scene that assembles everything) and `save_manager.gd` (restore + autosave, created by `game.gd`). |
| `game/world/` | Isometric tile map, zones, navigation, click-to-move input, camera, spawn markers. |
| `game/combat/` | Player character, damage formula, skills, cooldowns, hotbar, targeting, enemies + AI, combat HUD. |
| `game/progression/` | XP and levels, loot drops and pickup, inventory, equipment, item UI, starter pet. |
| `game/ui/title/`, `game/ui/pause_menu.gd` | Title screen with the save slots and new-game character creation; the in-game pause menu. |
| `game/ui/login/`, `game/net/`, `game/web/`, `game/export_presets.cfg` | Online login / character API client (unused for now; `login_theme.gd` and `login_background.gd` are shared by the title screen and pause menu), web shell / loading screen, export presets. |
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

**API URL** (online flow only, unused for now). Defaults to `http://localhost:8000/api`. Web builds take
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

**Boot — `res://scenes/boot.tscn`**
- No arguments: goes to the title screen.
- `-- --offline`: `Session.start_offline()` and straight into a fresh,
  **unsaved** game (CI smoke-boots both ways).

**Title — `res://ui/title/title.tscn`** (`ui/title/title.gd`, built in code)
- Three save slot cards. Empty: New Game. Filled: name, level, sign,
  playtime, last saved, Continue, Delete (with a confirm dialog). A file that
  cannot be read shows as "Damaged save" with Delete.
- New Game: name (3–16 letters/digits, `SaveGame.validate_character_name`)
  and one of the 12 birth signs (`zodiac_signs`), class fixed to Warrior,
  then `Session.start_new_game(slot, name, sign)`.
- Continue: `Session.start_from_save(slot, SaveGame.read_slot(slot))`.
- Either way it then changes to `res://scenes/game.tscn`.

**Session** (`core/session.gd`): `character` (`{id, name, class,
birth_sign, level, xp, gold}`), `save_slot` (1–3, or -1 for an unsaved
game) and `pending_save` (the parsed save for the game scene to restore; the
game scene clears it once read).

**Saves — `core/save_game.gd` (`SaveGame`, pure, no autoloads)**
- Files: `user://saves/slot_<n>.json`, n = 1..3. On the web export `user://`
  is IndexedDB, so saves live in that browser.
- Format (version 1):
  ```
  { "version": 1, "saved_at": <unix s>, "playtime": <s>,
    "character": {"name", "class": "warrior", "birth_sign", "level", "xp", "gold"},
    "zone": {"id", "position": {"x", "y"} | null},
    "vitals": {"hp", "mp"},            // -1 = full
    "inventory": {"slots": [{} | {"id", "qty"}], "equipment": {slot: item_id}},
    "pet": {"id", "level", "xp"} | {} }
  ```
- `SaveGame.parse()` migrates older versions (v0 = the flat
  `Session.character` dict), rejects saves from newer versions or with no
  valid character, and replaces bad field values with defaults.
  `Inventory.set_state()` then drops unknown item ids.
- Writes are atomic: write `.tmp`, read it back, keep the old file as
  `.bak`, rename `.tmp` over the slot file. Reading tries main, `.tmp`, `.bak`.
- Bump `SaveGame.VERSION` and add a migration step whenever the format changes.

**Save manager — `scenes/save_manager.gd`** (created by `game.gd`)
- `start_position(zone, save)`: the saved position if it is in this zone and
  `zone.is_walkable(pos)`, else the zone spawn.
- `setup(...)` applies the save through `Progression.apply_save_data()` plus
  HP/MP, then autosaves to `Session.save_slot`: every 60 s of unpaused play,
  on player level up, on `NOTIFICATION_WM_CLOSE_REQUEST`, on quit to title,
  and (throttled, no toast) on app focus loss. Shows a "Saved" toast.
  Unsaved games (`save_slot == -1`) never write.
- `Progression.get_save_data()` / `apply_save_data(data)` cover level, XP,
  gold, bag, equipment and pet; the save manager adds name, sign, zone,
  position, vitals and playtime.

**Pause menu — `ui/pause_menu.gd`** (`CanvasLayer`, created by `game.gd`)
- Esc toggles it and pauses the tree. Resume / Save / Quit to title (saves
  first). It is added before the other systems so Esc closes the inventory
  window first when that is open.

## Data table owners

| File | Owner |
|---|---|
| `zodiac_signs.json` | core |
| `skills.json`, `enemies.json` | combat |
| `items.json`, `loot_tables.json`, `pets.json`, `xp_curve.json` | progression |

# Pockie Saints Remake

Browser MMORPG vertical slice: pick a birth sign, fight as a Warrior with a pet, reach level 10, clear one dungeon.

For now the game is single-player and offline, with three local save slots. No account or backend is needed to play.

- `game/`: Godot 4.3 client (and later the headless server), GDScript only
- `backend/`: Laravel API for accounts and characters (kept for a later online mode, not used by the game yet)
- `docs/ARCHITECTURE.md`: folder ownership, runtime contracts, conventions
- `docs/api.md`: backend API contract

## Run the game

Open `game/project.godot` in Godot 4.3 and press Play (F5). No backend is needed.

The title screen shows three save slots: start a New Game (name + birth sign) or Continue / Delete an existing save. The game autosaves every minute, on level up and when you quit; Esc opens the pause menu (Resume / Save / Quit to title). Saves are JSON files in `user://saves/` (on Linux `~/.local/share/godot/app_userdata/Pockie Saints Remake/saves/`; in the browser they are stored in IndexedDB).

To skip the title screen and start a fresh, unsaved game: `godot --path game -- --offline`.

Tests: `godot --headless --path game --script res://tests/run_tests.gd`
Lint: `pip install gdtoolkit==4.3.3 "setuptools<81" && gdlint game && gdparse $(find game -name '*.gd')`

# Pockie Saints Remake

Browser MMORPG vertical slice: log in, pick a birth sign, fight as a Warrior with a pet, reach level 10, clear one dungeon.

- `game/`: Godot 4.3 client (and later the headless server), GDScript only
- `backend/`: Laravel API for accounts and characters
- `docs/ARCHITECTURE.md`: folder ownership, runtime contracts, conventions
- `docs/api.md`: backend API contract

## Run the game

Open `game/project.godot` in Godot 4.3. To skip login, run with `-- --offline`.

Tests: `godot --headless --path game --script res://tests/run_tests.gd`
Lint: `pip install gdtoolkit==4.3.3 && gdlint game && gdparse $(find game -name '*.gd')`

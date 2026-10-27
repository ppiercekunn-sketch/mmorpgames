# Character art

Characters are drawn from still images in `art/characters/` when present.
When an image is missing, the game draws the old placeholder shapes, so
any subset of images works.

## Files

| File | Character | On-screen height |
|---|---|---|
| `characters/warrior.png` | Player (Warrior) | 64 px (`Player.ART_HEIGHT`) |
| `characters/slime.png` | Green Slime | 36 px |
| `characters/wolf.png` | Grey Wolf | 48 px |
| `characters/bandit.png` | Road Bandit | 64 px |
| `characters/field_boss.png` | Bandit Warlord | 110 px |
| `characters/star_pup.png` | Star Pup (pet) | 34 px |

The file name is the id from `data/enemies.json` / `data/pets.json`. Change
the on-screen height with each entry's `sprite_height` field.

## Image requirements

- **One character per image**, full body, nothing else in the frame.
- **3/4 isometric view, facing south-east** (towards the bottom-right of
  the screen). The game mirrors it when the character walks left.
- **Transparent background** is best. A plain solid background (or a fake
  checkerboard) also works if you run `prepare_art.py`, below.
- **Feet at the bottom-center** of the image. Height is measured from the
  feet to the top of the image, so trim empty space (the script does this).
- **512x512 PNG** after cropping. Larger files work too; the game trims
  transparent borders and downsizes them when it loads them, but large files
  load slower in the browser.
- No animation frames are needed yet. The game adds breathing, a walking bob,
  an attack lunge, a hit flash and a death fade itself.

## Preparing an image

`tools/prepare_art.py` (Python 3 and Pillow: `pip install Pillow`) removes
a solid background, crops to the character, puts the feet at the
bottom-center of a square, and resizes to 512x512:

```sh
python3 game/tools/prepare_art.py ~/Downloads/higgsfield_wolf.png wolf
python3 game/tools/prepare_art.py bandit.png bandit --tolerance 48
```

It writes `game/art/characters/<id>.png`. Images that already have
transparency are only cropped, padded and resized (`--force-key` removes the
background anyway). If the background is removed too little, raise
`--tolerance` (default 32); if parts of the character disappear, lower it.
Background-coloured areas fully enclosed by the character (such as the gap
inside a bent arm) are kept; erase those by hand if needed.

Open the project in the Godot editor once after adding images, so it
imports them (this creates the `.png.import` files; commit them too).

## Git LFS

Character sprites in `art/characters/` are small (512x512) and are committed
as plain files, not through LFS. Other `*.png` art and audio go through Git
LFS (see `.gitattributes`); run `git lfs install` once before committing
those.

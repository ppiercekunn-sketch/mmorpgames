# Character art prompts (Higgsfield, free plan)

Budget: 10 free credits. The Higgsfield connector in Claude can read your
generations but can't start them, so generate these in the Higgsfield app and
Claude pulls the results in with `show_generations`.

## How to generate

- **Model:** Nano Banana (budget, and it accepts reference images). Use
  aspect ratio **1:1**.
- **Order matters.** Generate the Warrior first. For every image after it,
  attach the Warrior image as a **reference image**, so all characters share
  one art style.
- **One try per character.** If a result is unusable, skip it and tell Claude
  rather than spending credits on re-rolls; the game falls back to drawn
  placeholders for anything missing.
- A plain white background is fine. Claude's art tool removes it, crops and
  scales the image.

Priority order (stop when credits run out):

| # | File id | Character |
|---|---|---|
| 1 | `warrior` | Player hero |
| 2 | `slime` | Enemy, level 1 |
| 3 | `wolf` | Enemy, level 3 |
| 4 | `bandit` | Enemy, level 5 |
| 5 | `star_pup` | Starter pet |
| 6 | `field_boss` | Field boss (Star Ogre), level 10 |

## Shared style line

Every prompt ends with this line, unchanged:

> Chibi anime game character, full body, single character centered, 3/4
> isometric view from above, facing toward the bottom-right, standing on
> flat ground, clean bold outlines, soft cel shading, bright saturated
> colors, Chinese fantasy MMORPG style, plain solid white background, no
> shadow, no text, no frame.

## Prompts

**1. warrior**
> A young warrior hero with spiky dark hair, a red headband, light bronze
> armor plates over a crimson tunic, holding a broad sword resting on the
> shoulder, determined grin, small gold star emblem on the chest.
> + shared style line

**2. slime** (attach the warrior as reference)
> A cute round jelly slime monster, translucent mint-green body with a
> glossy highlight, two big dot eyes and a tiny open mouth, slightly
> squashed teardrop shape.
> + shared style line

**3. wolf** (attach the warrior as reference)
> A gray forest wolf monster on four legs, shaggy fur with a darker back
> stripe, glowing amber eyes, bared fangs, crouched ready to pounce.
> + shared style line

**4. bandit** (attach the warrior as reference)
> A road bandit in a brown hooded cloak and leather vest, face mask over the
> mouth, curved saber in one hand, sly narrow eyes.
> + shared style line

**5. star_pup** (attach the warrior as reference)
> A tiny loyal puppy companion pet, cream and pale-blue fur, a glowing gold
> star mark on the forehead, big sparkling eyes, fluffy tail up, happy
> expression.
> + shared style line

**6. field_boss** (attach the warrior as reference)
> A huge hulking ogre boss with dusky purple skin, a horned iron helmet,
> spiked shoulder pads, a giant stone club, star-shaped glowing runes on the
> chest, menacing.
> + shared style line

## After generating

Tell Claude which generations map to which id (or generate them in the order
above and say so). Claude downloads them, runs
`game/tools/prepare_art.py` to remove the background, crop and resize to
512x512, and commits them to `game/art/characters/` through Git LFS.

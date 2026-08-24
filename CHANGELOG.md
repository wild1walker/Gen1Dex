# Changelog

## 1.0.0

First release.

### The list

- A party icon beside every dex entry, drawn down the engine's own icon path
  (`PartyMenu.drawIcon`), so a menu-icon mod's art shows up here too.
- An undiscovered species is drawn as a **black silhouette** — a draw-time
  tint rather than a palette zone, so it holds for an icon mod's authored
  full-colour art as well as for the built-in DMG icons.
- A palette zone per discovered row, so every POKéMON on screen wears its own
  species colours; the chrome is shade 3 throughout and stays black under any
  zone.
- SELECT cycles the view between `POKéDEX`, `POKéDEX A-Z` (seen only, by name)
  and `POKéDEX CAUGHT` (owned only). The cursor stays on the same species
  wherever it survives the switch, and the SEEN / OWN counts are the whole
  dex's in every view.
- A view with nothing in it is refused rather than entered, because ListMenu
  returns before `onSelectKey` on an empty list and there would be no way back.
- UP on the first row and DOWN on the last wrap around.
- Built by the vanilla constructor and re-dressed, so the DATA / CRY / AREA /
  QUIT side menu and the QUIT path are untouched.

### The entry

- Three pages A cycles between: **DEX** (sprite, kind, height, weight and the
  Pokédex description), **STATS** (base stats, BST, types, evolutions) and
  **MOVES** (level-up moves, then TM/HM).
- The vanilla description is kept, and A turns its pages before moving on —
  the ROM's own behaviour for that key on that page.
- UP/DOWN opens the previous or next seen species on the first two pages, and
  pages the movelist on the third.
- A shared header and footer box on all three pages.
- Machine moves resolve through the items registry rather than a hard-coded TM
  table, so a mod that adds TM51 shows up with no help.
- Evolution labels come from the merged `evolution_methods` registry's
  `describe()`, so a mod-added method describes itself here.
- STAB moves are marked with a chip in their type's colour, and each type is
  underlined in its own; both are marked with `PaletteFX.markTrueColor` so the
  SGB shade remap cannot turn them into arbitrary greys.
- The sprite resolves through the battle kind first, so sprite and animation
  mods provide their replacement, with the dex kind as the fallback.
- Optional support for `crystal_animated_sprites_with_shiny_visuals`: its
  packaged frames are played on the DEX page when the mod is installed.

### Elsewhere

- Five options in the mod manager: `SPECIES COLOURS`, `SELECT VIEWS`,
  `UP/DOWN SPECIES`, `LIST WRAPS`, `HOLD TO SCROLL`.
- The pure builders are published on `mod.exports` for other mods and for the
  suite.
- Declared conflicts with `useful_dex` and `pokedex_plus`, which register the
  same screen ids.
- A headless test suite (171 checks) and a CI workflow that runs it against a
  real Gen1Recomp checkout with no ROM.

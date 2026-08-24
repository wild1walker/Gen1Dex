# Changelog

## 1.1.0

Spacing, chrome and the page keys.

### Fixed

- **An oversized sprite no longer runs into the description.** A Gen 1 front
  sprite is at most 56x56 and the well is exactly that, but a sprite pack ships
  whatever art its author drew: a 96x96 one drawn at 1:1 ran 38 pixels past the
  bottom of the well, through the rule and across all three lines of the text
  under it. Oversized art is now scaled down by the tighter of the two ratios,
  keeping its aspect; art that already fits is never scaled up.
- **The white stripe above a small sprite is gone.** The picture was pinned to
  the floor of the well, so everything shorter than 56 pixels left all of its
  slack in one band above it. It is centred in both axes now.
- The palette zone and the true-colour mark are measured from the DRAWN rect
  rather than the file's, so a scaled sprite no longer re-blits a patch bigger
  than the picture.

### Added

- **LEFT and RIGHT walk the entry's three pages**, wrapping both ways, with an
  arrow at each end of the header saying so. A still advances, but a reader one
  page too far can now go back instead of forward twice. LEFT and RIGHT do not
  wait for the description the way A does.
- Stepping to another species with UP/DOWN keeps the page you were reading.

### Changed

- **Both screens are boxed top and bottom**, like the rest of the set: a header
  box naming what you are looking at and a footer box saying what you can do
  about it, with the body ruled into columns between them.
- The list rules its icon column off from the names, and the owned ball moved
  into a fixed column of its own -- a column of balls can be scanned down, a
  scatter of them following the end of each name cannot.
- The list draws six rows rather than seven: the two boxes cost a tile row each
  end, and six 16-pixel rows fill the 96 pixels between them exactly.
- A row of three pips in the list header shows which view you are in.
- The entry's footer names the page you are on; the movelist's section headings
  are underlined.
- The DEX page's info column was pulled up and tightened, and the description
  rule with it.

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

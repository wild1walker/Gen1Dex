# Changelog

## 1.5.3

### Fixed

- **The side menu on a discovered entry had no box.** A on a POKéMON you have
  met came up as four bare words floating over the list, `QUIT` printed across
  the SEEN and OWN counts and past the bottom of the screen. A on one you have
  not met — this mod's own two-row menu — was drawn properly, which is what
  made it look like the discovered entries were the broken ones.

  Both were the same omission. The vanilla dex prints `DATA` / `CRY` / `AREA` /
  `QUIT` permanently into the block down the right of its screen, so
  `PokedexMenu`'s side menu draws the labels and the cursor and nothing else —
  *"the block is already on screen"*, as its own comment puts it, and in
  vanilla it is, because the vanilla list drew it. This list does not: the
  right of the screen is where the names run, and SEEN / OWN moved into a
  footer box. There was no block for the menu to be the cursor on.

  `chooseEntry` is now run and the menu it pushes is taken rather than shown:
  its entries go into a box of this mod's own. Nothing about what a press does
  changes — `DATA` and `CRY` are the engine's closures, not copies, and
  Yellow's `PRNT` comes along without this mod knowing it exists. The box is
  bottom-aligned on the last row of the body, so two rows sit exactly where
  they always have and four grow *upward* into the list rather than down
  through the footer.

  It is wired whether or not `AREA ON UNSEEN` is on. That row says what A does
  on a row you have never met; it has nothing to say about whether the menu on
  a row you have met is drawn inside a frame.

- **The row a side menu is open on reads as hollow.** The engine sets
  `hollowIndex` on the list when it opens one (`PlaceUnfilledArrowMenuCursor`)
  and the vanilla list draws the unfilled arrow for it; this list draws its own
  rows and was answering the solid cursor either way. Two live-looking cursors
  on one screen is a lie about which one the d-pad is moving.

## 1.5.2

Two keys that never ended anywhere: A on an entry a script was waiting for,
and the d-pad on the AREA map.

### Fixed

- **The starter you could not pick.** Oak's lab shows the Pokédex entry for a
  starter before it asks whether you want it, and the Safari Zone's signs and
  the S.S. Anne's Snorlax do the same thing on their own species: the script
  runs `push_screen DexEntryMenu` and then blocks until the screen pops itself
  (`Commands.push_screen`). The vanilla page popped on A once the description
  was spent, so A was the key that carried you through the preview and into
  the question.

  This mod's A advanced instead of ending: DEX to STATS to MOVES and round to
  DEX again, forever. B still closed the screen, so the way out existed — but
  a player pressing A at a CHARMANDER they had just been offered got a third
  page and then the first one back, and nothing ever asked them anything.

  A now walks the entry once and then leaves it. Past the last page it closes,
  which is what hands the waiting script its answer. LEFT and RIGHT are
  unchanged and still wrap both ways: they are the page keys, and a reader who
  overshoots has to be able to come back round.

- **`attempt to call method 'moveGrid' (a nil value)`** on the first d-pad
  press on the AREA map, once the hint was down.

  1.4.0 gave that screen a cursor you could move, where vanilla ignored the
  d-pad entirely, and moved it by calling a `moveGrid` on `TownMap`. No
  version of `TownMap` has one: its d-pad handling is `moveList`, which walks
  the towns in cursor order on UP and DOWN and does not answer LEFT or RIGHT
  at all. So the feature was a crash from the day it shipped.

  The snap-to-nearest is this mod's own now, and it snaps to the nearest
  location **in the direction pressed** rather than the nearest one overall —
  a cone of 45 degrees either side of the key, off-axis scored harder than
  distance so the straight neighbour wins a tie. A key with nothing in front
  of it leaves the cursor where it is; UP and DOWN then fall back to walking
  the list, so no press is simply swallowed.

### Testing

`area_test` was already asserting that the d-pad moved the cursor, and was
already red. It was not wired in front of the release (`test.yml` runs beside
`release.yml`, deliberately), so it stayed red through two releases. Both
suites now assert the shape of the fix rather than only its effect: that every
AREA move goes the way the key pointed, and that A alone gets out of a
script-pushed entry in a handful of presses.

## 1.5.1

The POKéDEX crashed the moment the cursor moved.

### Fixed

- **`src/ui/PokedexMenu.lua:116: attempt to call method 'rows' (a number
  value)`**, in the engine's own `syncScroll`, on the first press of UP or
  DOWN after the list came up.

  The vanilla dex was a `ListMenu` until Gen1Recomp rewrote it as a screen of
  its own, and the two shapes disagree about the one field this mod has always
  written. A `ListMenu` carries `rows` as a number — this list wants six where
  vanilla shows seven, because the header and footer boxes took a tile row each
  end — and the screen that replaced it carries `rows()` as a method its own
  scroll clamp calls. Writing the six over the method left the engine calling
  a number.

  Which shape the engine has is asked once now, and the six rows are handed
  over the way that shape asks for them. Nothing changes on a build whose dex
  is still a list.

- **SELECT VIEWS, LIST WRAPS and HOLD TO SCROLL had gone quiet with it.**
  `wrap`, `keyRepeat` and `onSelectKey` were `ListMenu` opts, and the screen
  that replaced it reads none of them — so three rows in this mod's options
  did nothing at all, and LEFT/RIGHT paged by the engine's seven over a list
  showing six, stepping past an entry every press and never reaching the last
  one.

  All four are answered again, as a layer over the engine's update rather than
  a replacement for it: A, B and the DATA / CRY / AREA / QUIT side menu never
  reach it, and every key it does take is one the engine leaves unbound here
  or one whose press it would have spent doing nothing.

### Testing

The suite built the list and read it back and never once ran the screen's own
`update`, which is how a dex that crashed on the first direction key shipped
green. `tests/gen1dex_test.lua` now drives the real screen the way a player
does — press, update, release — over the cursor keys, SELECT, both ends of the
wrap and a held key's repeat. Against the code this release fixes it stops at
exactly the reported line.

The row-count assertion asked the list for `rows` as a number, so it was
reading the very field that moved. It asks the screen instead now, and checks
both that a short list answers its own length and that a long one stops at six.

## 1.5.0

The nickname prompt, over the entry it just closed.

### Changed

- **A new catch asks for its nickname over the dex entry rather than over a
  blank white screen.** Catch something the dex has never held and the game
  shows you its entry, then wipes the screen to white to ask whether you want
  to name it: `AskName` clears the field before it prints, because the dex page
  and the battle are two tilemaps and the Game Boy has one of those.

  The page stays up now. Same box, same words, same two rows in the corner --
  the prompt is the engine's own and nothing about it moves; the only
  difference is that the POKéMON you are being asked to name is on the screen
  while you name it.

  It is the same screen rather than a second one built to look like it: a page
  left on STATS comes back on STATS, no cry plays twice, and no sprite is
  loaded twice. The one thing put back is the species, because UP/DOWN on an
  entry walks the ones you have seen and the box is about to ask after a
  particular POKéMON by name.

- **And a catch of something the dex already holds keeps the battle.** There is
  no dex page in that moment -- the game never shows one for a species you
  already have -- so the question is asked over the screen it did interrupt:
  the field the POKéMON was caught on, your POKéMON and both status boxes, and
  the closed ball resting where the one you just caught was standing.

  That ball is the point. The Game Boy leaves it in OAM through the caught text
  and only `AskName`'s `ClearSprites` takes it away, so keeping the field means
  keeping the ball with it -- and putting it down once the question is answered
  is that `ClearSprites`, moved to where the sprites are actually finished
  with.

  Conjuring a dex page here was the obvious other answer and it is the wrong
  one: a page a player was never shown is not a page being kept up, and the
  twelfth ZUBAT does not owe anyone its Pokédex paragraph.

  `NAME IN PLACE` turns both halves off, and the prompt goes back to white.

## 1.4.0

What AREA says when there is nothing to say.

### Added

- **A line for a species nobody can answer for.** The four statics live in no
  wild table and evolve from nothing, so AREA on MOLTRES drew a map with
  nothing on it -- which cannot be told apart from a hint that failed to draw.
  The box now comes up either way and says `NO RECORD REMAINS` /
  `GO ADVENTURING!`.

  A species a mod is deliberately withholding (a provider's `false`) gets the
  same two lines, which is load-bearing rather than lazy: Gen151 seals MEW
  until the Mansion journals are read, and a seal that read differently from an
  ordinary blank would tell the player there is something there. MEW's screen
  and MOLTRES's are now the same screen to the glyph. The words are published
  as `exports.area.unknown` for a mod that wants to match them.

### Fixed

- **The AREA header ran off the right edge of the screen.** Vanilla writes
  `<NAME> AREA UNKNOWN` into a 19-column strip without measuring it:
  `MOLTRES AREA UNKNOWN` is 20 glyphs, and every name of eight or more -- half
  the dex -- lost its last word mid-letter.

  The unknown line is this mod's now and drops the word AREA rather than
  truncating the name: the screen the player is standing on is already called
  AREA, so the word was carrying nothing, and `MOLTRES UNKNOWN` fits every name
  in the dex. The nest line (`<NAME>'s NEST`) is still the engine's own and is
  only repainted when it would have overflowed.

  1.3.0 shortened the header only on a screen that had a caption to draw --
  and the screens that overflowed were exactly the ones with no caption, so in
  practice it never fired.

## 1.3.0

The AREA screen.

### Added

- **AREA opens on an entry you have never met.** Vanilla's dex side menu
  returns early unless the entry is seen or owned, which is exactly backwards
  on the screen a player opens to find out where something lives. Pressing A on
  a blank row now opens a two-row menu -- `AREA` and `QUIT`, and nothing that
  would hand over the dex paragraph you have not earned -- and AREA opens on
  the species the ROW names, which is what makes it survive this mod's own
  filtered and re-sorted views.
- **A line under the AREA map saying how to get there**, for all 151. The
  blinking nests say *where*; they cannot say *in the grass, around level ten,
  and rare*, and that is the half a player actually needs. It is read straight
  out of the live encounter tables -- the map where the species has the biggest
  share of the encounters, that map's own level band, and a rarity worked out
  from Gen 1's ten slot buckets -- so it is right by construction and costs no
  data of its own. A species that is wild nowhere is answered out of the
  evolution table instead: `EVOLVE ODDISH / AT LV21`, `LINK CABLE / ON
  KADABRA`, `MOON STONE / ON NIDORINO`.
- **A press takes it away, START brings it back.** The box covers two tile rows
  of Kanto and one of them has nests in it, so the first A dismisses the hint
  and the second closes the screen, the way A always did. With the hint down
  the screen is the plain town map again -- the d-pad moves the cursor and the
  top strip names the place it is on, where vanilla's AREA branch ignored the
  d-pad and stopped drawing before either. B still leaves immediately.
- **A caption hook for other mods**: `mod.find("Gen1Dex").exports.area.provide`
  takes a function of `(game, species)` and lets a mod answer for its own
  species. Return two lines to draw them, `false` to withhold an answer that
  the built-in readings must not fill in for -- a spawn behind an event that has
  not fired yet -- or `nil` for no opinion. Providers are asked in registration
  order, first opinion wins, and the readings above are last. Pass your mod id
  as the second argument and a hot reload replaces your provider instead of
  stacking a second one.
- `AREA ON UNSEEN` and `AREA HINTS`, in the mod manager. Both are read when the
  screen opens rather than once at load, so flipping either shows up the next
  time you open it.

All of this shipped inside [Gen151](https://github.com/wild1walker/Gen151)
first, where it had to reach a dex list it did not own by wrapping the vanilla
constructor and re-deriving each row's species -- which broke the moment a dex
mod replaced the rows, and this mod replaces them wholesale. The screen belongs
to whoever draws it. Gen151 1.5.0 keeps only the words for its own spawns and
hands them over through the hook above.

## 1.2.0

DEX in the START menu.

### Changed

- **The START menu's dex row reads `DEX`.** The overworld menu's first row is
  renamed through the engine's `ui.start_menu.items` hook: same position, same
  key, same screen behind it, and every other row untouched. Nothing else that
  says POKéDEX moves -- the SAVE panel's dex count and the list's own header are
  separate text.

### Added

- `START SAYS DEX`, in the mod manager. Off hands the engine's row back exactly
  as it built it. It is read when the menu opens rather than once at load, so
  flipping it shows up the next time you press START.

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

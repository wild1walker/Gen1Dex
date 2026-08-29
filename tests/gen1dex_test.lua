-- Standalone: luajit mods/Gen1Dex/tests/gen1dex_test.lua
--
-- Loads the mod through the headless SDK harness against the ROM-free
-- fixture dataset and asserts its stated effect: both Pokédex screens are
-- taken over, every list row knows which POKéMON it is showing (or hiding),
-- the three views filter and count the way the README says, and all three
-- entry pages build and DRAW without throwing.
--
-- Run it from a Gen1Recomp checkout with this mod at mods/Gen1Dex, or set
-- GEN1DEX_DIR to wherever it lives.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local Font = require("src.render.Font")

local DIR = os.getenv("GEN1DEX_DIR") or "mods/Gen1Dex"
local Data = T.fixtures.fresh()
local run = T.sdk.loadMod(DIR, { data = Data })
T.eq(#run.errors, 0, "loads clean (" .. tostring(run.errors[1]) .. ")")

local exports = run.loader.exports[run.mod.manifest.id]
T.check(exports ~= nil, "the mod publishes its builders")

-- ------- both screens are taken over

local listFactory = Data.screens and Data.screens.PokedexMenu
local entryFactory = Data.screens and Data.screens.DexEntryMenu
T.check(listFactory ~= nil, "the PokedexMenu screen id is taken over")
T.eq(type(listFactory.new), "function", "and it is a screen factory")
T.check(entryFactory ~= nil, "the DexEntryMenu screen id is taken over")
T.eq(type(entryFactory.new), "function", "and it is a screen factory too")

-- ------- a stub game
--
-- The screens read data, save.pokedex, stack and input, and nothing else.

local function newStack()
  local stack = { states = {} }
  function stack:push(state) table.insert(self.states, state) end
  function stack:pop() return table.remove(self.states) end
  function stack:top() return self.states[#self.states] end
  return stack
end

local function fakeGame(seen, owned)
  local pressed = {}
  local game = {
    data = Data,
    save = {
      pokedex = { seen = seen or {}, owned = owned or {} },
      player = { name = "RED", id = 1 },
      party = {}, flags = {},
    },
    stack = newStack(),
    input = {
      wasPressed = function(_, key) return pressed[key] end,
      isDown = function(_, key) return pressed[key] end,
    },
  }
  game.press = function(key) pressed = {}; pressed[key] = true end
  game.release = function() pressed = {} end
  return game
end

-- FIXMON_A is seen and owned, FIXMON_B is seen only, FIXMON_C is neither:
-- one species per state, which is every branch the list and the silhouette
-- rule have.
local SEEN = { FIXMON_A = true, FIXMON_B = true }
local OWNED = { FIXMON_A = true }

-- ------- the list: three views over the same slots

local num = exports.buildList(Data, { seen = SEEN, owned = OWNED }, "num")
T.eq(#num.items, 3, "the numbered view has every dex slot")
T.eq(num.items[1].label, "001 FIXMON A", "a seen species is named")
T.eq(num.items[3].label, "003 -----", "an unseen one is blanked")
T.eq(num.seen, 2, "SEEN counts the whole dex")
T.eq(num.owned, 1, "and so does OWN")

-- The precondition for the silhouette: a blank row still knows which
-- POKéMON it is not showing you, which the vanilla list does not carry.
T.eq(num.items[3].species, "FIXMON_C", "a blank row still names its species")
T.eq(num.items[3].value, nil, "but A still does nothing on it")
T.eq(num.items[3].seen, false, "and it is marked undiscovered")
T.eq(num.items[1].seen, true, "a seen row is marked discovered")
T.eq(num.items[1].owned, true, "an owned row is marked owned")
T.eq(num.items[2].owned, false, "a seen-only row is not")
T.eq(num.items[1].ball, true, "owned carries the ball marker")
T.eq(num.items[2].ball, nil, "seen-only does not")

local alpha = exports.buildList(Data, { seen = SEEN, owned = OWNED }, "alpha")
T.eq(#alpha.items, 2, "A-Z drops what has not been seen")
T.eq(alpha.items[1].species, "FIXMON_A", "and sorts by name")
T.eq(alpha.items[2].species, "FIXMON_B", "in name order")
T.eq(alpha.seen, 2, "the counts are still the whole dex's")
T.eq(alpha.owned, 1, "in every view")

local caught = exports.buildList(Data, { seen = SEEN, owned = OWNED }, "caught")
T.eq(#caught.items, 1, "CAUGHT keeps only what is owned")
T.eq(caught.items[1].species, "FIXMON_A", "the owned one")

local empty = exports.buildList(Data, { seen = {}, owned = {} }, "caught")
T.eq(#empty.items, 0, "an empty dex has an empty CAUGHT view")

-- A-Z keeps its dex numbers: the row is re-sorted, not re-numbered, which is
-- what lets you read a number off a name-sorted list.
T.eq(alpha.items[1].label, "001 FIXMON A", "A-Z keeps the dex number")

-- ------- the views cycle, and the empty one is refused

T.eq(exports.nextMode.num, "alpha", "SELECT goes numbered -> A-Z")
T.eq(exports.nextMode.alpha, "caught", "A-Z -> caught")
T.eq(exports.nextMode.caught, "num", "and caught wraps to numbered")

do
  local game = fakeGame(SEEN, OWNED)
  local list = listFactory.new(game)
  T.eq(list.dexMode(), "num", "the list opens numbered")
  T.eq(#list.items, 3, "with every slot")
  T.eq(list.items[3].species, "FIXMON_C", "rebuilt so blank rows name a species")

  list.onSelectKey()
  T.eq(list.dexMode(), "alpha", "SELECT cycles to A-Z")
  T.eq(#list.items, 2, "and filters to what has been seen")
  T.eq(list.title, exports.modeLabels.alpha, "the title follows the view")

  list.onSelectKey()
  T.eq(list.dexMode(), "caught", "SELECT cycles to caught")
  T.eq(#list.items, 1, "and filters to what is owned")

  list.onSelectKey()
  T.eq(list.dexMode(), "num", "and wraps back to numbered")
end

do
  -- Nothing seen: A-Z and CAUGHT are both empty, so SELECT must stay put
  -- rather than strand the player on a list ListMenu returns out of.
  local game = fakeGame({}, {})
  local list = listFactory.new(game)
  list.onSelectKey()
  T.eq(list.dexMode(), "num", "SELECT refuses a view with nothing in it")
  T.eq(#list.items, 3, "and leaves the list it was on")
end

do
  -- The cursor is kept on the SPECIES across a view change, not on the row
  -- number: A-Z reorders, so a kept index would land somewhere else.
  local game = fakeGame(SEEN, OWNED)
  local list = listFactory.new(game)
  list.index = 2                          -- FIXMON_B, seen but not owned
  list.onSelectKey()
  T.eq(list.dexMode(), "alpha", "switched to A-Z")
  T.eq(list.items[list.index].species, "FIXMON_B", "the cursor stayed on it")

  -- and when it does NOT survive the filter, the cursor falls back to the top
  list.onSelectKey()
  T.eq(list.dexMode(), "caught", "switched to caught")
  T.eq(list.index, 1, "a species the filter dropped falls back to the first row")
end

-- ------- the cursor moves
--
-- Everything above builds the list and reads it back; none of it ever ran
-- the screen's own `update`, which is how the dex shipped crashing on the
-- first press of a direction key and this suite stayed green.
--
--   src/ui/PokedexMenu.lua:116: attempt to call method 'rows' (a number value)
--
-- The vanilla dex was a `ListMenu` and became a screen of its own, and the
-- two disagree about `rows`: a number the list reads, a method the screen's
-- own syncScroll CALLS.  This mod wants six rows where vanilla shows seven,
-- and wrote that six straight over the method.
--
-- So these drive the real screen the way a player does: press, update,
-- release.  `wasPressed` is a question and not a queue -- src/core/Input.lua
-- answers it out of a table the frame boundary clears -- and `isDown` is the
-- separate held state key-repeat reads, so the two are kept apart here.

local function keyboard(game)
  local pressed, down = {}, {}
  game.input = {
    wasPressed = function(_, key) return pressed[key] or false end,
    isDown = function(_, key) return down[key] or false end,
  }
  return {
    press = function(key) pressed[key], down[key] = true, true end,
    hold = function(key) down[key] = true end,
    release = function(key) down[key] = nil end,
    -- one frame: the screen updates, then the presses age out
    frame = function(screen) screen:update(0); pressed = {} end,
  }
end

do
  local game = fakeGame(SEEN, OWNED)
  local list = listFactory.new(game)
  local keys = keyboard(game)

  -- Whichever shape the engine has, the answer is this mod's six rows capped
  -- by what is in the list -- three, on the fixture dex.
  if type(list.rows) == "function" then
    T.eq(list:rows(), 3, "the screen is asked for its rows and answers three")
  else
    T.eq(list.rows, 6, "the list carries six rows as a number")
  end

  keys.press("down")
  T.check(pcall(keys.frame, list), "a press of DOWN does not throw")
  T.eq(list.index, 2, "and moves the cursor one row")
  keys.release("down")

  keys.press("up")
  keys.frame(list)
  T.eq(list.index, 1, "UP comes back")
  keys.release("up")
end

do
  -- SELECT through the screen's own update, not by calling the handler: the
  -- routing is the half that broke, and the handler was already covered.
  local game = fakeGame(SEEN, OWNED)
  local list = listFactory.new(game)
  local keys = keyboard(game)

  keys.press("select")
  keys.frame(list)
  T.eq(list.dexMode(), "alpha", "SELECT reaches the view cycle through update")
  keys.release("select")
end

do
  -- LIST WRAPS: UP on the first row crosses to the last, DOWN on the last
  -- comes back.  151 rows is a long way to hold a key for the far end.
  local game = fakeGame(SEEN, OWNED)
  local list = listFactory.new(game)
  local keys = keyboard(game)

  keys.press("up")
  keys.frame(list)
  T.eq(list.index, #list.items, "UP on the first row wraps to the last")
  keys.release("up")

  keys.press("down")
  keys.frame(list)
  T.eq(list.index, 1, "and DOWN on the last wraps to the first")
  keys.release("down")
end

do
  -- HOLD TO SCROLL: sixteen frames of delay, then a row every four.
  local game = fakeGame(SEEN, OWNED)
  local list = listFactory.new(game)
  local keys = keyboard(game)

  keys.press("down")
  keys.hold("down")
  keys.frame(list)
  T.eq(list.index, 2, "the press itself moves one row")

  for _ = 1, 16 do keys.frame(list) end
  T.eq(list.index, 3, "a held key starts repeating after the delay")

  keys.release("down")
  for _ = 1, 8 do keys.frame(list) end
  T.eq(list.index, 3, "and letting go stops it")
end

do
  -- The page keys are the engine's, and reach this mod's own pageScroll.
  local game = fakeGame(SEEN, OWNED)
  local list = listFactory.new(game)
  local keys = keyboard(game)

  keys.press("right")
  T.check(pcall(keys.frame, list), "a page key does not throw")
  T.check(list.index >= 1 and list.index <= #list.items,
          "and leaves the cursor on a row that exists")
  keys.release("right")
end

-- ------- the list draws

do
  local game = fakeGame(SEEN, OWNED)
  local list = listFactory.new(game)
  T.check(pcall(list.draw, list), "the list draws")
  local ok = pcall(list.sgbPalettes, list, game)
  T.check(ok, "and answers with a palette")

  local zones = list:sgbPalettes(game)
  T.check(type(zones) == "table", "the palette is a zone list")
  -- One whole-screen base, and a zone only for the rows that are BOTH seen
  -- and drawn with grey art: FIXMON_A and FIXMON_B, never FIXMON_C.
  T.check(#zones >= 1, "with a base palette in it")
end

do
  local game = fakeGame({}, {})
  local list = listFactory.new(game)
  T.check(pcall(list.draw, list), "a list of nothing but blanks still draws")
end

-- ------- the cursor goes hollow while the side menu owns the d-pad
--
-- engine/menus/pokedex.asm PlaceUnfilledArrowMenuCursor: the row a menu was
-- opened on stops reading as live, because the d-pad is moving the OTHER
-- cursor now.  The vanilla list does it off `hollowIndex`, which the engine's
-- own chooseEntry sets on the way past; this list draws its own rows, so it
-- has to answer the field itself or the row lies about which cursor UP moves.

do
  local Theme = require("src.ui.Theme")
  local game = fakeGame(SEEN, OWNED)
  local list = listFactory.new(game)
  local codes = {}
  local realDrawCode = Font.drawCode
  Font.drawCode = function(code, x, y)
    codes[#codes + 1] = code
    return realDrawCode(code, x, y)
  end
  local ok = pcall(list.draw, list)
  Font.drawCode = realDrawCode
  T.check(ok, "the list draws")
  local function drew(code)
    for _, c in ipairs(codes) do if c == code then return true end end
    return false
  end
  T.check(drew(Theme.cursor), "the row it is on carries the solid cursor")
  T.check(not drew(Theme.cursorHollow), "and no hollow one, with no menu up")

  codes = {}
  list.hollowIndex = list.index
  realDrawCode = Font.drawCode
  Font.drawCode = function(code, x, y)
    codes[#codes + 1] = code
    return realDrawCode(code, x, y)
  end
  ok = pcall(list.draw, list)
  Font.drawCode = realDrawCode
  T.check(ok, "and draws with a menu up")
  T.check(drew(Theme.cursorHollow),
    "where the row it was opened on goes hollow")
  T.check(not drew(Theme.cursor),
    "and the solid one is gone, rather than both being on screen")
end

-- ------- the silhouette, which is the whole point of the icons
--
-- The fixture dataset ships no icons table, so PartyMenu.drawIcon returns at
-- its first line and a plain draw() proves nothing about what colour the icon
-- would have been drawn in.  So ask the drawer directly: stand in for
-- drawIcon, record the colour that was set when it was called, and read the
-- rule off the recording.  The field is looked up on the module table at call
-- time, which is what makes this substitution possible at all.

do
  local PartyMenu = require("src.ui.PartyMenu")
  local real = PartyMenu.drawIcon
  local calls = {}
  PartyMenu.drawIcon = function(_, mon, x, y)
    local r, g, b = love.graphics.getColor()
    calls[#calls + 1] = { species = mon.species, x = x, y = y,
                          r = r, g = g, b = b }
    return true
  end

  local game = fakeGame(SEEN, OWNED)
  local list = listFactory.new(game)
  local ok, err = pcall(list.draw, list)
  PartyMenu.drawIcon = real
  T.check(ok, "the list draws with an icon in every row (" .. tostring(err) .. ")")

  T.eq(#calls, 3, "one icon per row, blank rows included")
  T.eq(calls[1].species, "FIXMON_A", "the first row draws its own species")
  T.eq(calls[3].species, "FIXMON_C", "and so does the row you have never seen")

  -- the rule, both halves
  T.eq(calls[1].r, 1, "a discovered species is drawn untinted")
  T.eq(calls[1].g, 1, "untinted green")
  T.eq(calls[1].b, 1, "untinted blue")
  T.eq(calls[2].r, 1, "seen-but-not-owned is discovered too")
  T.eq(calls[3].r, 0, "an undiscovered species is tinted black")
  T.eq(calls[3].g, 0, "black green")
  T.eq(calls[3].b, 0, "black blue")

  -- and where they land: x on a tile boundary, rows 16 apart from y=24
  T.eq(calls[1].x, 8, "the icon sits at x=8, a whole tile")
  T.eq(calls[1].y, 24, "the first row at y=24")
  T.eq(calls[2].y, 40, "the second 16 pixels below it")
  T.eq(calls[3].y, 56, "and the third 16 below that")
  for _, call in ipairs(calls) do
    T.eq(call.x % 8, 0, "every icon x is tile-aligned")
    T.eq(call.y % 8, 0, "every icon y is tile-aligned")
  end
end

-- ------- and the palette zones that go with it
--
-- monPal answers off a palette pack the fixture dataset does not carry, so
-- stand in for it too: what is being asserted is WHICH rows ask for a zone,
-- not what colours come back.

do
  local PaletteFX = require("src.render.PaletteFX")
  local realMonPal = PaletteFX.monPal
  local asked = {}
  PaletteFX.monPal = function(_, species)
    asked[#asked + 1] = species
    return { { 255, 255, 255 }, { 200, 100, 100 }, { 100, 50, 50 }, { 0, 0, 0 } }
  end

  local game = fakeGame(SEEN, OWNED)
  local list = listFactory.new(game)
  local zones = list:sgbPalettes(game)
  PaletteFX.monPal = realMonPal

  T.eq(#asked, 2, "only the discovered rows ask for a species palette")
  T.eq(asked[1], "FIXMON_A", "the owned one")
  T.eq(asked[2], "FIXMON_B", "and the seen one")
  for _, species in ipairs(asked) do
    T.neq(species, "FIXMON_C",
          "the undiscovered row asks for none -- a zone would colour the "
          .. "silhouette back in")
  end
  T.eq(#zones, 3, "a base palette plus one zone per discovered row")
end

-- ------- the movelist

local defA = Data.pokemon.FIXMON_A
local moves = exports.buildMoves(Data, defA)
T.eq(#moves.learned, 2, "the learnset comes through")
T.eq(moves.learned[1].name, "FIX TACKLE", "with the move's display name")
T.eq(moves.learned[1].level, 1, "and its level")
T.eq(moves.learned[1].stab, false, "a NORMAL move on a GRASS species is not STAB")
T.eq(moves.learned[2].name, "FIX EMBER", "in ROM order")

T.eq(#moves.machines, 1, "the tmhm list resolves through the items registry")
T.eq(moves.machines[1].kind, "TM", "as a machine kind")
T.eq(moves.machines[1].number, 1, "with the item's own number")
T.eq(moves.machines[1].name, "FIX CUT", "and the move's name")

do
  -- A learnset that names the same move twice keeps the FIRST (lower) level.
  local dup = { types = { "GRASS" }, tmhm = {}, learnset = {
    { level = 5, move = "FIX_TACKLE" },
    { level = 21, move = "FIX_TACKLE" },
  } }
  local built = exports.buildMoves(Data, dup)
  T.eq(#built.learned, 1, "a repeated move is printed once")
  T.eq(built.learned[1].level, 5, "at the level it is first learned")
end

do
  -- STAB is per species: the same move is marked on a FIRE one and not on a
  -- GRASS one.
  local fire = { types = { "FIRE" }, tmhm = {}, learnset = {
    { level = 1, move = "FIX_EMBERISH" } } }
  T.eq(exports.buildMoves(Data, fire).learned[1].stab, true,
       "a FIRE move on a FIRE species is STAB")
end

do
  -- HMs sort after every TM whatever their numbers say.
  local items = { HM = { id = "HM", machine = { kind = "HM", number = 1, move = "FIX_TACKLE" } },
                  TM = { id = "TM", machine = { kind = "TM", number = 50, move = "FIX_CUT" } } }
  local built = exports.buildMoves({ items = items, moves = Data.moves },
                                   { types = {}, tmhm = { "FIX_TACKLE", "FIX_CUT" } })
  T.eq(built.machines[1].kind, "TM", "TM50 sorts before HM01")
  T.eq(built.machines[2].kind, "HM", "and the HM comes last")
end

T.eq(#exports.buildMoves(Data, { types = {} }).learned, 0,
     "a species with no learnset builds an empty one")

-- ------- the move rows, and the width they have to fit

local rows = exports.buildMoveRows(moves)
T.eq(rows[1].text, "LEARNED", "the learned section is headed")
T.eq(rows[1].heading, true, "and marked as a heading")
T.eq(rows[2].text, "L1   FIX TACKLE", "a learned row is level then name")
T.check(rows[2].move ~= nil, "and carries the move it came from")
T.eq(rows[4].text, "TM/HM", "the machine section is headed")
T.eq(rows[5].text, "TM01 FIX CUT", "a machine row is the machine then the name")

T.eq(exports.buildMoveRows({ learned = {}, machines = {} })[1].text, "NO MOVES.",
     "a species that learns nothing says so")

do
  -- The rows are drawn at x=16 and the screen ends at 152, so no row may
  -- measure more than 17 glyphs.  Checked against the longest name the game
  -- has rather than against the fixtures', which are short.
  local long = { learned = { { level = 100, name = "THUNDERSHOCK" } },
                 machines = { { kind = "HM", number = 5, name = "THUNDERSHOCK" } } }
  for _, row in ipairs(exports.buildMoveRows(long)) do
    T.check(Font.width(row.text) <= 152 - 16,
            "the longest move row fits the screen: " .. row.text)
  end
end

-- ------- base stats, BST and evolutions

local stats = exports.buildStats(Data, defA)
T.eq(#stats.stats, 5, "five base stats")
T.eq(stats.stats[1].key, "HP", "in Gen 1 order")
T.eq(stats.stats[5].key, "SPC", "ending on SPECIAL")
T.eq(stats.stats[1].value, 45, "with the species' own numbers")
T.eq(stats.bst, 45 + 49 + 49 + 45 + 65, "and BST is their sum")

T.eq(#stats.evolutions, 1, "the evolution comes through")
T.eq(stats.evolutions[1].species, "FIXMON_B", "naming the target species")
T.eq(stats.evolutions[1].name, "FIXMON B", "by its display name")

do
  -- The label comes from the MERGED evolution_methods registry, so a
  -- mod-added method's own describe() is what this page prints.
  local data = {
    pokemon = { X = { id = "X", name = "X" } },
    evolution_methods = {
      MOONLIGHT = { describe = function(evo) return "AT " .. evo.when end },
    },
  }
  local def = { evolutions = { { method = "MOONLIGHT", when = "DUSK", species = "X" } } }
  T.eq(exports.buildStats(data, def).evolutions[1].label, "AT DUSK",
       "a mod-added method describes itself")
end

do
  -- A method with no describe(), and one whose describe() throws, both fall
  -- back to the method id rather than to a blank or a crash.
  local data = { pokemon = {}, evolution_methods = {
    QUIET = {},
    ANGRY = { describe = function() error("no") end },
  } }
  T.eq(exports.buildStats(data, { evolutions = { { method = "QUIET", species = "Z" } } })
        .evolutions[1].label, "QUIET", "a method with no describe falls back to its id")
  T.eq(exports.buildStats(data, { evolutions = { { method = "ANGRY", species = "Z" } } })
        .evolutions[1].label, "ANGRY", "and so does one that throws")
end

T.eq(exports.buildStats(Data, { }).bst, 0, "a species with no stats totals zero")
T.eq(#exports.buildStats(Data, { }).evolutions, 0, "and evolves into nothing")

-- ------- the description, and the ownership gate

do
  local data = { text = { ENTRY = "IT SLEEPS\vALL DAY\fAND ALL\vNIGHT" } }
  local def = { dexEntry = { text = "ENTRY" } }

  T.eq(exports.buildDescription(data, def, false), nil,
       "a species you have only SEEN shows no description")

  local pages = exports.buildDescription(data, def, true)
  T.check(pages ~= nil, "an owned one does")
  T.eq(#pages, 2, "and \\f starts a new page")
  T.eq(#pages[1], 2, "with \\v breaking the lines inside one")
  T.eq(pages[1][1], "IT SLEEPS", "the first line")
  T.eq(pages[2][2], "NIGHT.", "and the last one gains the full stop")

  T.eq(exports.buildDescription(data, { dexEntry = {} }, true), nil,
       "a species with no entry text has no description")
  T.eq(exports.buildDescription(data, { }, true), nil,
       "and neither does one with no dex entry at all")
end

-- ------- which species UP/DOWN walks

do
  local walked = exports.seenSpecies(Data, { seen = SEEN, owned = OWNED })
  T.eq(#walked, 2, "only the species that have been seen")
  T.eq(walked[1], "FIXMON_A", "in dex order")
  T.eq(walked[2], "FIXMON_B", "lowest number first")

  local ownedOnly = exports.seenSpecies(Data, { seen = {}, owned = OWNED })
  T.eq(#ownedOnly, 1, "owned implies seen")
  T.eq(ownedOnly[1], "FIXMON_A", "even with no seen bit set")

  T.eq(#exports.seenSpecies(Data, { seen = {}, owned = {} }), 0,
       "an empty dex walks nothing")
end

-- ------- the entry: three pages, A between them

do
  local game = fakeGame(SEEN, OWNED)
  local entry = entryFactory.new(game, "FIXMON_A")
  game.stack:push(entry)
  T.eq(entry.page, "dex", "an entry opens on the dex page")

  game.press("a"); entry:update(0)
  T.eq(entry.page, "stats", "A moves to the stats page")
  game.press("a"); entry:update(0)
  T.eq(entry.page, "moves", "A moves to the movelist")
  game.press("a"); entry:update(0)
  T.check(game.stack:top() ~= entry, "and A past the last page closes the entry")
end

do
  local game = fakeGame(SEEN, OWNED)
  local entry = entryFactory.new(game, "FIXMON_A")
  game.stack:push(entry)
  game.press("b"); entry:update(0)
  T.check(game.stack:top() ~= entry, "B closes the entry from any page")
end

do
  -- The page keys still wrap where A stops: LEFT and RIGHT are the page keys
  -- and a reader who overshoots has to be able to come back round.
  local game = fakeGame(SEEN, OWNED)
  local entry = entryFactory.new(game, "FIXMON_A")
  game.stack:push(entry)
  game.press("right"); entry:update(0)
  game.press("right"); entry:update(0)
  T.eq(entry.page, "moves", "RIGHT reaches the movelist")
  game.press("right"); entry:update(0)
  T.eq(entry.page, "dex", "and RIGHT wraps past it rather than closing")
  T.check(game.stack:top() == entry, "the entry is still up")
end

do
  -- Why A has to end somewhere: the lab's starter preview and the Safari
  -- Zone's signs push this screen and block until it pops itself
  -- (Commands.push_screen), so the whole script is waiting on the A press
  -- that leaves.  Vanilla's page popped on A; wrapping forever stranded the
  -- player at a starter they could not pick.
  local game = fakeGame(SEEN, OWNED)
  local entry = entryFactory.new(game, { species = "FIXMON_A",
                                         forceOwned = true })
  game.stack:push(entry)
  entry.desc = { { "PAGE ONE" } }
  entry.descPage = 1

  local presses = 0
  while game.stack:top() == entry and presses < 32 do
    game.press("a"); entry:update(0)
    presses = presses + 1
  end
  T.check(game.stack:top() ~= entry,
          "A alone gets out of a script-pushed entry")
  T.check(presses <= 4,
          "and gets out in a handful of presses, not a lap of the movelist")
end

do
  -- The description owns A while it has pages left, which is what A did on
  -- the vanilla page.  Only once it is spent does A move on.
  local game = fakeGame(SEEN, OWNED)
  local entry = entryFactory.new(game, "FIXMON_A")
  entry.desc = { { "PAGE ONE" }, { "PAGE TWO" } }
  entry.descPage = 1

  game.press("a"); entry:update(0)
  T.eq(entry.page, "dex", "A stays on the dex page while the text has more")
  T.eq(entry.descPage, 2, "and turns the description's page")

  game.press("a"); entry:update(0)
  T.eq(entry.page, "stats", "the spent description hands A on")

  -- and coming back round resets the description to its first page.  The page
  -- keys carry it round, because A stops at the last page rather than wrapping.
  game.press("right"); entry:update(0)
  game.press("right"); entry:update(0)
  T.eq(entry.page, "dex", "back on the dex page")
  T.eq(entry.descPage, 1, "with the description back at its start")
end

do
  -- A species you own but whose text the cache has no entry for still turns
  -- its pages: there are none, so A goes straight on rather than sticking.
  local game = fakeGame(SEEN, OWNED)
  local entry = entryFactory.new(game, "FIXMON_A")
  entry.desc = nil
  game.press("a"); entry:update(0)
  T.eq(entry.page, "stats", "no description means A moves on at once")
end

-- ------- UP/DOWN: species on the first pages, pages on the movelist

do
  local game = fakeGame(SEEN, OWNED)
  local entry = entryFactory.new(game, "FIXMON_A")
  game.press("down"); entry:update(0)
  T.eq(entry.species, "FIXMON_B", "DOWN steps to the next seen species")
  game.press("down"); entry:update(0)
  T.eq(entry.species, "FIXMON_A", "and wraps past the last one")
  game.press("up"); entry:update(0)
  T.eq(entry.species, "FIXMON_B", "UP wraps the other way")

  -- FIXMON_C was never seen, so the walk never lands on it
  game.press("down"); entry:update(0)
  T.neq(entry.species, "FIXMON_C", "an unseen species is never stepped onto")
end

do
  -- Stepping rebuilds everything derived, so the new species' own stats and
  -- movelist are what the next frame draws.
  local game = fakeGame(SEEN, OWNED)
  local entry = entryFactory.new(game, "FIXMON_A")
  local before = entry.stats.bst
  game.press("down"); entry:update(0)
  T.neq(entry.stats.bst, before, "the stats follow the species")
  T.eq(entry.stats.bst, exports.buildStats(Data, Data.pokemon.FIXMON_B).bst,
       "to the ones that species actually has")
end

do
  -- A dex with one species in it has nowhere to step, and must not move.
  local game = fakeGame({ FIXMON_A = true }, {})
  local entry = entryFactory.new(game, "FIXMON_A")
  game.press("down"); entry:update(0)
  T.eq(entry.species, "FIXMON_A", "a dex of one steps nowhere")
end

do
  local game = fakeGame(SEEN, OWNED)
  local entry = entryFactory.new(game, "FIXMON_A")
  entry.page = "moves"
  entry.moves = {}
  for i = 1, 20 do entry.moves[i] = { text = "ROW " .. i } end
  entry.movePage = 1
  T.eq(entry:movePages(), 3, "twenty rows are three pages of eight")

  game.press("down"); entry:update(0)
  T.eq(entry.movePage, 2, "DOWN turns the movelist's page")
  T.eq(entry.species, "FIXMON_A", "and does not step the species")
  game.press("down"); entry:update(0)
  game.press("down"); entry:update(0)
  T.eq(entry.movePage, 3, "the last page is where paging stops")
  game.press("up"); entry:update(0)
  T.eq(entry.movePage, 2, "UP turns it back")
end

-- ------- every page draws

do
  local game = fakeGame(SEEN, OWNED)
  local entry = entryFactory.new(game, "FIXMON_A")
  for _, page in ipairs({ "dex", "stats", "moves" }) do
    entry.page = page
    local ok, err = pcall(entry.draw, entry)
    T.check(ok, "the " .. page .. " page draws (" .. tostring(err) .. ")")
    T.check(pcall(entry.sgbPalettes, entry, game),
            "and the " .. page .. " page answers with a palette")
  end
end

do
  -- A species that is seen but not owned draws every page too: the dex page
  -- takes the branch that prints no height, weight or description.
  local game = fakeGame(SEEN, OWNED)
  local entry = entryFactory.new(game, "FIXMON_B")
  T.eq(entry.owned, false, "FIXMON B is seen but not owned")
  T.eq(entry.desc, nil, "so it has no description to print")
  for _, page in ipairs({ "dex", "stats", "moves" }) do
    entry.page = page
    T.check(pcall(entry.draw, entry), "a seen-only " .. page .. " page draws")
  end
end

do
  -- forceOwned is the starter-dex preview: the page prints as owned without
  -- the save saying so.
  local game = fakeGame({}, {})
  local entry = entryFactory.new(game, { species = "FIXMON_A", forceOwned = true })
  T.eq(entry.owned, true, "forceOwned shows the full page")
  T.check(pcall(entry.draw, entry), "and it draws")
end

do
  -- A species with no evolutions skips that block rather than heading an
  -- empty column, and a species with several takes the compact branch.
  local game = fakeGame(SEEN, OWNED)
  local entry = entryFactory.new(game, "FIXMON_B")
  entry.page = "stats"
  T.eq(#entry.stats.evolutions, 0, "FIXMON B evolves into nothing")
  T.check(pcall(entry.draw, entry), "and its stats page still draws")

  entry.stats.evolutions = {
    { label = "FIRE STONE", name = "FIXMON A" },
    { label = "WATER STONE", name = "FIXMON B" },
    { label = "THUNDERSTONE", name = "FIXMON C" },
  }
  T.check(pcall(entry.draw, entry), "and so does one with three of them")
end

-- ------- LEFT and RIGHT walk the pages
--
-- The keys the page turn belongs on: the pages sit beside each other, and a
-- reader one page too far has to be able to go back.

do
  local game = fakeGame(SEEN, OWNED)
  local entry = entryFactory.new(game, "FIXMON_A")
  T.eq(entry.page, "dex", "an entry opens on the dex page")

  game.press("right"); entry:update(0)
  T.eq(entry.page, "stats", "RIGHT turns to the stats page")
  game.press("right"); entry:update(0)
  T.eq(entry.page, "moves", "RIGHT turns to the movelist")
  game.press("right"); entry:update(0)
  T.eq(entry.page, "dex", "and wraps back round")

  game.press("left"); entry:update(0)
  T.eq(entry.page, "moves", "LEFT wraps the other way")
  game.press("left"); entry:update(0)
  T.eq(entry.page, "stats", "and walks back")
  game.press("left"); entry:update(0)
  T.eq(entry.page, "dex", "to where it started")
end

do
  -- LEFT/RIGHT do not wait for the description the way A does: they are page
  -- keys, and page three should not cost you reading page one.
  local game = fakeGame(SEEN, OWNED)
  local entry = entryFactory.new(game, "FIXMON_A")
  entry.desc = { { "PAGE ONE" }, { "PAGE TWO" } }
  entry.descPage = 1
  game.press("right"); entry:update(0)
  T.eq(entry.page, "stats", "RIGHT leaves an unread description behind")
  T.eq(entry.descPage, 1, "without turning it")

  -- and coming back resets it, however you arrive
  game.press("left"); entry:update(0)
  T.eq(entry.page, "dex", "LEFT comes back")
  T.eq(entry.descPage, 1, "with the description at its start")
end

do
  -- Arriving at MOVES resets its page whichever key brought you there, so a
  -- page cannot be entered two ways and be set up differently by one.
  local game = fakeGame(SEEN, OWNED)
  local entry = entryFactory.new(game, "FIXMON_A")
  entry.page = "moves"
  entry.moves = {}
  for i = 1, 20 do entry.moves[i] = { text = "ROW " .. i } end
  entry.movePage = 3

  game.press("left"); entry:update(0)
  T.eq(entry.page, "stats", "left off the movelist")
  game.press("right"); entry:update(0)
  T.eq(entry.page, "moves", "and back onto it")
  T.eq(entry.movePage, 1, "which opens on its first page again")
end

do
  -- On the movelist UP/DOWN page the list and LEFT/RIGHT still change page:
  -- the two do not collide.
  local game = fakeGame(SEEN, OWNED)
  local entry = entryFactory.new(game, "FIXMON_A")
  entry.page = "moves"
  entry.moves = {}
  for i = 1, 20 do entry.moves[i] = { text = "ROW " .. i } end
  entry.movePage = 1

  game.press("down"); entry:update(0)
  T.eq(entry.movePage, 2, "DOWN pages the movelist")
  T.eq(entry.page, "moves", "and stays on the page")
  game.press("right"); entry:update(0)
  T.eq(entry.page, "dex", "RIGHT still turns the page from there")
end

do
  -- Stepping species keeps the page you were reading: you were on stats, you
  -- still are, and the only thing that changed is whose stats they are.
  local game = fakeGame(SEEN, OWNED)
  local entry = entryFactory.new(game, "FIXMON_A")
  entry.page = "stats"
  game.press("down"); entry:update(0)
  T.eq(entry.species, "FIXMON_B", "DOWN stepped the species")
  T.eq(entry.page, "stats", "and left the page where it was")
end

-- ------- the sprite well: nothing runs into the description
--
-- A Gen 1 front sprite is at most 56x56 and the well is exactly that, but
-- nothing guarantees it -- HGSS_SPRITES, Gold_Silver_Sprites and the Crystal
-- frames ship whatever their authors drew.  A 64-pixel one drawn at 1:1 from
-- the top of the well ran eight pixels past the bottom of it, through the
-- rule at y=82 and into the description text under it.
--
-- C.fit is the guard, and it is asserted directly rather than through a draw,
-- because "did those pixels overlap" is not a question a headless draw can
-- answer.

do
  local C = assert(loadfile(DIR .. "/chrome.lua"))()({})
  local WELL_X, WELL_Y, WELL = 8, 24, 56
  local DESC_RULE_Y = 82

  local function fits(w, h, label)
    local x, y, scale, dw, dh = C.fit(w, h, WELL_X, WELL_Y, WELL, WELL)
    T.check(y >= WELL_Y, label .. ": starts inside the well")
    T.check(y + dh <= WELL_Y + WELL, label .. ": ends inside the well")
    T.check(y + dh <= DESC_RULE_Y, label .. ": clears the description rule")
    T.check(x >= WELL_X and x + dw <= WELL_X + WELL,
            label .. ": inside the well horizontally")
    T.check(scale > 0, label .. ": drawn at a real scale")
    return scale, dw, dh
  end

  fits(56, 56, "a vanilla 56x56 sprite")
  fits(64, 64, "an oversized 64x64 sprite")
  fits(96, 96, "a very large 96x96 sprite")
  fits(80, 40, "a wide sprite")
  fits(40, 80, "a tall sprite")
  fits(32, 32, "a small sprite")

  -- a sprite that already fits is never scaled UP: blowing a 32-pixel sprite
  -- up to 56 is a blurry 32-pixel sprite
  local scale = fits(32, 32, "a small sprite")
  T.eq(scale, 1, "a sprite that fits is drawn at 1:1")
  T.eq(select(1, fits(56, 56, "a vanilla sprite")), 1,
       "and so is one that exactly fills the well")

  -- an oversized one comes down by the tighter ratio, keeping its aspect
  local _, _, _, dw, dh = C.fit(64, 64, WELL_X, WELL_Y, WELL, WELL)
  T.eq(dw, 56, "a 64x64 sprite is scaled to the well's width")
  T.eq(dh, 56, "and its height")
  local _, _, _, wideW, wideH = C.fit(112, 56, WELL_X, WELL_Y, WELL, WELL)
  T.eq(wideW, 56, "a wide sprite is bounded by its width")
  T.eq(wideH, 28, "and keeps its aspect ratio")

  -- and the slack is shared, not all dumped above the picture
  local _, smallY = C.fit(32, 32, WELL_X, WELL_Y, WELL, WELL)
  T.eq(smallY, WELL_Y + 12, "a small sprite is centred, not floored")
  T.check(smallY - WELL_Y == (WELL_Y + WELL) - (smallY + 32),
          "with the same air above it as below")
end

-- ------- the chrome fits the screen it is drawn on

do
  local C = assert(loadfile(DIR .. "/chrome.lua"))()({})
  T.eq(C.BODY_TOP, 24, "the body starts under the header box")
  T.eq(C.BODY_BOTTOM, 119, "and ends before the footer box")
  T.eq(C.BODY_BOTTOM - C.BODY_TOP + 1, 96, "96 pixels of body")
  T.eq(96 % 16, 0, "which is a whole number of 16-pixel rows")
  T.eq(96 / 16, 6, "six of them")
  T.eq(96 % 12, 0, "and of 12-pixel rows")

  -- the view/page indicator has to fit the margin it is right-aligned into
  T.eq(C.pipsWidth(3), 21, "three pips are 21 pixels")
  T.check(C.RIGHT - C.pipsWidth(3) > 8 + 14 * 8,
          "which clears the longest list title")
end

-- ------- the list is six rows, and the icons still land on tiles

do
  local game = fakeGame(SEEN, OWNED)
  local list = listFactory.new(game)

  -- Asked, not read: on the screen the engine has now `rows` is a method,
  -- and it answers the six capped by however many entries are in the list.
  -- The fixture dex has three, so a list padded out to seven is what this is
  -- really guarding -- the vanilla count must never be what comes back.
  local function rows(screen)
    if type(screen.rows) == "function" then return screen:rows() end
    return screen.rows
  end
  T.eq(rows(list), math.min(6, #list.items),
       "the boxed list draws its six rows, not the vanilla seven")

  local padded = listFactory.new(fakeGame(SEEN, OWNED))
  for i = #padded.items + 1, 9 do
    padded.items[i] = { label = ("%03d PAD"):format(i), species = "FIXMON_A",
                        seen = false }
  end
  T.eq(rows(padded), 6, "and stops at six once there are more rows than that")

  -- the scroll clamp has to agree with the row count, or the cursor walks off
  -- the bottom of the box
  padded.index = 6
  padded.scroll = 0
  T.check(padded.index - padded.scroll <= rows(padded),
          "six rows of cursor fit without scrolling")
end

-- ------- the entry the onDone contract promises

do
  local game = fakeGame(SEEN, OWNED)
  local fired = false
  local entry = entryFactory.new(game, "FIXMON_A", function() fired = true end)
  game.stack:push(entry)
  game.press("b"); entry:update(0)
  T.check(fired, "onDone runs when the entry closes")
end

-- ------- the START menu row says DEX
--
-- Through the engine's own StartMenu rather than the hook alone: what is
-- being asserted is what the player reads off the overworld menu, and that
-- is the whole list the engine builds, not the shape of one callback.

do
  local StartMenu = require("src.ui.StartMenu")

  -- the dex row is gated on Oak having handed the thing over
  local function startGame()
    local game = fakeGame(SEEN, OWNED)
    game.save.flags = { EVENT_GOT_POKEDEX = true }
    game.save.options = {}
    return game
  end

  local game = startGame()
  local menu = StartMenu.new(game)
  local labels = {}
  for i, item in ipairs(menu.items) do labels[i] = item.label end

  T.eq(labels[1], "DEX", "the START menu's first row reads DEX")
  for _, label in ipairs(labels) do
    T.neq(label, "POK\195\169DEX", "and no row still reads POK\195\169DEX")
  end

  -- the rename is a rename: every other row, and the order, are untouched
  -- (no LINK here -- the engine lists that one only with a party)
  T.same(labels,
         { "DEX", "POK\195\169MON", "ITEM", "RED", "SAVE", "OPTION", "QUIT" },
         "the rest of the START menu is exactly as the engine built it")

  -- and it still opens the dex: the row's own onSelect is the engine's
  menu.items[1].onSelect()
  T.eq(type(game.stack:top()), "table", "the row still pushes a screen")

  -- START SAYS DEX off hands the engine's row back untouched.  The option is
  -- read when the menu opens rather than once at load, so the same loaded
  -- mod answers both ways: mod.options:get reads loader.modOptions.
  local id = run.mod.manifest.id
  run.loader.modOptions[id] = { dex_label = false }
  T.eq(StartMenu.new(startGame()).items[1].label, "POK\195\169DEX",
       "START SAYS DEX off leaves the engine's row alone")

  run.loader.modOptions[id] = { dex_label = true }
  T.eq(StartMenu.new(startGame()).items[1].label, "DEX",
       "and back on renames it again, without a reload")
  run.loader.modOptions[id] = nil
end

T.finish("Gen1Dex")

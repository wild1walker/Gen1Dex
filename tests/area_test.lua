-- Standalone: luajit mods/Gen1Dex/tests/area_test.lua
--
-- The AREA surface (area.lua): the caption under the map, the presses that
-- take it down and put it back, the d-pad that works again while it is down,
-- and A on an entry you have never met.
--
-- This shipped inside Gen151 first, where it had to reach a dex list it did
-- not own from the outside.  It lives here now, so the tests live here too --
-- and the half that is Gen151's (its placement text, and MEW's sealed
-- caption) is tested there, through the provider hook at the bottom of this
-- file.
--
-- Run it from a Gen1Recomp checkout with this mod at mods/Gen1Dex, or set
-- GEN1DEX_DIR to wherever it lives.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local check, eq = T.check, T.eq
local Font = require("src.render.Font")

local DIR = os.getenv("GEN1DEX_DIR") or "mods/Gen1Dex"

-- The box, in the pixels Font.drawBox fills for 0,14 x 20,4 in tiles.  The
-- HEIGHT is the assertion worth having: a six-row dialogue box passes every
-- other check here and still eats two more tile rows of Kanto than it needs.
local BOX_X, BOX_Y, BOX_W, BOX_H = 0, 112, 160, 32
local ARROW_X = (0 + 20 - 2) * 8
local HEADER_COLS = 19

-- A long name, put on the route so it has a nest to blink: the nest header
-- is the one vanilla still writes, and the one this has to shorten.
local LONG = "FIXMONOSAURUS"

-- And a species in no encounter table and no evolution chain -- the shape of
-- MOLTRES on the real cartridge, and of MEW behind Gen151's gate.
local NOBODY = "FIXMON_D"

local Data = T.fixtures.fresh()
Data.pokemon[LONG] = {
  id = LONG, index = 4, dex = 4, name = LONG,
  types = { "NORMAL" }, evolutions = {},
  baseStats = { hp = 1, attack = 1, defense = 1, speed = 1, special = 1 },
}
-- one slot on the fixture's route, so the screen has a nest to blink and a
-- caption to draw: a screen with neither never installs the strip at all
table.insert(Data.encounters.FIX_ROUTE.grass.slots,
  { level = 9, species = LONG })

Data.pokemon[NOBODY] = {
  id = NOBODY, index = 5, dex = 5, name = "FIXMON D",
  types = { "NORMAL" }, evolutions = {},
  baseStats = { hp = 1, attack = 1, defense = 1, speed = 1, special = 1 },
}

local run = T.sdk.loadMod(DIR, { data = Data })
eq(#run.errors, 0, "loads clean (" .. tostring(run.errors[1]) .. ")")
local exports = run.loader.exports[run.mod.manifest.id]
local area = exports and exports.area
check(area ~= nil, "the AREA surface is published for other mods")
check(type(area.provide) == "function", "with a provider hook")
check(type(area.caption) == "function", "and the caption it would draw")

local TownMap = require("src.ui.TownMap")

local function newStack()
  local stack = { states = {} }
  function stack:push(state) table.insert(self.states, state) end
  function stack:pop() return table.remove(self.states) end
  function stack:top() return self.states[#self.states] end
  return stack
end

local pressed = {}
local function fakeGame(seen, owned)
  return {
    data = Data,
    save = {
      pokedex = { seen = seen or {}, owned = owned or {} },
      player = { name = "RED", id = 1 },
      party = {}, flags = {}, inventory = {},
    },
    stack = newStack(),
    input = {
      wasPressed = function(_, key) return pressed[key] == true end,
      isDown = function(_, key) return pressed[key] == true end,
    },
  }
end
local function press(key) pressed = { [key] = true } end

local game = fakeGame({}, {})

-- ------- what the box says, when nobody has told it anything
--
-- Both readings are made out of tables the game already has, so they are
-- right by construction and cost this mod no data of its own.

do
  local wild = area.caption(game, "FIXMON_A")
  check(type(wild) == "table", "a wild species is captioned from the "
    .. "encounter tables")
  eq(wild and wild[1], "GRASS  Lv3", "naming how and roughly what level")
  eq(wild and wild[2], "COMMON",
    "and how often, off the slot's own share of the map")

  -- FIXMON_B is in no encounter table anywhere.  The dex still owes the
  -- player an answer and the evolution table has one.
  local evolved = area.caption(game, "FIXMON_B")
  check(type(evolved) == "table",
    "a species that is wild nowhere is captioned from the evolution table")
  eq(evolved and evolved[1], "EVOLVE FIXMON A", "naming what it comes from")
  eq(evolved and evolved[2], "AT LV16", "and what that costs")

  eq(area.caption(game, "NOT_A_SPECIES"), nil,
    "and a species neither table knows has no answer at all")
  eq(area.caption(game, NOBODY), nil,
    "nor does one that is in no wild table and evolves from nothing")
end

-- ------- and what the box says when nobody can answer
--
-- A blank screen cannot be told apart from a broken one.  The four
-- legendaries are statics and live in no wild table, so on the real cartridge
-- this is what AREA on MOLTRES draws.

do
  check(type(area.unknown) == "table" and area.unknown[1] ~= nil,
    "the words for an unanswerable species are published")

  local screen = TownMap.new(game, { nestSpecies = NOBODY })
  check(rawget(screen, "draw") ~= nil,
    "a species nobody can answer for still gets the box")
  screen.game = game

  local drawn = {}
  local realDraw = Font.draw
  Font.draw = function(text, x, y)
    drawn[#drawn + 1] = { text = tostring(text), y = y }
    return realDraw(text, x, y)
  end
  screen:draw()
  Font.draw = realDraw

  local body = {}
  for _, d in ipairs(drawn) do
    if d.y >= 96 then body[#body + 1] = d.text end
  end
  eq(body[1], area.unknown[1], "saying so on its first line")
  eq(body[2], area.unknown[2], "and on its second")
  for index, line in ipairs(area.unknown) do
    local budget = index == 1 and 18 or 17
    check(Font.spansFitting(Font.split(line), budget * 8) >= #Font.split(line),
      ("and both lines fit the box, unlike %q"):format(line))
  end
end

-- ------- and what another mod gets to say
--
-- The whole reason this is a registry rather than a fixed pair of readings:
-- a mod that ADDS a spawn knows the tier it rolled it at and the HM the
-- player needs to get there, and the encounter tables carry neither.

do
  local calls = {}
  local remove = area.provide(function(_, species)
    calls[#calls + 1] = species
    if species == "FIXMON_A" then return { "SUPER ROD  Lv15", "VERY RARE" } end
    if species == "FIXMON_C" then return false end
    return nil
  end)

  local ours = area.caption(game, "FIXMON_A")
  eq(ours and ours[1], "SUPER ROD  Lv15",
    "a provider outranks the built-in reading of the same species")
  eq(ours and ours[2], "VERY RARE", "on both lines")

  eq(area.caption(game, "FIXMON_C"), nil,
    "false is the seal: the species is answered by nobody, not even the "
      .. "encounter tables that could have")

  local fallthrough = area.caption(game, "FIXMON_B")
  eq(fallthrough and fallthrough[1], "EVOLVE FIXMON A",
    "and nil is no opinion, so the built-in reading still answers")
  check(#calls >= 3, "every caption asked the provider first")

  -- second in, first asked, and the first non-nil answer wins
  local second = area.provide(function(_, species)
    if species == "FIXMON_B" then return { "SOMEWHERE ELSE" } end
    return nil
  end)
  local both = area.caption(game, "FIXMON_A")
  eq(both and both[1], "SUPER ROD  Lv15",
    "with two providers registered the first one with an opinion wins")
  eq(area.caption(game, "FIXMON_B")[1], "SOMEWHERE ELSE",
    "and the second answers what the first passed on")
  second()

  -- The box owns its own width: a provider that hands over a line too long
  -- for it gets it cut rather than drawn through the frame, and the second
  -- line is cut a column earlier because the blinking prompt sits there.
  local wide = area.provide(function(_, species)
    if species ~= "FIXMON_B" then return nil end
    return { ("W"):rep(40), ("W"):rep(40) }
  end)
  local cut = area.caption(game, "FIXMON_B")
  check(type(cut) == "table" and cut[2] ~= nil, "a too-wide caption still draws")
  check(Font.spansFitting(Font.split(cut[1]), 18 * 8) >= #Font.split(cut[1]),
    "with its first line cut to the box interior")
  check(#cut[2] < #cut[1],
    "and its second cut a column shorter, for the prompt that sits there")
  wide()

  -- A provider that throws is dropped rather than taking the POKéDEX with
  -- it: a mod that cannot caption a species is a missing line.
  local boom = area.provide(function() error("no") end)
  local survived = area.caption(game, "FIXMON_B")
  eq(survived and survived[1], "EVOLVE FIXMON A",
    "a provider that throws is skipped and the screen still answers")
  boom()

  remove()
  local back = area.caption(game, "FIXMON_A")
  eq(back and back[1], "GRASS  Lv3",
    "and unregistering hands the species back to the built-in reading")
  eq(area.caption(game, "FIXMON_C")[1], "GRASS  Lv4",
    "seal included")
end

-- ------- the strip, and the presses that take it down and put it back

do
  local screen = TownMap.new(game, { nestSpecies = "FIXMON_A" })
  check(type(screen) == "table", "the AREA screen builds")
  check(screen.draw ~= TownMap.draw,
    "and is captioned -- the wrap installs an instance draw of its own")
  screen.game = game

  local popped = false
  game.stack = newStack()
  game.stack.pop = function(self) popped = true return table.remove(self.states) end
  screen.game = game

  local painted = 0
  local realRect = love.graphics.rectangle
  love.graphics.rectangle = function(mode, x, y, w, h)
    if x == BOX_X and y == BOX_Y and w == BOX_W and h == BOX_H then
      painted = painted + 1
    end
    return realRect(mode, x, y, w, h)
  end

  screen:draw()
  eq(painted, 1, "the box is on screen to begin with, four rows tall")

  press("a")
  screen:update(0)
  check(not popped,
    "the first A takes the hint down rather than closing the map")
  painted = 0
  screen:draw()
  eq(painted, 0, "and the box really is gone")

  press("start")
  screen:update(0)
  check(not popped, "START does not close the map")
  painted = 0
  screen:draw()
  eq(painted, 1, "it brings the hint back")

  press("a")
  screen:update(0)
  check(not popped, "A dismisses the reopened hint")
  painted = 0
  screen:draw()
  eq(painted, 0, "which goes away again")

  screen:update(0)
  check(popped, "and only THEN does A close it, the way A always did")
  love.graphics.rectangle = realRect
end

-- ------- with the hint down, the screen is the plain town map again
--
-- Vanilla's AREA branch answers A and B and nothing else, and returns from
-- draw before it reaches the cursor or the name banner.  So a player who
-- dismissed the hint was left looking at a map they could not read or move
-- around.

do
  local nav = TownMap.new(game, { nestSpecies = "FIXMON_A" })
  nav.game = game
  check(type(nav.locs) == "table" and #nav.locs > 1,
    "nav: the map has locations to move between")
  eq(nav.mode, "grid", "nav: and is the real grid, not the fallback list")
  -- The fixture ships no Kanto art, so TownMap loaded no background and its
  -- draw takes the fall-through path instead of the AREA branch.  An empty
  -- tilemap is enough to put it back on the branch the player sees: the blit
  -- loop runs zero times and the AREA code after it runs for real.
  nav.bg = nav.bg or { map = {} }

  press("a")
  nav:update(0)                       -- dismiss the hint first

  local DELTA = { down = { 0, 1 }, up = { 0, -1 },
                  right = { 1, 0 }, left = { -1, 0 } }
  local moved, wrongWay = {}, {}
  for _, dir in ipairs({ "down", "up", "right", "left" }) do
    local from = nav.locs[nav.sel]
    press(dir)
    -- the crash this replaced: TownMap has no moveGrid, so the first d-pad
    -- press on the AREA map used to raise rather than move anything
    local ok, err = pcall(nav.update, nav, 0)
    check(ok, "nav: " .. dir .. " is answered without raising: " .. tostring(err))
    local to = nav.locs[nav.sel]
    if to ~= from then
      moved[#moved + 1] = dir
      -- and it has to be a move THAT WAY: nearest in the direction pressed,
      -- not nearest overall
      local dx, dy = DELTA[dir][1], DELTA[dir][2]
      if from.x and to.x then
        local along = (to.x - from.x) * dx + (to.y - from.y) * dy
        if along <= 0 then wrongWay[#wrongWay + 1] = dir end
      end
    end
  end
  check(#moved > 0,
    "nav: the d-pad moves the selection, where vanilla ignored it")
  eq(#wrongWay, 0, "nav: and every move goes the way the key pointed")

  local strip
  local realDraw = Font.draw
  Font.draw = function(text, x, y)
    if y == 0 then strip = tostring(text) end
    return realDraw(text, x, y)
  end
  nav:draw()
  Font.draw = realDraw
  eq(strip, nav:bannerText(nav.locs[nav.sel]),
    "nav: and the top strip names the selected place")

  local back = 0
  local realRect = love.graphics.rectangle
  love.graphics.rectangle = function(mode, x, y, w, h)
    if x == BOX_X and y == BOX_Y and w == BOX_W and h == BOX_H then
      back = back + 1
    end
    return realRect(mode, x, y, w, h)
  end
  nav:draw()
  eq(back, 0, "nav: the hint is still down while navigating")
  press("start")
  nav:update(0)
  back = 0
  nav:draw()
  love.graphics.rectangle = realRect
  eq(back, 1, "nav: START brings it back over the map it was navigating")
end

-- ------- nothing the text draws may reach the column the prompt sits in
--
-- The bug this is here for: the second line was budgeted the full 18 columns
-- of box interior, and the arrow is drawn in the eighteenth.  "VERY RARE  2
-- SPOTS" is exactly 18, so the arrow landed on the final S.  Measured
-- through a real draw rather than by counting the string, because what
-- collides is pixels.

do
  local remove = area.provide(function(_, species)
    if species ~= "FIXMON_A" then return nil end
    -- the widest thing a caption has ever wanted to say, on both lines
    return { "SUPER ROD  Lv15-25", "VERY RARE  2 SPOTS" }
  end)

  -- The SECOND line is the one that has to stay out of the way: the arrow
  -- is drawn four pixels above the box's last row, which is that line's own
  -- row and not the first line's.
  local LINE2_Y = (14 + 2) * 8
  local worst, widest, arrowAt = 0, nil, nil
  local realDraw, realCode = Font.draw, Font.drawCode
  Font.draw = function(text, x, y)
    if y == LINE2_Y then
      local width = 0
      for _, span in ipairs(Font.split(tostring(text))) do
        width = width + Font.advanceOf(span.code)
      end
      if x + width > worst then worst, widest = x + width, tostring(text) end
    end
    return realDraw(text, x, y)
  end
  Font.drawCode = function(code, x, y)
    if y >= 96 then arrowAt = x end
    return realCode(code, x, y)
  end

  local one = TownMap.new(game, { nestSpecies = "FIXMON_A" })
  one.game = game
  one.blink = 0                       -- arrow showing
  one:draw()
  Font.draw, Font.drawCode = realDraw, realCode
  remove()

  eq(arrowAt, ARROW_X, "arrow: the prompt is in the box's last-but-one cell")
  check(worst > 0, "arrow: there was a second line to measure")
  check(worst <= ARROW_X,
    ("arrow: the widest caption line ends at %d, which reaches the prompt "
      .. "cell at %d -- %q"):format(worst, ARROW_X, tostring(widest)))
end

-- ------- and the header is made to fit
--
-- Vanilla writes into a 19-column strip without measuring: "CHARIZARD AREA
-- UNKNOWN" is 22 and ran off the right edge of the screen mid-word.

do
  local realDraw = Font.draw
  local function headerOf(species)
    local drawn
    Font.draw = function(text, x, y)
      if y == 0 then drawn = tostring(text) end
      return realDraw(text, x, y)
    end
    local screen = TownMap.new(game, { nestSpecies = species })
    screen.game = game
    screen:draw()
    Font.draw = realDraw
    return drawn
  end

  -- ---- the nest line is the engine's, and only shortened when it overflows
  local long = headerOf(LONG)
  check(long ~= nil, "a nest header was drawn for a name vanilla would "
    .. "overflow")
  if long then
    check(Font.spansFitting(Font.split(long), HEADER_COLS * 8)
            >= #Font.split(long),
      ("and it fits the strip, unlike %q"):format(long))
    check(long:find(LONG, 1, true) ~= nil,
      "while still naming the POKéMON, got " .. long)
  end
  eq(headerOf("FIXMON_A"), nil,
    "and a nest line that already fits is left to the engine")

  -- ---- the unknown line is ALWAYS ours: "<NAME> AREA UNKNOWN" is twelve
  -- glyphs plus the name, so it ran off the edge for every name of eight or
  -- more -- MOLTRES, ARTICUNO, half the dex.  AREA is the word that goes:
  -- the screen is already called AREA and it was carrying nothing.
  local unknown = headerOf(NOBODY)
  eq(unknown, "FIXMON D UNKNOWN",
    "an unknown location says just that, without the AREA that overflowed it")
  check(Font.spansFitting(Font.split(unknown), HEADER_COLS * 8)
          >= #Font.split(unknown),
    "and it fits the strip")
end

-- ------- A on an entry you have never met

do
  local Screens = require("src.ui.Screens")
  local unseen = fakeGame({ FIXMON_A = true }, {})
  local list = Screens.get(unseen, "PokedexMenu").new(unseen, {})
  check(type(list) == "table" and type(list.items) == "table",
    "the dex list builds through the registry")

  local unknown
  for _, item in ipairs(list.items or {}) do
    if not item.value then unknown = item break end
  end
  check(unknown ~= nil, "with an undiscovered entry in it")
  check(unknown == nil or type(unknown.species) == "string",
    "whose row names its species even unseen")

  list.onChoose(unknown, list)
  local menu = unseen.stack:top()
  check(menu ~= nil, "choosing it opens something, where vanilla returns "
    .. "early and opens nothing")
  local labels = {}
  for _, entry in ipairs((menu or {}).items or {}) do
    labels[#labels + 1] = entry.label
  end
  eq(labels[1], "AREA", "whose first row is AREA")
  eq(labels[2], "QUIT",
    "and whose second is QUIT -- DATA on a POKéMON you have never met would "
      .. "hand over the dex paragraph, which nobody asked for")

  -- and AREA opens the map on the species the ROW named, not on whatever
  -- species sits at that position in the vanilla dex order
  local before = #unseen.stack.states
  menu.items[1].onSelect()
  check(#unseen.stack.states > before, "AREA opens a screen")
  local opened = unseen.stack:top()
  eq(opened and opened.nestSpecies, unknown.species,
    "on the species the row is actually for")

  -- the probe a bench prints, from the list the game would really build
  local report = area.probe(unseen)
  check(type(report) == "string" and report:find("unseen rows", 1, true),
    "and the probe reports the chain as live: " .. tostring(report))
end

-- ------- and both halves can be turned off
--
-- Read when the screen opens rather than once at load, so the same loaded
-- mod answers both ways: mod.options:get reads loader.modOptions.

do
  local id = run.mod.manifest.id

  run.loader.modOptions[id] = { area_hints = false }
  local bare = TownMap.new(game, { nestSpecies = "FIXMON_A" })
  -- rawget, because every TownMap answers .draw through its metatable; what
  -- the wrap installs is an INSTANCE field over the top of it
  eq(rawget(bare, "draw"), nil,
    "AREA HINTS off leaves the AREA screen exactly as the engine built it")

  run.loader.modOptions[id] = { area_unseen = false }
  local unseen = fakeGame({ FIXMON_A = true }, {})
  local list = require("src.ui.Screens").get(unseen, "PokedexMenu")
    .new(unseen, {})
  eq(list.__gen1dexArea, nil,
    "AREA ON UNSEEN off hands the press back to the engine")
  local blank
  for _, item in ipairs(list.items or {}) do
    if not item.value then blank = item break end
  end
  if blank then
    list.onChoose(blank, list)
    eq(unseen.stack:top(), nil, "which is to say it opens nothing, as vanilla")
  end
  local report = area.probe(unseen)
  check(type(report) == "string" and report:find("AREA ON UNSEEN", 1, true),
    "and the probe says which option turned it off: " .. tostring(report))

  run.loader.modOptions[id] = nil
end

run.release()
T.finish("Gen1Dex AREA")

-- Standalone: luajit mods/Gen1Dex/tests/naming_test.lua
--
-- The nickname prompt after a catch (naming.lua): the dex entry that stays up
-- behind the box for a species the dex has never held, the battle field that
-- stays up behind it for anything else, and the promise that the prompt itself
-- is untouched -- same box, same words, same YES/NO.
--
-- Run it from a Gen1Recomp checkout with this mod at mods/Gen1Dex, or set
-- GEN1DEX_DIR to wherever it lives.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local check, eq, neq = T.check, T.eq, T.neq
local Font = require("src.render.Font")
local Runtime = require("src.mods.Runtime")

local DIR = os.getenv("GEN1DEX_DIR") or "mods/Gen1Dex"
local Data = T.fixtures.fresh()
local run = T.sdk.loadMod(DIR, { data = Data })
eq(#run.errors, 0, "loads clean (" .. tostring(run.errors[1]) .. ")")

local BattleState = require("src.battle.BattleState")
local entryFactory = Data.screens and Data.screens.DexEntryMenu
check(entryFactory ~= nil and type(entryFactory.new) == "function",
  "the entry screen is registered, which is the page this keeps up")

-- ------- the wrap
--
-- The pristine method is parked on the class under a key of this mod's own so
-- that a hot reload wraps the ORIGINAL rather than the last wrap.  Reading it
-- here is reading this mod's own bookkeeping, not the engine's.

local PRISTINE = "__gen1dex_pristine_askNicknameUI"
local pristine = rawget(BattleState, PRISTINE)
check(type(pristine) == "function", "the engine's nickname prompt is wrapped")
neq(BattleState.askNicknameUI, pristine, "and the wrap is what a battle calls")

-- ------- a stub battle
--
-- askNicknameUI reads the battle's data (romText) and its game (the box), and
-- writes the two fields AskName sets.  Nothing else of a battle is involved in
-- asking the question, so nothing else is built here.

local function newStack()
  local stack = { states = {} }
  function stack:push(state) table.insert(self.states, state) end
  function stack:pop() return table.remove(self.states) end
  function stack:top() return self.states[#self.states] end
  return stack
end

local function fakeGame(owned)
  return {
    data = Data,
    save = {
      pokedex = { seen = owned or {}, owned = owned or {} },
      player = { name = "RED", id = 1 },
      party = {}, flags = {},
    },
    stack = newStack(),
    input = {
      wasPressed = function() return false end,
      isDown = function() return false end,
    },
  }
end

local function fakeBattle(game)
  return setmetatable({ game = game, data = Data },
                      { __index = BattleState })
end

local function newMon(species)
  return { species = species, level = 5, hp = 10, maxHp = 10, moves = {} }
end

-- The catch, as the engine emits it once the mon is in the party or the box:
-- the queue rows for the dex page and for the prompt are already in the queue
-- and neither has run, which is what makes this arming land in time.
local function caught(mon, isNew)
  Runtime.emit("pokemon.caught",
    { mon = mon, species = mon.species, isNew = isNew, destination = "party" })
end

-- Everything Font.draw puts on the screen for one frame of the box.  The
-- dialogue box draws its own text a glyph at a time (Font.drawCode), so what
-- comes back here is the backdrop and nothing else.
local function textDrawnBy(box)
  local drawn = {}
  local real = Font.draw
  Font.draw = function(text, x, y)
    drawn[#drawn + 1] = tostring(text)
    return real(text, x, y)
  end
  local ok, err = pcall(box.draw, box)
  Font.draw = real
  check(ok, "the box draws (" .. tostring(err) .. ")")
  return drawn
end

local function drew(drawn, text)
  for _, line in ipairs(drawn) do
    if line == text then return true end
  end
  return false
end

local NAME_A = Data.pokemon.FIXMON_A.name
local NAME_C = Data.pokemon.FIXMON_C.name

-- ------- a species the dex has never held: the page stays up

do
  local game = fakeGame({ FIXMON_A = true })
  local mon = newMon("FIXMON_A")
  -- the page the engine puts up between the catch and the prompt
  entryFactory.new(game, "FIXMON_A")
  caught(mon, true)

  local battle = fakeBattle(game)
  local box = battle:askNicknameUI(mon, NAME_A)
  check(type(box) == "table", "the prompt is still a box")
  eq(type(box.choice), "function", "still carrying its YES/NO")
  eq(battle.blankForAskName, true,
    "and the engine's own white field is still the floor it is drawn on")

  local drawn = textDrawnBy(box)
  check(drew(drawn, NAME_A), "the entry it just closed is drawn behind it")
  check(drew(drawn, "DEX"), "on the page the player was reading")
  check(type(box.sgbPalettes) == "function",
    "and the box answers for the colours, or the page wears the battle's")
  local zones = box:sgbPalettes(game)
  check(type(zones) == "table" and #zones > 0,
    "with the entry's own zones")
end

-- ------- through the engine's own queue
--
-- The order this rests on: BattleState:offerNickname puts the prompt in the
-- battle queue as a UI row, pokemon.caught is emitted once the mon is in the
-- party -- after the row is queued and before any of it has run -- and the row
-- builds the box some frames later.  Driven here the way the engine drives it,
-- because an arming that landed a row too late would still pass every case
-- above.

do
  local game = fakeGame({ FIXMON_A = true })
  local mon = newMon("FIXMON_A")
  entryFactory.new(game, "FIXMON_A")

  local battle = fakeBattle(game)
  battle.queue, battle.nextInsert = {}, 0
  eq(battle:offerNickname(mon, NAME_A), true, "the prompt is queued as a row")
  caught(mon, true)

  local row = battle.queue[1]
  check(type(row) == "table" and type(row.ui) == "function",
    "and the row builds the box when the queue reaches it")
  check(drew(textDrawnBy(row.ui()), NAME_A),
    "with the entry behind it, armed a row earlier")
end

-- ------- one catch, one page

do
  local game = fakeGame({ FIXMON_A = true })
  local mon = newMon("FIXMON_A")
  entryFactory.new(game, "FIXMON_A")
  caught(mon, true)

  local battle = fakeBattle(game)
  battle:askNicknameUI(mon, NAME_A)

  -- the same mon asked after twice: the arming is spent, and a second prompt
  -- is a prompt no dex page came up for
  local again = battle:askNicknameUI(mon, NAME_A)
  eq(#textDrawnBy(again), 0, "a second prompt draws no page")
  eq(again.sgbPalettes, nil, "and answers for no colours of its own")
  eq(battle.blankForAskName, false, "it takes the battle instead")
end

-- ------- a species the dex already holds keeps the battle instead
--
-- No page came up for it, so there is no page to keep up -- and the screen the
-- question interrupts is the field it was caught on, ball and all.

do
  local game = fakeGame({ FIXMON_A = true })
  local mon = newMon("FIXMON_A")
  entryFactory.new(game, "FIXMON_A")
  caught(mon, false)

  local battle = fakeBattle(game)
  local ball = { "the resting closed ball" }
  battle.lockedBall = ball
  local box = battle:askNicknameUI(mon, NAME_A)

  eq(battle.blankForAskName, false, "the field is kept rather than wiped")
  eq(battle.lockedBall, ball,
    "with the ball AskName's ClearSprites had just taken off it")
  eq(#textDrawnBy(box), 0, "and no dex page is conjured in front of it")
  eq(box.sgbPalettes, nil, "the battle owns the colours, as it always did")

  -- and the ClearSprites, moved to where the sprites are finished with
  box.choice(false)
  eq(battle.lockedBall, nil, "the ball comes off once the question is answered")
end

-- ------- and a prompt for a mon this catch was not about

do
  local game = fakeGame({ FIXMON_A = true })
  local mon = newMon("FIXMON_A")
  entryFactory.new(game, "FIXMON_A")
  caught(mon, true)

  local other = newMon("FIXMON_A")
  local battle = fakeBattle(game)
  local box = battle:askNicknameUI(other, NAME_A)
  eq(#textDrawnBy(box), 0, "the arming is held by identity, not by species")
  eq(battle.blankForAskName, false, "so that prompt takes the battle")
end

-- ------- the page comes back on the POKéMON that was caught
--
-- UP/DOWN on the entry walks the species you have seen, so the page a player
-- closes is not necessarily the page it was opened on -- and the box is about
-- to ask after this one by name.

do
  local game = fakeGame({ FIXMON_A = true, FIXMON_C = true })
  local mon = newMon("FIXMON_A")
  local page = entryFactory.new(game, "FIXMON_A")
  page:setSpecies("FIXMON_C", false)
  page:goTo("stats")
  caught(mon, true)

  local drawn = textDrawnBy(fakeBattle(game):askNicknameUI(mon, NAME_A))
  eq(page.species, "FIXMON_A", "the entry is put back on the caught species")
  check(drew(drawn, NAME_A), "which is the name in the header")
  check(not drew(drawn, NAME_C), "not the one it was left on")
  check(drew(drawn, "STATS"), "and the page it was left on survives")
end

-- ------- the option

-- Read when the prompt opens rather than once at load, so the same loaded mod
-- answers both ways: mod.options:get reads loader.modOptions.

do
  local id = run.mod.manifest.id
  run.loader.modOptions[id] = { nickname_backdrop = false }

  local game = fakeGame({ FIXMON_A = true })
  local mon = newMon("FIXMON_A")
  entryFactory.new(game, "FIXMON_A")
  caught(mon, true)

  local battle = fakeBattle(game)
  local box = battle:askNicknameUI(mon, NAME_A)
  eq(#textDrawnBy(box), 0, "NAME IN PLACE off asks over the white field")
  eq(box.sgbPalettes, nil, "and takes the colours back with it")
  eq(battle.blankForAskName, true, "which is the field the engine wiped to")

  run.loader.modOptions[id] = nil
end

run.release()
T.finish("Gen1Dex naming")

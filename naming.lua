-- Gen1Dex: the nickname prompt, over the entry it just closed.
--
-- Returns a factory: factory(mod, C, Entry) -> a table with an install(),
-- which main.lua calls once the entry screen has been registered.
--
-- ------- the white field this takes away
--
-- Catch something the dex has never held and the game shows you its entry,
-- and then asks whether you want to give it a nickname.  The second question
-- is asked over a blank white screen: AskName (engine/menus/naming_screen.asm)
-- clears the sprites and wipes the field before it prints, so the entry you
-- were reading a frame ago is gone and the POKéMON you are being asked to
-- name is not on the screen while you name it.
--
-- On the cartridge that was the only affordable answer -- the dex page and the
-- battle are two different tilemaps and the Game Boy has one of those.  There
-- is no such bill here, so the page stays up: the dialogue box and its YES/NO
-- come up OVER the entry, which is what the player thinks is happening anyway.
-- Nothing about the prompt itself moves.  The box is the engine's own box, in
-- the same place, with the same words and the same two rows in the corner; the
-- only difference is what is behind it.
--
-- ------- only the catch that brought the page up
--
-- The prompt comes up for every catch; the dex page comes up only for a
-- species the dex has never held.  So this backdrop is armed by the CATCH
-- rather than by the prompt -- pokemon.caught carries `isNew`, which is the
-- same bit the engine queued the dex page on -- and a catch that never showed
-- a page still gets the white field the cartridge drew.  Keeping a page up is
-- one thing; conjuring one in front of a player who was never shown it is
-- another, and it is not what was asked for.
--
-- And it is the SAME screen instance, not a fresh one built to look like it:
-- the page a player left on STATS comes back on STATS, no cry plays a second
-- time, and no sprite is loaded twice.  The one thing that is put back is the
-- species, because UP/DOWN on the entry walks the ones you have seen and the
-- box is about to ask after a particular POKéMON by name.
--
-- ------- what it costs
--
-- BattleState.askNicknameUI is engine code with no hook on it, so it is
-- reached for directly -- the second thing this mod's engine_internals
-- permission buys, after TownMap in area.lua, and it is spent the same way.
-- The method is not replaced: the original is called, the box it built is the
-- box that is returned, and the backdrop is installed as instance fields over
-- it, so the engine's own draw runs untouched underneath.  Nothing is pushed
-- on the state stack and nothing is popped off it: the battle's queue waits on
-- being the top of the stack again (BattleState:updateQueue), and a screen of
-- this mod's own left sitting under the prompt would be a screen the battle
-- waits behind forever.  A backdrop is worth a lot less than that.

return function(mod, C, Entry)
  local N = {}

  -- Wrapping a method stacks, and this mod's entry chunk runs again on every
  -- hot reload and every profile switch -- so the pristine one is parked on
  -- the class under a key of this mod's own, and a re-install wraps the
  -- ORIGINAL rather than the last wrap.  Exactly what area.lua does to
  -- TownMap.new, for exactly the same reason.
  local PRISTINE = "__gen1dex_pristine_askNicknameUI"

  -- The mon the dex page came up for, set by the catch and spent by the next
  -- prompt.  Held by identity rather than by species: the mon in the payload
  -- and the mon the prompt is asked about are the same table, and two
  -- VOLTORBs caught in one session are not.
  local pending

  -- ------- what to draw behind the box, if anything

  -- Answers with the entry screen to draw, or nil for the white field the
  -- cartridge drew.  Spends `pending` either way: one catch, one page, and a
  -- prompt that declines the backdrop must not leave it armed for the next.
  function N.backdrop(game, mon)
    local caught = pending
    pending = nil
    if caught == nil or caught ~= mon then return nil end
    -- read per prompt rather than once at load, so flipping the option in the
    -- manager shows up on the next POKéMON you catch
    if not C.option("nickname_dex", true) then return nil end

    local entry = Entry.recent and Entry.recent()
    -- Nil is the ordinary answer on a boot where some other mod won the
    -- DexEntryMenu id: the page that came up was not ours to keep up.
    if type(entry) ~= "table" or type(entry.draw) ~= "function" then
      return nil
    end
    if entry.game ~= game then return nil end

    -- UP/DOWN on the entry walks the species you have seen, so the page a
    -- player closes is not necessarily the page that was opened -- and the box
    -- is about to ask after this POKéMON by name.  The PAGE they left it on
    -- survives; only whose page it is is put back.
    if entry.species ~= mon.species then
      local ok, err = pcall(entry.setSpecies, entry, mon.species, false)
      if not ok then
        mod.log:warn("the nickname backdrop did not reopen on %s: %s",
                     tostring(mon.species), tostring(err))
        return nil
      end
    end
    return entry
  end

  -- ------- the wrap

  function N.install()
    local BattleState = require("src.battle.BattleState")
    local UIVisibility = require("src.battle.UIVisibility")

    local original = rawget(BattleState, PRISTINE) or BattleState.askNicknameUI
    if type(original) ~= "function" then
      -- an engine that asks for the nickname somewhere else entirely; the
      -- prompt is still asked, it just keeps its white field
      mod.log:warn("this build has no askNicknameUI to draw behind")
      return
    end
    rawset(BattleState, PRISTINE, original)

    BattleState.askNicknameUI = function(battle, mon, displayName)
      local box = original(battle, mon, displayName)
      local ok, entry = pcall(N.backdrop, battle and battle.game, mon)
      if not ok then
        mod.log:warn("the nickname backdrop did not build: %s", tostring(entry))
        return box
      end
      if not entry or type(box) ~= "table" then return box end

      -- Instance fields over the box the engine built, so its own draw runs
      -- untouched underneath -- and the YES/NO, which is a state of its own
      -- pushed above the box, still lands on top of both.
      local baseDraw = box.draw
      if type(baseDraw) ~= "function" then return box end
      local drawing = true

      box.draw = function(self)
        -- the box and the YES/NO both answer to the battle's bottom UI
        -- visibility (UIVisibility.bottomVisible); a backdrop for a prompt
        -- that is not on the screen is a dex page with nothing to explain it
        if drawing and UIVisibility.bottomVisible(self, true) then
          -- An animated sprite pack's frames were stepping a frame ago
          -- (Entry:update), and a POKéMON that stops breathing the instant
          -- the box comes up reads as the game having frozen rather than as a
          -- page held behind a question.  Stepped from the draw because a
          -- state under another one is never updated -- which is the same
          -- reason nothing ELSE about the page moves, and the reason nothing
          -- else about it should.
          if entry.crystal and love and love.timer then
            pcall(entry.stepCrystal, entry, love.timer.getDelta())
          end
          local drew, err = pcall(entry.draw, entry)
          if not drew then
            -- one bad frame, not sixty: the battle has already painted the
            -- white field under this, so dropping the backdrop lands exactly
            -- on the screen the cartridge drew
            drawing = false
            mod.log:warn("the nickname backdrop stopped drawing: %s",
                         tostring(err))
          end
          -- whatever the page left the pen set to, the box below is drawn in
          -- the caller's colour and a leaked black one paints it solid
          C.white()
        end
        return baseDraw(self)
      end

      -- The topmost state that HAS an opinion owns the colours, and neither
      -- the dialogue box nor the YES/NO has one -- so without this the page
      -- comes out wearing the battle's palette instead of the species'.  The
      -- entry's own answer, which is what it would draw with if it were still
      -- the screen: grey chrome, and the species over the sprite well.
      box.sgbPalettes = function(_, forGame)
        if not drawing then return nil end
        local zoned, zones = pcall(entry.sgbPalettes, entry, forGame)
        return zoned and zones or nil
      end

      return box
    end

    -- pokemon.caught fires while the queue is still being BUILT -- the dex
    -- page and the prompt are rows in it, and neither has run yet -- so the
    -- arming always lands before the prompt it is for.
    mod.events:on("pokemon.caught", function(ev)
      pending = (ev and ev.isNew and ev.mon) or nil
    end)
  end

  return N
end

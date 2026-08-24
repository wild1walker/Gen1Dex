-- Gen1Dex: the Pokédex ENTRY -- three pages, A between them, B out.
--
-- Returns a factory: factory(mod, DexData) -> { new = function(game, arg) },
-- which main.lua installs over the builtin "DexEntryMenu" id.
--
-- ------- the three pages
--
--   DEX     the sprite, the kind, height and weight, and the dex description
--   STATS   the five base stats and their total, the types, the evolutions
--   MOVES   the learnset, then the machines, paginated
--
-- A advances, wrapping DEX -> STATS -> MOVES -> DEX.  On the DEX page A first
-- walks the description's own pages, because that is what A did there in the
-- ROM (home/text.asm <PAGE>) and taking the key away would have made a
-- two-page entry unreadable.  Only once the description is spent does A move
-- on -- so the vanilla page still behaves like the vanilla page, and the two
-- new ones are past the end of it rather than in front of it.
--
-- The DEX page is why this is not a port of useful_dex's entry screen: that
-- one replaces the vanilla page outright and its description goes with it, so
-- installing it costs you the Pokédex text.  Here the vanilla page IS the
-- first page and the description is still on it.
--
-- ------- the shape of every page
--
--   rows 0-2    a header box: the species' name, and its number
--   rows 3-14   the page
--   rows 15-17  a footer box: what A does here, and what B does
--
-- The two boxes are the same on all three pages and drawn by the same call,
-- so the pages differ only where they say something different.  That is the
-- whole visual argument for the frame: A cycling three pages that share a
-- header and a footer reads as one screen with three faces, where three bare
-- 160x144 fills read as three screens.
--
-- ------- black chrome, coloured POKéMON
--
-- Every pixel this screen draws itself is shade 3, which is {0,0,0} in the
-- grey ramp and in all 151 species palettes alike -- so the boxes, the rules
-- and the text stay black under any zone, and the species zone over the
-- sprite colours the sprite and nothing around it.  The two exceptions are
-- the type colours, and they do not go through the palette pass at all: see
-- "the type colours are not palette colours" below.

return function(mod, DexData)
  local Font = require("src.render.Font")
  local PaletteFX = require("src.render.PaletteFX")
  local Sound = require("src.core.Sound")
  local Sprites = require("src.pokemon.Sprites")
  local Strings = require("src.core.Strings")
  local Theme = require("src.ui.Theme")
  local TypeChart = require("src.battle.TypeChart")

  -- ------- geometry

  local HEADER_TH, FOOTER_TY = 3, 15
  local HEADER_TEXT_Y = 8
  local FOOTER_TEXT_Y = 128
  local LEFT, RIGHT = 8, 152        -- the text margins, everywhere

  -- The sprite well: seven tiles square at tile (1,3), which is where the
  -- vanilla entry puts the pic and the largest a Gen 1 front sprite gets.
  -- Tile-aligned because it carries the species palette zone.
  local PIC_TX, PIC_TY, PIC_TILES = 1, 3, 7
  local PIC_X, PIC_Y = PIC_TX * 8, PIC_TY * 8
  local PIC_SPAN = PIC_TILES * 8

  -- DEX page: the right-hand column beside the sprite, and the description
  -- under both.  Three lines at 12 is what fits between the rule and the
  -- footer box; the ROM never prints more than three to a page.
  local INFO_X = 72
  local KIND_Y, HT_Y, WT_Y = 32, 52, 64
  local DESC_RULE_Y = 84
  local DESC_Y, DESC_STEP, DESC_LINES = 88, 12, 3

  -- STATS page: two columns.  The left one is a label and a right-aligned
  -- number, so it needs 3 glyphs plus 3 digits plus air -- 56 pixels, ending
  -- at 64.  The right one has to hold a species NAME, and ten glyphs is the
  -- longest one in the game, so it needs all 80 pixels from 72 to 152.  That
  -- split is why there are no stat BARS here: a bar wide enough to read costs
  -- 24 pixels, the left column has none spare, and taking them from the right
  -- one truncates CHARMELEON.  A number you can compare is worth more than a
  -- bar you cannot read.
  local STAT_X, STAT_END = 8, 64
  local STAT_HEAD_Y, STAT_Y, STAT_STEP = 28, 42, 12
  local BST_RULE_Y, BST_Y = 98, 102
  local TYPE_X = 72
  local TYPE_HEAD_Y, TYPE_Y, TYPE_STEP = 28, 42, 14
  local TYPE_RULE_H, TYPE_RULE_DY = 2, 9
  local EVO_HEAD_Y, EVO_Y, EVO_STEP = 78, 90, 11
  local EVO_ROWS = 3

  -- MOVES page: eight rows of twelve from 28 to 112, which ends one pixel
  -- clear of the footer box's top rule.
  local MOVE_CHIP_X, MOVE_X = 8, 16
  local MOVE_Y, MOVE_STEP, MOVE_ROWS = 28, 12, 8
  local CHIP, CHIP_DY = 5, 1

  local BLACK = { 0, 0, 0 }

  local PAGES = { "dex", "stats", "moves" }
  local NEXT_PAGE = { dex = "stats", stats = "moves", moves = "dex" }

  -- ------- the type colours are not palette colours
  --
  -- The SGB pass remaps every pixel to one of four palette entries keyed off
  -- its RED channel, so a colour drawn straight onto this screen does not
  -- come out as itself: GRASS green has red near 0.25, lands on shade 2, and
  -- is painted the palette's dark grey.  Every type would end up a different
  -- grey, which is worse than no colour at all because it looks like a bug.
  --
  -- markTrueColor is the engine's answer and the one the screens that draw
  -- real colour already use: a marked rect is re-blit with no shader over the
  -- colourised pass, so the pixels survive exactly as drawn.  The rule under
  -- each type name is marked; nothing else on the screen is, because nothing
  -- else on the screen is anything but black.
  --
  -- Kept close to the game's own type palette rather than to the modern
  -- charts, so a rule under GRASS reads as the same green the grass POKéMON
  -- wear elsewhere.
  local TYPE_COLORS = {
    NORMAL = { 0.65, 0.65, 0.55 }, FIGHTING = { 0.85, 0.35, 0.25 },
    FLYING = { 0.45, 0.65, 0.95 }, POISON = { 0.65, 0.35, 0.70 },
    GROUND = { 0.75, 0.55, 0.25 }, ROCK = { 0.55, 0.45, 0.30 },
    BUG = { 0.45, 0.70, 0.20 }, GHOST = { 0.40, 0.30, 0.60 },
    STEEL = { 0.55, 0.60, 0.65 }, FIRE = { 0.95, 0.30, 0.15 },
    WATER = { 0.20, 0.45, 0.90 }, GRASS = { 0.25, 0.75, 0.25 },
    ELECTRIC = { 0.95, 0.75, 0.10 }, PSYCHIC = { 0.90, 0.35, 0.65 },
    ICE = { 0.35, 0.80, 0.90 }, DRAGON = { 0.35, 0.25, 0.80 },
    DARK = { 0.30, 0.25, 0.25 }, FAIRY = { 0.90, 0.50, 0.75 },
  }

  local function ink(shade)
    love.graphics.setColor(shade[1], shade[2], shade[3], 1)
  end

  local function option(key, fallback)
    local ok, value = pcall(function() return mod.options:get(key) end)
    if not ok or value == nil then return fallback end
    return value
  end

  local function colorFor(typeId)
    return TYPE_COLORS[tostring(typeId or ""):upper()]
  end

  -- A patch of real colour: drawn, then marked so the unshaded pass puts it
  -- back after the shade remap has had its way with it.
  local function trueColorRect(color, x, y, w, h)
    if not color or w <= 0 or h <= 0 then return end
    love.graphics.setColor(color[1], color[2], color[3], 1)
    love.graphics.rectangle("fill", x, y, w, h)
    pcall(PaletteFX.markTrueColor, x, y, w, h)
    ink(BLACK)
  end

  -- ------- animated sprites from the Crystal mod
  --
  -- Crystal does not export its renderer, but its packaged frames are
  -- addressable through the engine's virtual filesystem, so the national dex
  -- number and a probe of the numbered files is enough to play them here.
  -- Entirely optional: with the mod absent every call in this section returns
  -- nothing and the still sprite the engine resolved is what is drawn.
  local CRYSTAL_MOD = "crystal_animated_sprites_with_shiny_visuals"
  local CRYSTAL_MS = 100
  local CRYSTAL_MAX = 100

  local function crystalRoot()
    local ok, found = pcall(function() return mod:find(CRYSTAL_MOD) end)
    if not ok or not found then return nil end
    return "mods/" .. CRYSTAL_MOD .. "/assets/front/normal"
  end

  local function crystalFrame(root, dex, frame)
    return ("%s/%d/%03d.png"):format(root, dex, frame)
  end

  local function crystalFrames(root, dex)
    if not (love.filesystem and love.filesystem.getInfo) then return 0 end
    local count = 0
    while count < CRYSTAL_MAX do
      if not love.filesystem.getInfo(crystalFrame(root, dex, count + 1)) then
        break
      end
      count = count + 1
    end
    return count
  end

  -- ------- the screen

  local Entry = {}
  Entry.__index = Entry
  Entry.isOpaque = true

  local function resolveArgs(arg)
    if type(arg) == "table" then
      return arg.species or arg[1], arg.forceOwned and true or false
    end
    return arg, false
  end

  function Entry.new(game, arg, onDone)
    local species, forceOwned = resolveArgs(arg)
    local self = setmetatable({
      game = game,
      forceOwned = forceOwned,
      onDone = onDone,
      page = "dex",
      crystalRoot = crystalRoot(),
    }, Entry)
    self:setSpecies(species, false)
    -- the cry the vanilla page plays on the way in; the species stepper plays
    -- it again on every step, which is what makes stepping feel like opening
    Sound.playCry(game.data, species)
    return self
  end

  -- Everything derived hangs off this one call, so stepping to the next
  -- species and opening a fresh screen go down the same path and cannot drift.
  function Entry:setSpecies(species, playCry)
    local game = self.game
    self.def = game.data.pokemon[species]
    self.species = species

    -- Resolved through the BATTLE kind rather than the dex kind, so a sprite
    -- or animation mod's replacement art shows up here: those mods hook the
    -- battle sprite, which is the one the player thinks of as the POKéMON.
    -- The dex kind is the fallback, which is what a mod-free boot resolves.
    local path, trueColor = Sprites.path(game.data, species, "front",
                                         { kind = "battle" })
    if not path then
      path, trueColor = Sprites.path(game.data, species, "front",
                                     { kind = "dex" })
    end
    local ok, image = false, nil
    if path then ok, image = pcall(love.graphics.newImage, path) end
    self.sprite = ok and image or nil
    self.spriteTrueColor = (ok and trueColor) and true or false

    self.stats = DexData.stats(game.data, self.def)
    self.owned = self.forceOwned
      or (game.save.pokedex and game.save.pokedex.owned[species]) or false
    self.desc = DexData.description(game.data, self.def, self.owned)
    self.descPage = 1
    self.moves = nil          -- built on first sight of the MOVES page
    self.movePage = 1

    self.crystal = nil
    self:startCrystal()

    if playCry then Sound.playCry(game.data, species) end
  end

  function Entry:startCrystal()
    local root = self.crystalRoot
    local dex = root and tonumber(self.def and self.def.dex)
    local frames = dex and crystalFrames(root, dex) or 0
    if frames == 0 then return end
    self.crystal = { dex = dex, frame = 1, elapsed = 0, frames = frames }
    self:loadCrystalFrame(1)
  end

  function Entry:loadCrystalFrame(index)
    local ok, image = pcall(love.graphics.newImage,
                            crystalFrame(self.crystalRoot, self.crystal.dex,
                                         index))
    if not (ok and image) then return end
    image:setFilter("nearest", "nearest")
    self.sprite = image
    self.spriteTrueColor = true
  end

  function Entry:stepCrystal(dt)
    local state = self.crystal
    if not state then return end
    state.elapsed = state.elapsed + (tonumber(dt) or 0) * 1000
    if state.elapsed < CRYSTAL_MS then return end
    state.elapsed = state.elapsed - CRYSTAL_MS
    state.frame = state.frame % state.frames + 1
    self:loadCrystalFrame(state.frame)
  end

  -- ------- moving around

  function Entry:moveList()
    if not self.moves then
      self.moves = DexData.moveRows(DexData.moves(self.game.data, self.def))
    end
    return self.moves
  end

  function Entry:movePages()
    return math.max(1, math.ceil(#self:moveList() / MOVE_ROWS))
  end

  function Entry:advance()
    -- the description owns A for as long as it has pages left; see the header
    if self.page == "dex" and self.desc and self.descPage < #self.desc then
      self.descPage = self.descPage + 1
      return
    end
    self.page = NEXT_PAGE[self.page]
    if self.page == "dex" then self.descPage = 1 end
    if self.page == "moves" then
      self:moveList()
      self.movePage = 1
    end
  end

  -- UP/DOWN steps through the species you have SEEN, in dex order, wrapping
  -- at both ends.  Only seen ones, because a dex with 12 entries in it would
  -- otherwise step through 139 blanks; and the current species is found by
  -- identity rather than by dex number so a renumbering mod cannot desync it.
  function Entry:stepSpecies(delta)
    if not option("step_species", true) then return end
    local species = DexData.seenSpecies(self.game.data,
                                        self.game.save and self.game.save.pokedex)
    if #species < 2 then return end
    local current
    for i, id in ipairs(species) do
      if id == self.species then current = i break end
    end
    if not current then return end
    self:setSpecies(species[(current - 1 + delta) % #species + 1], true)
  end

  function Entry:stepMovePage(delta)
    self.movePage = math.min(math.max(1, self.movePage + delta),
                             self:movePages())
  end

  function Entry:close()
    self.game.stack:pop()
    if self.onDone then self.onDone() end
  end

  function Entry:update(dt)
    self:stepCrystal(dt)
    local input = self.game.input
    if input:wasPressed("b") then
      self:close()
      return
    end
    if input:wasPressed("a") then
      self:advance()
      return
    end
    if self.page == "moves" then
      if input:wasPressed("up") then
        self:stepMovePage(-1)
      elseif input:wasPressed("down") then
        self:stepMovePage(1)
      end
    elseif input:wasPressed("up") then
      self:stepSpecies(-1)
    elseif input:wasPressed("down") then
      self:stepSpecies(1)
    end
  end

  -- ------- colour
  --
  -- Base GRAYS so the chrome is black line art, then the species' own palette
  -- over the sprite well -- the same two rules the list screen runs on, for
  -- the same reason.  Answering at all is not optional: this screen is
  -- opaque, so with no opinion the topmost state that HAS one is whatever is
  -- underneath, and the entry would come out wearing the dex list's palette.
  function Entry:sgbPalettes(game)
    local ok, zones = pcall(function()
      if not option("species_colours", true) then
        local base = PaletteFX.pal(game.data, "BROWNMON")
        if not base then return nil end
        return { PaletteFX.whole(base),
                 PaletteFX.zone(PaletteFX.monPal(game.data, self.species),
                                PIC_TX, PIC_TY,
                                PIC_TX + PIC_TILES - 1, PIC_TY + PIC_TILES - 1) }
      end
      local out = { PaletteFX.whole(PaletteFX.GRAYS) }
      -- full-colour art is re-blit unshaded over this pass, so a species
      -- palette under it would be paint nobody ever sees
      if self.page == "dex" and self.sprite and not self.spriteTrueColor then
        local colors = PaletteFX.monPal(game.data, self.species)
        local zone = colors and PaletteFX.zone(colors, PIC_TX, PIC_TY,
                                               PIC_TX + PIC_TILES - 1,
                                               PIC_TY + PIC_TILES - 1)
        if zone then out[#out + 1] = zone end
      end
      return out
    end)
    return ok and zones or nil
  end

  -- ------- drawing

  local function rule(x, y, w)
    love.graphics.rectangle("fill", x, y, w, 1)
  end

  function Entry:drawChrome(aHint, bHint)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.rectangle("fill", 0, 0, 160, 144)

    ink(BLACK)
    Font.drawBox(0, 0, 20, HEADER_TH)
    ink(BLACK)
    Font.draw(self.def.name, LEFT, HEADER_TEXT_Y)
    local digits = (self.game.data.constants or {}).dexDigits or 3
    local number = Strings("No.") .. ("%0" .. digits .. "d"):format(self.def.dex or 0)
    Font.draw(number, RIGHT - Font.width(number), HEADER_TEXT_Y)

    ink(BLACK)
    Font.drawBox(0, FOOTER_TY, 20, 3)
    ink(BLACK)
    if aHint then Font.draw(aHint, LEFT, FOOTER_TEXT_Y) end
    if bHint then
      Font.draw(bHint, RIGHT - Font.width(bHint), FOOTER_TEXT_Y)
    end
  end

  function Entry:drawSprite()
    local sprite = self.sprite
    if not sprite then return end
    -- White before the sprite or its transparent pixels come out as a solid
    -- silhouette -- the drawn colour multiplies the image, which is the same
    -- property the list screen blacks its unseen icons out with.
    love.graphics.setColor(1, 1, 1, 1)
    local w, h = sprite:getDimensions()
    -- centred across the well and standing on its floor, which is where the
    -- vanilla page stands a pic that is shorter than seven tiles
    local x = PIC_X + math.floor((PIC_SPAN - w) / 2)
    local y = PIC_Y + math.max(0, PIC_SPAN - h)
    love.graphics.draw(sprite, x, y)
    if self.spriteTrueColor then
      pcall(PaletteFX.markTrueColor, x, y, w, h)
    end
    ink(BLACK)
  end

  function Entry:drawDex()
    local hasMore = self.desc and self.descPage < #self.desc
    self:drawChrome(hasMore and Strings("A:MORE") or Strings("A:STATS"),
                    Strings("B:EXIT"))
    self:drawSprite()

    local e = self.def.dexEntry or {}
    ink(BLACK)
    Font.draw(e.kind or "?", INFO_X, KIND_Y)

    -- Height and weight are printed only once the species is OWNED, which is
    -- the Pokédex's one rule and the vanilla page's own gate: seeing one
    -- tells you what it looks like and what it is called, and nothing else.
    if self.owned and e.heightFt then
      if e.heightM then
        Font.draw((Strings("GR. %.1fm", e.heightM):gsub("(%d)%.(%d)", "%1,%2")),
                  INFO_X, HT_Y)
        Font.draw((Strings("GEW. %.1fkg", e.weightKg or 0)
                    :gsub("(%d)%.(%d)", "%1,%2")), INFO_X, WT_Y)
      else
        Font.draw(Strings("HT %d′%02d″", e.heightFt, e.heightIn or 0),
                  INFO_X, HT_Y)
        Font.draw(Strings("WT %.1flb", (e.weight or 0) / 10), INFO_X, WT_Y)
      end
    end

    rule(0, DESC_RULE_Y, 160)
    if self.desc then
      local lines = self.desc[self.descPage] or self.desc[#self.desc]
      for i = 1, math.min(#lines, DESC_LINES) do
        Font.draw(lines[i], LEFT, DESC_Y + (i - 1) * DESC_STEP)
      end
    else
      Font.draw(Strings("Data unknown."), LEFT, DESC_Y)
    end
  end

  function Entry:drawStats()
    self:drawChrome(Strings("A:MOVES"), Strings("B:EXIT"))
    ink(BLACK)

    Font.draw(Strings("STATS"), STAT_X, STAT_HEAD_Y)
    for i, s in ipairs(self.stats.stats) do
      local y = STAT_Y + (i - 1) * STAT_STEP
      Font.draw(s.key, STAT_X, y)
      local value = tostring(s.value or 0)
      Font.draw(value, STAT_END - Font.width(value), y)
    end
    rule(STAT_X, BST_RULE_Y, STAT_END - STAT_X)
    Font.draw(Strings("BST"), STAT_X, BST_Y)
    local bst = tostring(self.stats.bst)
    Font.draw(bst, STAT_END - Font.width(bst), BST_Y)

    Font.draw(Strings("TYPE"), TYPE_X, TYPE_HEAD_Y)
    local types = self.def.types or {}
    for i = 1, 2 do
      if types[i] then
        local y = TYPE_Y + (i - 1) * TYPE_STEP
        local name = TypeChart.displayName(types[i])
        Font.draw(name, TYPE_X, y)
        trueColorRect(colorFor(types[i]), TYPE_X, y + TYPE_RULE_DY,
                      Font.width(name), TYPE_RULE_H)
      end
    end

    -- A species with nowhere to go skips the heading rather than printing it
    -- over an empty column.
    local evolutions = self.stats.evolutions
    if #evolutions == 0 then return end
    Font.draw(Strings("EVOLVES"), TYPE_X, EVO_HEAD_Y)
    -- One evolution gets two lines -- HOW, then INTO WHAT -- because the
    -- column is ten glyphs wide and "LEVEL 16 IVYSAUR" is sixteen.  Two or
    -- three (EEVEE) get one line each and lose the method: three rows is all
    -- that fits, and which POKéMON it becomes is the answer the dex is being
    -- asked for.  The methods are still on the stones and the trade in your
    -- bag; the species is not written down anywhere else.
    if #evolutions == 1 then
      local evo = evolutions[1]
      Font.draw(evo.label, TYPE_X, EVO_Y)
      Font.draw(evo.name, TYPE_X, EVO_Y + EVO_STEP)
      return
    end
    for i = 1, math.min(#evolutions, EVO_ROWS) do
      Font.draw(evolutions[i].name, TYPE_X, EVO_Y + (i - 1) * EVO_STEP)
    end
  end

  function Entry:drawMoves()
    local pages = self:movePages()
    self:drawChrome(Strings("A:DEX"),
                    pages > 1 and Strings("PAGE %d/%d", self.movePage, pages)
                      or Strings("B:EXIT"))
    ink(BLACK)

    local rows = self:moveList()
    local first = (self.movePage - 1) * MOVE_ROWS
    for i = 1, MOVE_ROWS do
      local row = rows[first + i]
      if not row then break end
      local y = MOVE_Y + (i - 1) * MOVE_STEP
      -- the chip marks a move this species gets STAB on: the one fact about a
      -- movelist that changes which move you pick, and the only thing on the
      -- page worth spending colour on
      local move = row.move
      if move and move.stab then
        trueColorRect(colorFor(move.type), MOVE_CHIP_X, y + CHIP_DY, CHIP, CHIP)
      end
      Font.draw(row.text, MOVE_X, y)
    end
    if pages > 1 and self.movePage < pages then
      Font.drawCode(Theme.moreArrow, RIGHT - 8, MOVE_Y + (MOVE_ROWS - 1) * MOVE_STEP)
    end
  end

  function Entry:draw()
    if self.page == "stats" then
      self:drawStats()
    elseif self.page == "moves" then
      self:drawMoves()
    else
      self:drawDex()
    end
    love.graphics.setColor(1, 1, 1, 1)
  end

  Entry.PAGES = PAGES

  return { new = Entry.new }
end

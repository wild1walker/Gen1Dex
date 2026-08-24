-- Gen1Dex: the Pokédex LIST -- a party icon beside every entry, and three
-- views to read them in.
--
-- Returns a factory: factory(mod, DexData) -> { new = function(game, opts) },
-- which main.lua installs over the builtin "PokedexMenu" id.
--
-- ------- the shape of a row
--
--   x 0-7     the cursor, on the row it is on
--   x 8-23    the POKéMON, 16x16, two tiles square
--   x 28-     "001 BULBASAUR", and the owned ball after it
--
-- Seven rows sixteen pixels apart, which is the vanilla list's own pitch
-- (src/ui/ListMenu.lua draws row n at y = 8 + n*16) -- so the icons fit the
-- list rather than the list moving to fit the icons.  A 16-pixel icon on a
-- 16-pixel pitch sits flush against its neighbours, which is exactly how the
-- party pane in Gen1BillsBox stacks its six.
--
-- ------- why the icon sits on a tile boundary
--
-- x = 8 and y = 24 + 16n are both whole tiles, and that is load bearing
-- rather than tidy: an SGB palette zone is ADDRESSED in tiles
-- (PaletteFX.zone), and a zone per row is what gives all seven POKéMON on
-- screen their own species colours at once -- where the Game Boy could show
-- four.  Move the icon a pixel and the colour goes with the row above it.
--
-- ------- and why an undiscovered one is black
--
-- Not a palette zone -- a TINT.  PartyMenu.drawIcon never sets a colour of
-- its own, it draws in the caller's, and LÖVE multiplies the image by it: so
-- setColor(0,0,0,1) takes every pixel's RGB to zero and leaves its alpha
-- alone, which is a silhouette of the exact shape the icon draws, for free.
--
-- The palette route cannot do this job.  A zone of four blacks would blacken
-- a DMG icon, but an icon mod's authored full-colour art is re-blit UNSHADED
-- over the colourised pass (PaletteFX.markTrueColor / Renderer's
-- withTrueColor), so it would come back in colour underneath -- the entry you
-- have not met would be the only one on the screen in full colour.  A tint is
-- applied at draw time, before any of that, so it holds for both kinds of art
-- and needs to know about neither.  The matching half of the rule is below:
-- an undiscovered row asks for no species zone and marks no true-colour rect,
-- because both would repaint what the tint just blacked out.

return function(mod, DexData)
  local Font = require("src.render.Font")
  local PaletteFX = require("src.render.PaletteFX")
  local PartyMenu = require("src.ui.PartyMenu")
  local Sprites = require("src.pokemon.Sprites")
  local Strings = require("src.core.Strings")
  local Theme = require("src.ui.Theme")

  -- ------- geometry, in whole tiles where a zone has to reach

  local ROWS = 7                        -- what ListMenu draws, unchanged
  local ROW_H = 16
  local ROW_TOP = 24                    -- y of the first row: 8 + 1*16
  local CURSOR_X = 0
  local ICON_X = 8                      -- tile 1; the zone covers tiles 1-2
  local ICON = 16
  local LABEL_X = 28                    -- 4px of air after the icon
  local TITLE_Y, FOOTER_Y = 4, 136

  -- The longest row is a three-digit number, a space and a ten-glyph name --
  -- "151 CHARMANDER" is 14 glyphs, 112 pixels, ending at 140 -- and the
  -- owned ball goes one blank glyph past that.  Measured, not assumed: the
  -- ball is placed off Font.width because NIDORAN's ♂/♀ are multi-byte and
  -- counting bytes put their ball 16 pixels into the margin (engine #285).
  local BALL_GAP = 8 + 3
  local BALL_R = 3.5

  -- A blacked-out silhouette, and the white the row is drawn on.
  local BLACK = { 0, 0, 0 }

  local function ink(shade)
    love.graphics.setColor(shade[1], shade[2], shade[3], 1)
  end

  local function option(key, fallback)
    local ok, value = pcall(function() return mod.options:get(key) end)
    if not ok or value == nil then return fallback end
    return value
  end

  -- ------- the icon
  --
  -- drawIcon wants a MON and this screen has a species: a dex row is a
  -- record, not a creature, and nothing in the save answers "what would one
  -- of these look like".  The stub is the smallest shape the icon path
  -- actually reads -- with `selected` false it never reaches hp or stats,
  -- which is the same reason Gen1BillsBox passes forceAlt for its box mons
  -- (a Gen 1 box mon has no stat block at all).
  local stubs = {}
  local function stubFor(species)
    local hit = stubs[species]
    if not hit then
      hit = { species = species, hp = 1, stats = { hp = 1 }, level = 1 }
      stubs[species] = hit
    end
    return hit
  end

  -- Does this species' icon carry colour a grey ramp cannot?  Only a mod's
  -- own image can: a built-in icon CLASS is baked through obpIcon, which
  -- flattens every pixel to a grey off its red channel, so it is never full
  -- colour whatever file it points at.  Read once per species and kept,
  -- because it is a property of the art and the art does not change.
  local colourCache = {}

  local function resolveIcon(game, species)
    local icons = game.data and game.data.icons
    if not icons then return nil, nil end
    local def = game.data.pokemon and game.data.pokemon[species]
    local entry = (icons.bySpecies and icons.bySpecies[species])
      or (def and def.icon)
    local name, path
    if type(entry) == "string" then
      name = entry
      path = icons.icons and icons.icons[entry]
    elseif type(entry) == "table" then
      path = entry.image
    end
    if not path then
      name = def and def.dex and icons.byDex and icons.byDex[def.dex]
      path = name and icons.icons and icons.icons[name]
    end
    local ok, hooked = pcall(Sprites.iconPath, game.data, stubFor(species),
                             path, { name = name })
    if ok then path = hooked end
    return name, path
  end

  local function fullColour(game, species)
    local hit = colourCache[species]
    if hit ~= nil then return hit end
    hit = false
    local name, path = resolveIcon(game, species)
    if path and not name then
      pcall(function()
        local data = require("src.render.Assets").imageData(path)
        local w, h = data:getDimensions()
        local drawn = h > ICON and ICON or h
        for y = 0, drawn - 1 do
          for x = 0, w - 1 do
            local r, g, b, a = data:getPixel(x, y)
            if a > 0 and (math.abs(r - g) > 0.02 or math.abs(g - b) > 0.02) then
              hit = { w = w > ICON and ICON or w, h = drawn }
              return
            end
          end
        end
      end)
    end
    colourCache[species] = hit
    return hit
  end

  -- One icon, in colour or blacked out.  `discovered` is the whole rule: a
  -- species you have seen wears its own art and asks for its own colours, one
  -- you have not is a black shape and asks for nothing.
  local function drawIcon(game, species, x, y, discovered)
    if not species then return end
    if discovered then
      love.graphics.setColor(1, 1, 1, 1)
      pcall(PartyMenu.drawIcon, game, stubFor(species), x, y, false, 0, false)
      local rect = fullColour(game, species)
      if rect then
        pcall(PaletteFX.markTrueColor, x, y, rect.w, rect.h)
      end
    else
      -- the tint IS the silhouette; see the header
      ink(BLACK)
      pcall(PartyMenu.drawIcon, game, stubFor(species), x, y, false, 0, false)
    end
    love.graphics.setColor(1, 1, 1, 1)
  end

  -- ------- colour
  --
  -- Base GRAYS rather than the vanilla list's BROWNMON, and for the reason
  -- Gen1BillsBox spells out: a named palette paints shade 1 a colour
  -- (MEWMON's is a salmon {239,156,107}), and everything this screen draws
  -- itself is meant to read as black line art.  Shade 3 is {0,0,0} in the
  -- grey ramp and in all 151 species palettes alike, so the chrome stays
  -- black under any zone and a species palette laid over a row reaches the
  -- POKéMON in it and nothing else.
  --
  -- SPECIES COLOURS off puts the vanilla brown back and asks for no zones,
  -- which is the whole of that option.
  local function palettesFor(screen, game)
    local ok, zones = pcall(function()
      if not option("species_colours", true) then
        return PaletteFX.wholeNamed(game.data, "BROWNMON")
      end
      local out = { PaletteFX.whole(PaletteFX.GRAYS) }
      for row = 1, screen.rows do
        local item = screen.items[screen.scroll + row]
        -- an undiscovered row is deliberately skipped: it is black by tint,
        -- and a species zone would colour the silhouette back in
        if item and item.species and item.seen and not fullColour(game, item.species) then
          local colors = PaletteFX.monPal(game.data, item.species)
          local ty = (ROW_TOP + (row - 1) * ROW_H) / 8
          local zone = colors
            and PaletteFX.zone(colors, ICON_X / 8, ty, ICON_X / 8 + 1, ty + 1)
          if zone then out[#out + 1] = zone end
        end
      end
      return out
    end)
    return ok and zones or nil
  end

  -- ------- drawing
  --
  -- A whole replacement for ListMenu:draw rather than a wrap around it: the
  -- vanilla row prints its label at x=16, which is where the icon now is, so
  -- there is no version of this that leaves that call in place.  Everything
  -- else about the list -- input, scrolling, the side menu, SELECT -- is
  -- still ListMenu's, and is not touched.
  local function draw(self)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.rectangle("fill", 0, 0, 160, 144)
    ink(BLACK)
    Font.draw(Strings(self.title), 8, TITLE_Y)

    if #self.items == 0 then
      Font.draw(Strings("Nothing here."), 16, 64)
      love.graphics.setColor(1, 1, 1, 1)
      return
    end

    for row = 1, self.rows do
      local i = self.scroll + row
      local item = self.items[i]
      if not item then break end
      local y = ROW_TOP + (row - 1) * ROW_H

      drawIcon(self.game, item.species, ICON_X, y, item.seen)

      ink(BLACK)
      -- the icon is two tiles tall and the glyphs are one, so the label sits
      -- on the icon's middle rather than on its top edge
      local textY = y + 4
      Font.draw(item.label, LABEL_X, textY)
      if item.ball then
        local bx = LABEL_X + Font.width(item.label) + BALL_GAP
        local by = textY + 3
        love.graphics.circle("fill", bx, by, BALL_R)
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.rectangle("fill", bx - BALL_R, by - 0.5, BALL_R * 2, 1)
        ink(BLACK)
        love.graphics.circle("fill", bx, by, 1.2)
      end
      if i == self.index then
        Font.drawCode(Theme.cursor, CURSOR_X, textY)
      end
    end

    ink(BLACK)
    if self.footer then Font.draw(self.footer, 8, FOOTER_Y) end
    -- more below: the same marker every other list uses, in the margin the
    -- footer leaves free
    if self.scroll + self.rows < #self.items then
      Font.drawCode(Theme.moreArrow, 148, FOOTER_Y)
    end
    love.graphics.setColor(1, 1, 1, 1)
  end

  -- ------- the screen
  --
  -- Built by the VANILLA constructor and then re-dressed, which is what keeps
  -- the DATA / CRY / AREA / QUIT side menu, the cursor memory and the QUIT
  -- path exactly as they were: this mod has an opinion about how the list
  -- looks and which entries are in it, and none at all about what pressing A
  -- on one does.
  local List = {}

  function List.new(game, opts)
    local Vanilla = require("src.ui.PokedexMenu")
    local list = Vanilla.new(game, opts)

    list.wrap = option("wrap", true)          -- UP on the first row wraps
    list.keyRepeat = option("hold_scroll", true)

    local mode = "num"

    local function rebuild(prebuilt)
      local build = prebuilt
        or DexData.list(game.data, game.save.pokedex, mode)
      local current = list.items[list.index] and list.items[list.index].species
      list.title = DexData.MODE_LABELS[mode]
      -- fixed three-digit fields keep this at 17 glyphs, under the 18-column
      -- wrap a bare ListMenu footer goes through (engine #639)
      list.footer = Strings("SEEN %3d  OWN %3d", build.seen, build.owned)
      list.items = build.items
      list.index = 1
      list.scroll = 0
      if current then
        for i, item in ipairs(build.items) do
          if item.species == current then list.index = i break end
        end
      end
      -- the restored cursor can sit past the visible rows; clamp the scroll
      -- here so the frame drawn right after this shows the right page
      if list.index - list.scroll > list.rows then
        list.scroll = list.index - list.rows
      end
    end

    -- Rebuilt once on open even in the numbered view, because the items this
    -- mod draws carry `species` and `seen` on every row and the vanilla ones
    -- do not -- a blank row has to know which POKéMON it is not showing you.
    rebuild()

    list.onSelectKey = function()
      if not option("view_cycle", true) then return end
      local nextMode = DexData.NEXT_MODE[mode]
      local build = DexData.list(game.data, game.save.pokedex, nextMode)
      -- an empty filtered view would strand SELECT: ListMenu returns before
      -- onSelectKey when the list is empty, so there would be no way back
      if #build.items == 0 then return end
      mode = nextMode
      rebuild(build)
    end

    list.draw = draw
    list.sgbPalettes = palettesFor

    -- for the suite, and for anything that wants to know what is on screen
    list.dexMode = function() return mode end

    return list
  end

  return { new = List.new }
end

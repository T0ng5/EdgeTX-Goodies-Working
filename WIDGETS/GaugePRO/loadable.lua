---------------------------------------------------------------------------
-- The dynamically loadable part of the Lua widget.                      --
--                                                                       --
-- Author:  Philippe Wechsler                                            --
-- Date:    2022-07-23                                                   --
-- Version: 1.0.0                                                        --
-- Source: https://github.com/MadMonkey87/EdgeTX-Goodies                 --
--                                                                       --
-- Copyright (C) Philippe Wechsler                                       --
--                                                                       --
-- License GPLv2: http://www.gnu.org/licenses/gpl-2.0.html               --
--                                                                       --
-- This program is free software; you can redistribute it and/or modify  --
-- it under the terms of the GNU General Public License version 2 as     --
-- published by the Free Software Foundation.                            --
--                                                                       --
-- This program is distributed in the hope that it will be useful        --
-- but WITHOUT ANY WARRANTY; without even the implied warranty of        --
-- MERCHANTABILITY or FITNESS FOR borderON PARTICULAR PURPOSE. See the   --
-- GNU General Public License for more details.                          --
---------------------------------------------------------------------------
-- TX16S MK3 HiRes patch — overview of all changes in this file          --
--   The TX16S MK3 has an 800×480 display.  All older EdgeTX colour      --
--   radios (TX16S MK1/MK2, Horus X10/X12) use 480×272.  Every pixel     --
--   value and font choice in the original script was written for        --
--   480×272, so on the MK3 the back button, title bar and text all      --
--   appeared roughly 1.67× too large or misplaced.                      --
--                                                                       --
-- FIX SUMMARY                                                           --
--   1. Detect the MK3 screen at load time using LCD_W >= 800.           --
--   2. Provide S(px) to scale any fixed pixel value proportionally.     --
--   3. Scale all fixed-pixel constants (HEADER, BTN_SIZE, etc).         --
--   4. Replace the original static font-size logic in create() with     --
--      fully dynamic font selection in widgetRefresh() using            --
--      lcd.sizeText() so any zone size on any screen renders correctly. --
--   5. Replace hardcoded vertical offsets with zone-relative maths so   --
--      label and value text never overlap regardless of zone height.    --
--   6. Gauge geometry (margin, border) derived dynamically from zone    --
--      dimensions rather than looked up from a static size table.       --
---------------------------------------------------------------------------

local zone, options = ...

---- CHANGE 1: HiRes screen detection -------------------------------------
-- LCD_W and LCD_H are EdgeTX globals set to the physical screen resolution.
-- We check at load time rather than every frame because the screen size
-- never changes while the radio is running — this avoids repeated work.
--
-- The threshold 800 is used rather than checking for exactly 800×480
-- so the patch also works on any future radio with an equally large or
-- larger screen without needing code changes.
local IS_HIRES = (LCD_W ~= nil) and (LCD_W >= 800) or false

---- CHANGE 2: Scale factor and S() helper --------------------------------
-- The original script was authored against a 480px-wide screen.
-- The MK3 is 800px wide, giving a ratio of 800/480 ≈ 1.667.
-- On non-HiRes radios SCALE=1.0, so S(px) is a no-op and the original
-- pixel values are preserved exactly.
local SCALE = IS_HIRES and (800 / 480) or 1.0

-- S(px): scale a pixel constant and round to the nearest integer.
-- Used for every fixed pixel value that needs to grow on the MK3.
-- math.floor(x + 0.5) is the standard Lua integer-rounding idiom.
local function S(px)
  return math.floor(px * SCALE + 0.5)
end

---- CHANGE 3: Scaled layout constants -----------------------------------
-- These were originally hardcoded integers designed for 480×272.
-- Wrapping them in S() means they scale up on the MK3 and stay unchanged
-- on all other radios.
--
-- HEADER: height of the title bar drawn across the top of full-screen mode.
--         Original value: 40px.
-- COL1:   left margin for the title text inside that bar.
--         Original value: 10px.
-- HEIGHT: generic line height used in list-style sub-layouts.
--         Original value: 24px.
local HEADER = S(40)
local COL1   = S(10)
local HEIGHT = S(24)

---- CHANGE 4: Scaled back-button geometry -------------------------------
-- The original full-screen "back" button was hardcoded as:
--   lcd.drawRectangle(LCD_W - 34, 6, 28, 28, ...)       -- outer box
--   lcd.drawFilledRectangle(LCD_W - 30, 19, 20, 3, ...) -- inner bar
-- On the MK3 those absolute pixel offsets placed the button in the wrong
-- position and made it too small relative to the larger screen.
--
-- We compute the button position from first principles using S() so it
-- is always correctly sized and anchored to the top-right corner on any
-- screen.
local BTN_SIZE   = S(28)                          -- width and height of button
local BTN_MARGIN = S(6)                           -- gap from the right and top edges
local BTN_X      = LCD_W - BTN_SIZE - BTN_MARGIN  -- anchored to right edge
local BTN_Y      = BTN_MARGIN                     -- anchored to top edge

local widget = { }

-- CHANGE (main.lua): loadGUI_GaugePRO() instead of loadGUI() — see main.lua for why.
local libGUI = loadGUI_GaugePRO()

local gui = libGUI.newGUI()

-- Back button element registered with the GUI framework.
-- CHANGE 4: position and size now use BTN_* scaled constants.
local custom = gui.custom({ }, BTN_X, BTN_Y, BTN_SIZE, BTN_SIZE)

function custom.draw(focused)
  -- Outer border rectangle — position and size fully scaled (CHANGE 4)
  lcd.drawRectangle(BTN_X, BTN_Y, BTN_SIZE, BTN_SIZE, libGUI.colors.primary2)

  -- Inner horizontal bar (the "≡" back icon).
  -- Original offsets LCD_W-30 / 19 / w=20 / h=3 were hardcoded for
  -- 480×272.  We re-derive the bar dimensions and centre them inside the
  -- button using S() so they scale correctly on every screen.
  local barW = S(20)
  local barH = S(3)
  local barX = BTN_X + math.floor((BTN_SIZE - barW) / 2)
  local barY = BTN_Y + math.floor((BTN_SIZE - barH) / 2)
  lcd.drawFilledRectangle(barX, barY, barW, barH, libGUI.colors.primary2)
  if focused then
    custom.drawFocus()
  end
end

function custom.onEvent(event, touchState)
  if event == EVT_VIRTUAL_ENTER then
    lcd.exitFullScreen()
  end
end

local function hasLabel()
  return widget.options.Label ~= ""
end

local function getPercentValue(value)
  return math.floor(100 / (widget.options.Max - widget.options.Min) * value + 0.5)
end

local function getTotalizedValue(value)
  return math.floor(100 / (widget.options.Max *2) * (value + widget.options.Max + 0.5)) --only works if Min is negative and same total as Max
end

---- CHANGE 5: Simplified create() -----------------------------------------
-- The original create() selected font sizes, colors and layout offsets
-- once into widget.textFlags / widget.labelFlags / widget.gaugeFlags /
-- widget.yo / widget.lyo / widget.lyo2 / widget.margin / widget.border.
-- This worked on fixed-size screens but broke on the MK3 because:
--   a) The zone width/height thresholds (> 240 / > 70 / >= 56) were
--      tuned for 480×272 and mapped to wrong choices on 800×480.
--   b) The stored offsets became stale if the widget zone was resized
--      in the Companion Simulator without reloading the widget.
--   c) lyo and lyo2 were near-identical fractions of zone height, causing
--      the label to render directly on top of the value text.
--
-- The fix moves all font, color and geometry decisions into widgetRefresh()
-- where they run every frame against the live zone dimensions.  create()
-- now only stores zone and options — nothing else.
function widget.create(zone, options)
  widget = { zone = zone, options = options }
  return widget
end

---- Full-screen refresh ----------------------------------------------------
-- This function draws the full-screen overlay when the user double-taps
-- the widget.  It uses CHANGE 3 constants (HEADER, COL1) which are now
-- scaled via S() so layout is correct on both 480×272 and 800×480 screens.
function gui.fullScreenRefresh()
  -- Title bar — HEADER is now S(40) so it scales with the screen (CHANGE 3)
  lcd.drawFilledRectangle(0, 0, LCD_W, HEADER, COLOR_THEME_SECONDARY1)
  if hasLabel() then
    -- S(2) nudge keeps the text visually centred in the bar on all screens
    lcd.drawText(COL1, HEADER / 2 - S(2), widget.options.Label, VCENTER + DBLSIZE + COLOR_THEME_PRIMARY2)
  else
    lcd.drawText(COL1, HEADER / 2 - S(2), "Gauge PRO", VCENTER + DBLSIZE + COLOR_THEME_PRIMARY2)
  end

  local textValue
  value = getValue(widget.options.Source)
  if value == nil then
    return
  end

  -- CHANGE 3: margin scaled so the gauge bar and its border keep the same
  -- proportional inset from the screen edge on both 480×272 and 800×480.
  -- Original was hardcoded 20px.
  local margin = S(20)
  local xo = LCD_W / 2
  local yo = (LCD_H - HEADER) / 2 + HEADER

  percentValue  = getPercentValue(value)
  totalizedValue = getTotalizedValue(value)
  textValue = percentValue.."%"
  if widget.options.Totalize == 1 then
    textValue = totalizedValue.."%"
  end
  lcd.drawGauge(margin, HEADER + margin, LCD_W - 2*margin, LCD_H - HEADER - 2*margin, totalizedValue, 100, COLOR_THEME_FOCUS)
  lcd.drawRectangle(margin, HEADER + margin, LCD_W - 2*margin, LCD_H - HEADER - 2*margin, COLOR_THEME_ACTIVE, 3)
  lcd.drawText(xo, yo, textValue, XXLSIZE + SHADOWED + CENTER + COLOR_THEME_ACTIVE)
end

---- CHANGE 6: Fully dynamic widget (non-full-screen) refresh --------------
-- Previous iterations used static font flags, colors, gauge geometry and
-- y offsets set once in create().  These caused problems on the MK3:
--
--   PROBLEM A — Clipping: Font chosen by zone WIDTH alone.  A tall narrow
--     zone has plenty of width but limited height, so a large font
--     overflowed the bottom edge.  Long percent strings ("100%") could
--     also clip horizontally because render width was never checked.
--
--   PROBLEM B — Overlap: label and value y positions were both derived
--     from widget.yo with similar small adjustments, causing them to
--     render on top of each other in medium-height zones.
--
--   PROBLEM C — Gauge geometry (margin, border) chosen by static thresholds
--     tuned for 480×272, giving wrong proportions on 800×480 zones.
--
-- SOLUTION: Every frame we:
--   1. Resolve the display string before font selection.
--      "100%" is the worst-case width for any percentage value; we size
--      against it so the font never flickers as the gauge value changes.
--   2. Derive gauge margin and border from the live zone dimensions so
--      they scale correctly on any screen.
--   3. Use lcd.sizeText() to check both rendered HEIGHT and WIDTH of each
--      candidate font.  A font is only accepted when it fits on both axes.
--   4. Guard against the EdgeTX lcd.sizeText() height quirk (returns 13px
--      for all fonts on some builds) using a known-minimum table.
--   5. Apply an 85% height cap so descenders never clip at the zone edge.
--   6. Compute y positions from measured heights for clean separation
--      between label and value text.
function libGUI.widgetRefresh()
  local textValue
  value = getValue(widget.options.Source)
  if value == nil then
    return
  end

  local showLabel = hasLabel()

  -- Unpack zone dimensions for readability
  local zoneX = widget.zone.x
  local zoneY = widget.zone.y
  local zoneW = widget.zone.w
  local zoneH = widget.zone.h
  local xo    = zoneX + math.floor(zoneW / 2)

  percentValue  = getPercentValue(value)
  totalizedValue = getTotalizedValue(value)
  textValue = percentValue.."%"
  if widget.options.Totalize == 1 then
    textValue = totalizedValue.."%"
  end

  ---- Gauge geometry (CHANGE 6, point 2) --------------------------------
  -- margin: inset between zone edge and gauge bar.
  --   Zones taller than 56px get a proportional margin (3% of the shorter
  --   dimension, minimum 1px); very short zones (thin top-bar slots) get
  --   no margin so the gauge fills the full height.
  -- border: outline thickness drawn around the gauge bar.
  --   Omitted entirely for very short zones to avoid artefacts.
  -- gaugeColor: the fill colour of the bar.
  --   COLOR_THEME_FOCUS for normal zones, COLOR_THEME_ACTIVE for tiny ones
  --   (matches the original behavior for each size tier).
  local margin     = (zoneH >= 56) and math.max(1, math.floor(math.min(zoneW, zoneH) * 0.03)) or 0
  local border     = (margin > 0) and 3 or 0
  local gaugeColor = (margin > 0) and COLOR_THEME_FOCUS or COLOR_THEME_ACTIVE

  lcd.drawGauge(zoneX + margin, zoneY + margin, zoneW - 2*margin, zoneH - 2*margin, totalizedValue, 100, gaugeColor)
  if border > 0 then
    lcd.drawRectangle(zoneX + margin, zoneY + margin, zoneW - 2*margin, zoneH - 2*margin, COLOR_THEME_ACTIVE, border)
  end

  ---- Slot budgets (CHANGE 6, point 5) ---------------------------------
  -- Divide available height into two slots.
  -- Label slot: top 28% of zone height (only used when a label is set).
  -- Value slot: remaining 68% when label shown, or full height otherwise.
  local maxValueH = showLabel and math.floor(zoneH * 0.68) or zoneH
  local maxLabelH = math.floor(zoneH * 0.26)

  -- Hard cap at 85% of each slot.
  -- Prevents descenders on tall glyphs from clipping at the zone boundary.
  local capValue = math.floor(maxValueH * 0.85)
  local capLabel = math.floor(maxLabelH * 0.85)

  ---- Font selection (CHANGE 6, points 3 & 4) --------------------------
  -- pickFont() iterates candidates from largest to smallest and returns
  -- the first font whose effective height fits within capH AND whose
  -- rendered width of `text` fits within zoneW.
  --
  -- For the value slot we size against "100%" (the widest possible percent
  -- string) rather than the live textValue.  This prevents the chosen font
  -- from changing each frame as the gauge value moves, which would cause
  -- visible flickering between font sizes near a threshold.
  --
  -- Height: guarded by knownMins against the EdgeTX sizeText quirk.
  -- Width:  trusted directly — it varies with string length and font size.
  --
  -- Known safe minimum heights (EdgeTX colour LCD, conservative values):
  --   XXLSIZE ≥ 38px   DBLSIZE ≥ 22px   MIDSIZE ≥ 17px
  --   default ≥ 13px   SMLSIZE ≥ 10px
  local function pickFont(text, candidates, capH)
    local knownMins = {
      [XXLSIZE] = 38,
      [DBLSIZE] = 22,
      [MIDSIZE] = 17,
      [0]       = 13,
      [SMLSIZE] = 10,
    }
    for _, f in ipairs(candidates) do
      local w, h = lcd.sizeText(text, f)
      local minH = knownMins[f] or 10
      -- Trust sizeText height only when it returns above the default height.
      local effectiveH = (h > 13) and h or minH
      if effectiveH <= capH and w <= zoneW then
        return f, effectiveH  -- return chosen font flag AND its height
      end
    end
    return SMLSIZE, 10  -- absolute fallback: smallest font always fits
  end

  -- Value font: sized against "100%" so the choice is stable regardless
  -- of the live gauge value.  Actual textValue is drawn with this font.
  local tsBase, tsH = pickFont("100%",              { XXLSIZE, DBLSIZE, MIDSIZE, 0, SMLSIZE }, capValue)
  -- Label font: label is always smaller than value, so start from MIDSIZE.
  local lsBase, lsH = pickFont(widget.options.Label, { MIDSIZE, 0, SMLSIZE },                  capLabel)

  -- Combine base font flag with display style flags.
  -- SHADOWED: drop-shadow for legibility drawn over the coloured gauge bar.
  -- CENTER:   horizontal centering around xo.
  -- textFlags use COLOR_THEME_ACTIVE; labelFlags use COLOR_THEME_PRIMARY2
  -- (matching the original's color choices for the large/medium size tiers).
  local ts = tsBase + SHADOWED + CENTER + COLOR_THEME_ACTIVE
  local ls = lsBase + SHADOWED + CENTER + COLOR_THEME_PRIMARY2

  ---- Vertical positioning (CHANGE 6, point 6) -------------------------
  -- Position text using the measured heights so there is always a clean
  -- gap between label and value, and neither clips at the zone boundary.
  --
  -- With label:
  --   yLabel = near the top of the zone (3% padding from top edge)
  --   yValue = centred in the space that remains below the label
  --
  -- Without label:
  --   yValue = centred in the full zone height
  local yValue, yLabel
  if showLabel then
    yLabel = zoneY + math.floor(zoneH * 0.03)
    -- belowLabel: y coordinate where the value slot begins
    -- (bottom of label text + 2% gap)
    local belowLabel = yLabel + lsH + math.floor(zoneH * 0.02)
    local belowH     = (zoneY + zoneH) - belowLabel  -- height of remaining space
    yValue = belowLabel + math.floor((belowH - tsH) / 2)
  else
    yValue = zoneY + math.floor((zoneH - tsH) / 2)
  end

  ---- Draw text over the gauge ------------------------------------------
  lcd.drawText(xo, yValue, textValue, ts)

  if showLabel then
    lcd.drawText(xo, yLabel, widget.options.Label, ls)
  end
end

function widget.background()

end

function widget.update(options)
  widget.options = options
end

function widget.refresh(event, touchState)
  gui.run(event, touchState)
end

return widget

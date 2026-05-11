---------------------------------------------------------------------------
-- The dynamically loadable part of the Lua widget.                      --
--                                                                       --
-- Author:  Philippe Wechsler                                            --
-- Date:    2022-07-24                                                   --
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
---------------------------------------------------------------------------

local UnitsTable = {
  [1] = "V",
  [2] = "A",
  [3] = "mA",
  [4] = "kts",
  [5] = "m/s",
  [6] = "f/s",
  [7] = "km/h",
  [8] = "mph",
  [9] = "m",
  [10] = "f",
  [11] = "C°",
  [12] = "F°",
  [13] = "%",
  [14] = "mAh",
  [15] = "W",
  [16] = "mW",
  [17] = "dB",
  [18] = "RPM",
  [19] = "G",
  [20] = "deg",
  [21] = "rad",
  [22] = "mm",
  [23] = "floz",
  [24] = "ml/m",
  [35] = "h",
  [36] = "m",
  [37] = "s",
  [38] = "",
  [39] = "",
  [40] = "",
  [41] = "",
  [42] = ""
}

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

-- CHANGE (main.lua): loadGUI_ValuePRO() instead of loadGUI() — see main.lua for why.
local libGUI = loadGUI_ValuePRO()

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

local function updateUnit()
  fieldInfo = getFieldInfo(widget.options.Source)
  if(fieldInfo.unit~=nil and fieldInfo.unit > 0) then
    widget.unit = (UnitsTable[fieldInfo.unit])
  else
    widget.unit = ""
  end

  if(fieldInfo.desc~=nil) then
    widget.desc = fieldInfo.desc
  else
    widget.desc = ""
  end
end

---- CHANGE 5: Simplified create() -----------------------------------------
-- The original create() selected font sizes and computed vertical offsets
-- once, storing them in widget.ts / widget.ls / widget.yo / widget.lyo /
-- widget.lyo2.  This worked on fixed-size screens but broke on the MK3
-- because:
--   a) The zone width thresholds (> 240 / > 70) were tuned for 480×272
--      and mapped to wrong font choices on 800×480.
--   b) The stored offsets became stale if the widget zone was resized
--      in the Companion Simulator without reloading the widget.
--   c) lyo and lyo2 were near-identical fractions of zone height, causing
--      the label to render directly on top of the value text.
--
-- The fix moves all font selection and layout into widgetRefresh() where
-- it runs every frame against the live zone dimensions.  create() now
-- only stores the zone, options, and unit/desc state — nothing else.
function widget.create(zone, options)
  widget = { zone = zone, options = options, unit = "", desc = "" }
  updateUnit()
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
    lcd.drawText(COL1, HEADER / 2 - S(2), "Value PRO", VCENTER + DBLSIZE + COLOR_THEME_PRIMARY2)
  end

  local value = getValue(widget.options.Source)
  local xo = LCD_W / 2
  local yo = LCD_H / 2 - (HEADER / 2)

  -- CHANGE 3: LCD_H - HEADER instead of hardcoded LCD_H - 40, so the
  -- source description label stays the same distance from the bottom on
  -- any screen height.
  lcd.drawText(xo, LCD_H - HEADER, widget.desc, SHADOWED + CENTER + COLOR_THEME_PRIMARY3)

  if value == nil then
    lcd.drawText(xo, yo, "NO VALUE", XXLSIZE + SHADOWED + CENTER + COLOR_THEME_ACTIVE + BLINK + INVERS)
  elseif widget.options.Percent == 1 then
    percentValue = getPercentValue(value)
    local textValue = percentValue.."%"
    lcd.drawText(xo, yo, textValue, XXLSIZE + SHADOWED + CENTER + COLOR_THEME_ACTIVE)
  else
    --lcd.drawNumber(xo, yo, value, widget.ts)
    lcd.drawText(xo, yo, string.format("%2.1f", value).." "..widget.unit, XXLSIZE + SHADOWED + CENTER + COLOR_THEME_ACTIVE)
  end
end

---- CHANGE 6: Fully dynamic widget (non-full-screen) refresh --------------
-- Previous iterations used static font flags and hardcoded/fractional y
-- offsets set once in create().  These caused two problems on the MK3:
--
--   PROBLEM A — Clipping: The font was chosen based on zone WIDTH alone.
--     A tall narrow zone (e.g. top-bar size 2) has plenty of width but
--     limited height, so a large font overflowed the bottom edge.
--     Long values with unit suffixes (e.g. "-1024.0 mAh") also clipped
--     horizontally because the original code never checked render width.
--
--   PROBLEM B — Overlap: The label and value y positions were both derived
--     from the same base offset (widget.yo) with similar small adjustments,
--     causing them to render on top of each other.
--
-- SOLUTION: Every frame we:
--   1. Resolve the actual display string before font selection so that
--      pickFont() measures the real text, not a single proxy character.
--   2. Divide the zone into a label slot (top ~28%) and a value slot (rest).
--   3. Use lcd.sizeText() to check both rendered HEIGHT and WIDTH of the
--      candidate font against the slot cap and zone width respectively.
--      A font is only accepted when it fits on both axes.
--   4. Fall back to a known-minimum height table when lcd.sizeText()
--      returns the same value for all fonts (a known EdgeTX quirk on some
--      firmware builds where the flag is not respected by sizeText).
--   5. Apply an 85% height cap as a final hard guard so a font can never
--      fill its slot to the point where descenders clip at the edge.
--   6. Compute y positions from the measured heights rather than from
--      fixed fractions, so label and value are always cleanly separated.
function libGUI.widgetRefresh()
  local value     = getValue(widget.options.Source)
  local showLabel = hasLabel()

  -- Unpack zone dimensions for readability
  local zoneX = widget.zone.x
  local zoneY = widget.zone.y
  local zoneW = widget.zone.w
  local zoneH = widget.zone.h
  local xo    = zoneX + math.floor(zoneW / 2)

  ---- Resolve display text early (CHANGE 6, point 1) -------------------
  -- We must know the actual string before picking a font so pickFont()
  -- can measure its rendered width against the zone width.  This also
  -- removes duplicate value-mapping logic from the draw section below.
  local textValue
  if value == nil then
    textValue = "NO VALUE"
  elseif widget.options.Percent == 1 then
    textValue = getPercentValue(value).."%"
  else
    --lcd.drawNumber(xo, yo, value, widget.ts)
    textValue = string.format("%2.1f", value)..widget.unit
  end

  ---- Slot budgets (CHANGE 6, point 2) ---------------------------------
  -- Divide available height into two slots.
  -- Label slot: top 28% of zone height (only used when a label is set).
  -- Value slot: remaining 68% when label shown, or full height otherwise.
  -- These proportions keep both items visible at all practical zone sizes.
  local maxValueH = showLabel and math.floor(zoneH * 0.68) or zoneH
  local maxLabelH = math.floor(zoneH * 0.26)

  -- Hard cap at 85% of each slot (CHANGE 6, point 5).
  -- Prevents descenders on tall glyphs (g, y, p) from clipping at the
  -- zone boundary.  The 85% figure gives roughly one descender-height of
  -- breathing room below the text.
  local capValue = math.floor(maxValueH * 0.85)
  local capLabel = math.floor(maxLabelH * 0.85)

  ---- Font selection (CHANGE 6, points 3 & 4) --------------------------
  -- pickFont() iterates candidates from largest to smallest and returns
  -- the first font whose effective height fits within capH AND whose
  -- rendered width of `text` fits within zoneW.
  --
  -- Height: lcd.sizeText() height is unreliable on some EdgeTX builds —
  --   it returns 13px for all font sizes.  We guard against this with
  --   knownMins: if sizeText returns ≤13px we use the conservative table
  --   value instead.
  --
  -- Width: lcd.sizeText() width scales with font size and string length
  --   and does not suffer the same EdgeTX quirk, so we trust it directly.
  --   This is the key fix for value+unit strings clipping on narrow zones.
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
      -- Trust sizeText height only when it returns above the default height,
      -- meaning it actually varies with the font flag.
      local effectiveH = (h > 13) and h or minH
      if effectiveH <= capH and w <= zoneW then
        return f, effectiveH  -- return chosen font flag AND its height
      end
    end
    return SMLSIZE, 10  -- absolute fallback: smallest font always fits
  end

  -- Value font: sized against the actual display string so long values
  -- with unit suffixes (e.g. "-1024.0 mAh") never overflow the zone.
  local tsBase, tsH = pickFont(textValue,            { XXLSIZE, DBLSIZE, MIDSIZE, 0, SMLSIZE }, capValue)
  -- Label font: label is always smaller than value, so start from MIDSIZE.
  local lsBase, lsH = pickFont(widget.options.Label, { MIDSIZE, 0, SMLSIZE },                  capLabel)

  -- Combine base font flag with display style flags.
  -- SHADOWED: drop-shadow for legibility on coloured backgrounds.
  -- CENTER:   horizontal centering around xo.
  local ts = tsBase + SHADOWED + CENTER + COLOR_THEME_ACTIVE
  local ls = lsBase + SHADOWED + CENTER + COLOR_THEME_PRIMARY3

  ---- Vertical positioning (CHANGE 6, point 6) ------------------------
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

  ---- Draw -------------------------------------------------------------
  if value == nil then
    -- Source not connected or telemetry lost — blink to draw attention
    lcd.drawText(xo, yValue, textValue, ts + BLINK + INVERS)
  else
    lcd.drawText(xo, yValue, textValue, ts)
  end

  if showLabel then
    --lcd.drawSource(xo, yLabel, widget.options.Source, ls)
    lcd.drawText(xo, yLabel, widget.options.Label, ls)
  end
end

function widget.background()

end

function widget.update(options)
  widget.options = options

  updateUnit()
end

function widget.refresh(event, touchState)
  gui.run(event, touchState)
end

return widget

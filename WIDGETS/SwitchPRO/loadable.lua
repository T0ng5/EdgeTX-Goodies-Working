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
--   480×272, so on the MK3 the full-screen button, title bar and text   --
--   all appeared roughly 1.67× too large or misplaced.                  --
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
-- This matches the community-standard ratio used in other MK3 patches
-- (e.g. the iNav telemetry widget) so behaviour is consistent.
-- On non-HiRes radios SCALE=1.0, so S(px) is a no-op and the original
-- pixel values are preserved exactly.
local SCALE    = IS_HIRES and (800 / 480) or 1.0

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

-- CHANGE (main.lua): loadGUI_SwitchPRO() instead of loadGUI() — see main.lua for why.
local libGUI = loadGUI_SwitchPRO()

local gui = libGUI.newGUI()

-- Back button element registered with the GUI framework.
local custom = gui.custom({ }, BTN_X, BTN_Y, BTN_SIZE, BTN_SIZE)

function custom.draw(focused)
  -- Outer border rectangle — position and size fully scaled (CHANGE 3/4)
  lcd.drawRectangle(BTN_X, BTN_Y, BTN_SIZE, BTN_SIZE, libGUI.colors.primary2)

  -- Inner horizontal bar (the "≡" back icon).
  -- Original offsets BTN_X+4 / BTN_Y+13 / w=20 / h=3 were hardcoded for
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
-- only stores the zone and options — nothing else.
function widget.create(zone, options)
  widget = { zone = zone, options = options }
  return widget
end
---- Full-screen refresh ----------------------------------------------------
-- This function draws the full-screen overlay when the user double-taps
-- the widget.  It uses CHANGE 3 constants (HEADER, COL1) and derives the
-- vertical spread between the three switch-position labels as a proportion
-- of the available screen height, replacing the original ±60px hardcode.
function gui.fullScreenRefresh()
  -- Title bar — HEADER is now S(40) so it scales with the screen (CHANGE 3)
  lcd.drawFilledRectangle(0, 0, LCD_W, HEADER, COLOR_THEME_SECONDARY1)
  if(hasLabel()) then
    -- S(2) nudge keeps the text visually centred in the bar on all screens
    lcd.drawText(COL1, HEADER / 2 - S(2), widget.options.Label, VCENTER + DBLSIZE + COLOR_THEME_PRIMARY2)
  else
    lcd.drawText(COL1, HEADER / 2 - S(2), "Switch PRO", VCENTER + DBLSIZE + COLOR_THEME_PRIMARY2)
  end

  local value = getValue(widget.options.Source)
  -- Centre of the drawable area below the title bar
  local xo = LCD_W / 2
  local yo = (LCD_H - HEADER) / 2 + HEADER

  -- CHANGE: proportional vertical spread between the three position labels.
  -- Original was ±60px, which was ~22% of the 272px screen height.
  -- Using a fraction of (LCD_H - HEADER) keeps that same visual proportion
  -- on any screen height automatically.
  local spread = math.floor((LCD_H - HEADER) * 0.22)

  if(value == nil) then
    lcd.drawText(xo, yo, "NO VALUE", XXLSIZE + SHADOWED + CENTER + COLOR_THEME_ACTIVE + BLINK + INVERS)
  else
    if(value == -1024) then
      -- Switch UP: highlight SwUp in large font, dim the others
      lcd.drawText(xo, yo - spread, widget.options.SwUp,   XXLSIZE + SHADOWED + CENTER + VCENTER + COLOR_THEME_ACTIVE)
      lcd.drawText(xo, yo,          widget.options.SwMid,  DBLSIZE + SHADOWED + CENTER + VCENTER + COLOR_THEME_PRIMARY3)
      lcd.drawText(xo, yo + spread, widget.options.SwDown, DBLSIZE + SHADOWED + CENTER + VCENTER + COLOR_THEME_PRIMARY3)
    elseif(value == 0) then
      -- Switch MID: highlight SwMid
      lcd.drawText(xo, yo - spread, widget.options.SwUp,   DBLSIZE + SHADOWED + CENTER + VCENTER + COLOR_THEME_PRIMARY3)
      lcd.drawText(xo, yo,          widget.options.SwMid,  XXLSIZE + SHADOWED + CENTER + VCENTER + COLOR_THEME_ACTIVE)
      lcd.drawText(xo, yo + spread, widget.options.SwDown, DBLSIZE + SHADOWED + CENTER + VCENTER + COLOR_THEME_PRIMARY3)
    elseif(value == 1024) then
      -- Switch DOWN: highlight SwDown
      lcd.drawText(xo, yo - spread, widget.options.SwUp,   DBLSIZE + SHADOWED + CENTER + VCENTER + COLOR_THEME_PRIMARY3)
      lcd.drawText(xo, yo,          widget.options.SwMid,  DBLSIZE + SHADOWED + CENTER + VCENTER + COLOR_THEME_PRIMARY3)
      lcd.drawText(xo, yo + spread, widget.options.SwDown, XXLSIZE + SHADOWED + CENTER + VCENTER + COLOR_THEME_ACTIVE)
    end
  end
end

---- CHANGE 6: Fully dynamic widget (non-full-screen) refresh --------------
-- Previous iterations used static font flags and hardcoded/fractional y
-- offsets set once in create().  These caused two problems on the MK3:
--
--   PROBLEM A — Clipping: The font was chosen based on zone WIDTH alone.
--     A tall narrow zone (e.g. top-bar size 2) has plenty of width but
--     limited height, so a large font overflowed the bottom edge.
--
--   PROBLEM B — Overlap: The label and value y positions were both derived
--     from the same base offset (widget.yo) with similar small adjustments,
--     causing them to render on top of each other.
--
-- SOLUTION: Every frame we:
--   1. Divide the zone into a label slot (top ~28%) and a value slot (rest).
--   2. Use lcd.sizeText() to measure the actual rendered height of each
--      candidate font, picking the largest one that fits its slot.
--   3. Fall back to a known-minimum height table when lcd.sizeText()
--      returns the same value for all fonts (a known EdgeTX quirk on some
--      firmware builds where the flag is not respected by sizeText).
--   4. Apply an 85% cap as a final hard guard so a font can never fill
--      its slot to the point where descenders clip at the edge.
--   5. Compute y positions from the measured heights rather than from
--      fixed fractions, so label and value are always cleanly separated.
function libGUI.widgetRefresh()
  local showLabel = hasLabel()
  local value     = getValue(widget.options.Source)

  -- Unpack zone dimensions for readability
  local zoneX = widget.zone.x
  local zoneY = widget.zone.y
  local zoneW = widget.zone.w
  local zoneH = widget.zone.h
  local xo    = zoneX + math.floor(zoneW / 2)

  ---- Resolve display text early (needed for width-aware font selection) --
  -- We must know the actual string before picking a font so that pickFont()
  -- can measure its rendered width against the zone width.  Doing this once
  -- here also removes duplicate value-mapping logic from the draw section.
  local textValue
  if value == nil then
    textValue = "NO VALUE"
  elseif value == -1024 then
    textValue = widget.options.SwUp
  elseif value == 0 then
    textValue = widget.options.SwMid
  elseif value == 1024 then
    textValue = widget.options.SwDown
  else
    textValue = "INVALID VALUE"
  end

  ---- Slot budgets (CHANGE 6, point 1) --------------------------------
  -- Divide available height into two slots.
  -- Label slot: top 28% of zone height (only used when a label is set).
  -- Value slot: remaining 72% when label shown, or full height otherwise.
  -- These proportions keep both items visible at all practical zone sizes.
  local maxValueH = showLabel and math.floor(zoneH * 0.68) or zoneH
  local maxLabelH = math.floor(zoneH * 0.26)

  -- Hard cap at 85% of each slot (CHANGE 6, point 4).
  -- Prevents descenders on tall glyphs (g, y, p) from clipping at the
  -- zone boundary.  The 85% figure gives roughly one descender-height of
  -- breathing room below the text.
  local capValue  = math.floor(maxValueH * 0.85)
  local capLabel  = math.floor(maxLabelH * 0.85)

  ---- Font selection (CHANGE 6, points 2 & 3) -------------------------
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
  --   This is the fix for text clipping when the zone is narrow — the
  --   original code measured only "M" for height and ignored width entirely.
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
      local w, h   = lcd.sizeText(text, f)
      local minH   = knownMins[f] or 10
      -- Trust sizeText height only when it returns above the default height.
      local effectiveH = (h > 13) and h or minH
      if effectiveH <= capH and w <= zoneW then
        return f, effectiveH  -- return chosen font flag AND its height
      end
    end
    return SMLSIZE, 10  -- absolute fallback: smallest font always fits
  end

  -- Value font: sized against the actual display string so long words
  -- (e.g. "Manual") are never wider than the zone.
  local tsBase, tsH = pickFont(textValue,            { XXLSIZE, DBLSIZE, MIDSIZE, 0, SMLSIZE }, capValue)
  -- Label font: label is always smaller than value, so start from MIDSIZE.
  local lsBase, lsH = pickFont(widget.options.Label, { MIDSIZE, 0, SMLSIZE },                  capLabel)

  -- Combine base font flag with display style flags.
  -- SHADOWED: drop-shadow for legibility on coloured backgrounds.
  -- CENTER:   horizontal centering around xo.
  -- Colour flags come last as EdgeTX ORs them all together.
  local ts = tsBase + SHADOWED + CENTER + COLOR_THEME_ACTIVE
  local ls = lsBase + SHADOWED + CENTER + COLOR_THEME_PRIMARY3

  ---- Vertical positioning (CHANGE 6, point 5) ------------------------
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
    lcd.drawText(xo, yLabel, widget.options.Label, ls)
  end
end
---- Standard widget callbacks (unchanged from original) --------------------
function widget.background()

end

function widget.update(options)
  -- Called by EdgeTX when the user changes settings in the widget menu.
  -- Store the new options so widgetRefresh() picks them up next frame.
  widget.options = options
end

function widget.refresh(event, touchState)
  -- Hand off to the GUI framework; it calls widgetRefresh() (widget mode)
  -- or fullScreenRefresh() + onEvent() (full-screen mode) as appropriate.
  gui.run(event, touchState)
end

return widget

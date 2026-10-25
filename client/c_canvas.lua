--[[
    spraypaint - canvas (render target) and stroke drawing

    Strokes are drawn into the render target INCREMENTALLY - every frame only
    the points that appeared since the last one. A full redraw only happens
    when a graffiti is loaded, after an undo/clear, and after the render
    targets are lost (alt-tab).
]]--

Canvas = {}

local canvases = {}     -- every live canvas, for the bulk redraw below

-- ─── Deterministic scatter ───────────────────────────────────────────────────
-- Spray droplets have to land in the same place after every load, otherwise a
-- graffiti would "dance" every time you walk up to it. Hence a hash of the
-- point position instead of math.random.

local function scatterRand(seed, n)
    local h = (seed * 1103515245 + n * 12345 + 7919) % 2147483648
    return (h % 10000) / 10000
end

-- ─── Texture orientation ─────────────────────────────────────────────────────
-- dxDrawMaterialLine3D maps the texture onto the surface its own way, which
-- comes out rotated compared to how the drawing was made. The compensation
-- (rotation plus optional mirroring) happens here, while drawing into the
-- canvas.
--
-- Applies ONLY to canvases projected onto a wall (c.wall). The editor creates
-- its canvas without it, otherwise the player would see something different
-- from what they are drawing.

local function mapPoint(c, u, v)
    if not c.wall then return u, v end

    local rot = (tonumber(Config.WallRotation) or 0) % 360
    if rot == 90 then
        u, v = 1 - v, u
    elseif rot == 180 then
        u, v = 1 - u, 1 - v
    elseif rot == 270 then
        u, v = v, 1 - u
    end

    if Config.FlipHorizontal then u = 1 - u end
    if Config.FlipVertical   then v = 1 - v end

    return u, v
end

-- ─── Create and destroy ──────────────────────────────────────────────────────

-- onWall: true for canvases projected onto a wall (orientation compensated),
--         false for the editor preview (drawn 1:1)
function Canvas.new(strokes, onWall)
    local size = Config.CanvasSize
    local rt = dxCreateRenderTarget(size, size, true)
    if not rt then
        outputDebugString("[spraypaint] could not create a render target", 1)
        return nil
    end

    local c = {
        rt          = rt,
        size        = size,
        strokes     = strokes or {},
        wall        = onWall and true or false,
        doneStrokes = 0,        -- number of fully drawn strokes
        donePoints  = 0,        -- points done in stroke number doneStrokes+1
        needsClear  = true,
    }

    canvases[c] = true
    return c
end

function Canvas.destroy(c)
    if not c then return end
    canvases[c] = nil
    if isElement(c.rt) then destroyElement(c.rt) end
    c.rt = nil
end

-- Forces a full redraw from scratch (undo, clear, device loss).
function Canvas.markDirty(c)
    if not c then return end
    c.needsClear  = true
    c.doneStrokes = 0
    c.donePoints  = 0
end

-- ─── Drawing ─────────────────────────────────────────────────────────────────

local function drawBlob(x, y, brush, r, g, b, seed)
    -- Core of the blob
    dxDrawCircle(x, y, brush.size * 0.5, 0, 360, tocolor(r, g, b, 210), tocolor(r, g, b, 235), 10)

    -- Scattered droplets around it - that is what makes it a spray, not a marker
    for i = 1, brush.drops do
        local ang  = scatterRand(seed, i * 2)     * math.pi * 2
        local rad  = scatterRand(seed, i * 2 + 1) * brush.scatter
        local px   = x + math.cos(ang) * rad
        local py   = y + math.sin(ang) * rad
        local dropSize = 1 + math.floor(scatterRand(seed, i * 3) * 2)
        dxDrawRectangle(px, py, dropSize, dropSize, tocolor(r, g, b, 90))
    end
end

-- Draws the line between two canvas points as a row of overlapping blobs.
-- Returns the number of blobs drawn, for the per-frame budget.
local function drawSegment(x1, y1, x2, y2, brush, r, g, b, seed)
    local dx, dy = x2 - x1, y2 - y1
    local len = math.sqrt(dx*dx + dy*dy)
    local step = math.max(1.5, brush.size / 3)
    local steps = math.max(1, math.ceil(len / step))

    for i = 0, steps do
        local t = i / steps
        drawBlob(x1 + dx*t, y1 + dy*t, brush, r, g, b, seed + i)
    end

    return steps + 1
end

-- How many blobs may be drawn during a single frame. A full redraw of a large
-- graffiti is tens of thousands of draw calls - without a cap the picture
-- would freeze when a player walks up to a wall. This way the canvas fills in
-- over a few frames instead.
local FRAME_BUDGET = 900

-- Is there anything left to draw into the canvas?
local function hasPendingWork(c)
    if c.needsClear then return true end

    local nStrokes = #c.strokes
    if c.doneStrokes >= nStrokes then return false end
    if c.doneStrokes + 1 < nStrokes then return true end

    -- The last stroke is in progress - compare the number of finished points
    local cur = c.strokes[c.doneStrokes + 1]
    return c.donePoints < (#cur.p / 2)
end

-- Draws everything that appeared since the previous frame.
-- MUST be called from a render event - dxSetRenderTarget fails outside one.
function Canvas.flush(c)
    if not c or not isElement(c.rt) then return end
    if not hasPendingWork(c) then return end

    if not dxSetRenderTarget(c.rt, c.needsClear) then return end
    c.needsClear = false

    local strokes = c.strokes
    local nStrokes = #strokes
    local size = c.size
    local budget = FRAME_BUDGET

    for si = c.doneStrokes + 1, nStrokes do
        local s = strokes[si]
        local brush = Config.BrushSizes[s.b] or Config.BrushSizes[1]
        local col   = Config.Colors[s.c] or Config.Colors[1]
        local r, g, b = col.rgb[1], col.rgb[2], col.rgb[3]

        local pts = s.p
        local nPts = #pts / 2
        local startPt = math.max(1, c.donePoints)

        -- A lone point (a tap without dragging) has to be visible too
        if nPts == 1 and c.donePoints < 1 then
            local bu, bv = mapPoint(c, pts[1], pts[2])
            drawBlob(bu * size, bv * size, brush, r, g, b, si * 977)
            budget = budget - 1
        end

        local pi = startPt
        while pi <= nPts - 1 do
            local u1, v1 = mapPoint(c, pts[pi*2 - 1], pts[pi*2])
            local u2, v2 = mapPoint(c, pts[pi*2 + 1], pts[pi*2 + 2])
            local x1, y1 = u1 * size, v1 * size
            local x2, y2 = u2 * size, v2 * size
            budget = budget - drawSegment(x1, y1, x2, y2, brush, r, g, b, si * 977 + pi * 31)
            pi = pi + 1

            if budget <= 0 then
                -- Out of budget mid-stroke; the next frame continues from here
                c.donePoints = pi
                dxSetRenderTarget()
                return
            end
        end

        if si < nStrokes then
            c.doneStrokes = si
            c.donePoints  = 0
        else
            c.donePoints = math.max(1, nPts)
        end
    end

    dxSetRenderTarget()
end

-- ─── Device loss ─────────────────────────────────────────────────────────────
-- After an alt-tab or a resolution change the render targets are empty and have
-- to be drawn again, otherwise every graffiti would stay invisible until the
-- resource restarts.

addEventHandler("onClientRestore", root, function(didClearRenderTargets)
    if not didClearRenderTargets then return end
    for c in pairs(canvases) do
        Canvas.markDirty(c)
    end
end)

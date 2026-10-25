--[[
    spraypaint - streaming and drawing of saved graffiti

    The server sends the metadata and strokes of every graffiti nearby; the
    client builds render targets only for the ones it can actually see. The
    number of live render targets is hard-capped (Config.MaxActiveRenderers).
]]--

Graffiti = {}       -- [id] = record

-- ─── Record management ───────────────────────────────────────────────────────

function Graffiti_add(data)
    local id = tonumber(data.id)
    if not id then return end

    local rev = tonumber(data.rev) or 1
    local existing = Graffiti[id]

    -- The periodic sync also sends graffiti the client already has. Without a
    -- revision change the canvas must not be touched, or it would flicker
    -- every few seconds.
    if existing then
        if existing.rev == rev then return end
        Graffiti_remove(id)
    end

    Graffiti[id] = {
        id        = id,
        rev       = rev,
        x         = data.x,  y = data.y,  z = data.z,
        nx        = data.nx, ny = data.ny, nz = data.nz,
        width     = data.width,
        height    = data.height,
        dimension = tonumber(data.dimension) or 0,
        interior  = tonumber(data.interior) or 0,
        strokes   = data.strokes or {},
        canvas    = nil,
    }
end

function Graffiti_remove(id)
    local g = Graffiti[id]
    if not g then return end
    if g.canvas then
        Canvas.destroy(g.canvas)
    end
    Graffiti[id] = nil
end

function Graffiti_clearAll()
    for id in pairs(Graffiti) do Graffiti_remove(id) end
end

addEvent("spraypaint:sync", true)
addEventHandler("spraypaint:sync", root, function(list)
    for _, data in ipairs(list) do Graffiti_add(data) end
end)

addEvent("spraypaint:removed", true)
addEventHandler("spraypaint:removed", root, function(id)
    Graffiti_remove(tonumber(id))
end)

addEventHandler("onClientResourceStop", resourceRoot, function()
    Graffiti_clearAll()
end)

-- ─── Deciding what stays loaded ──────────────────────────────────────────────

local function playerMatches(g)
    return g.dimension == getElementDimension(localPlayer)
       and g.interior  == getElementInterior(localPlayer)
end

setTimer(function()
    local px, py, pz = getElementPosition(localPlayer)

    -- Sort by distance and keep only the nearest N alive.
    local candidates = {}
    for _, g in pairs(Graffiti) do
        local d = Util.dist3D(px, py, pz, g.x, g.y, g.z)
        g.dist = d

        if d > Config.UnloadDistance or not playerMatches(g) then
            if g.canvas then
                Canvas.destroy(g.canvas)
                g.canvas = nil
            end
        elseif d <= Config.RenderDistance then
            candidates[#candidates + 1] = g
        end
    end

    table.sort(candidates, function(a, b) return a.dist < b.dist end)

    for i, g in ipairs(candidates) do
        if i <= Config.MaxActiveRenderers then
            if not g.canvas then
                g.canvas = Canvas.new(g.strokes, true)
            end
        elseif g.canvas then
            -- Dropped out of the limit (the player turned towards a denser
            -- cluster of graffiti)
            Canvas.destroy(g.canvas)
            g.canvas = nil
        end
    end
end, Config.RendererCheckInterval, 0)

-- ─── Drawing into the world ──────────────────────────────────────────────────

-- Draws the canvas as a flat rectangle glued to the wall.
function Graffiti_drawSurface(x, y, z, nx, ny, nz, width, height, material)
    local rx, ry, rz, _, _, _, cnx, cny, cnz = Util.basisFromNormal(nx, ny, nz)

    -- Offset from the wall, otherwise the texture fights the building geometry
    local cx = x + cnx * Config.WallOffset
    local cy = y + cny * Config.WallOffset
    local cz = z + cnz * Config.WallOffset

    local hw = width * 0.5
    local sx, sy, sz = cx - rx*hw, cy - ry*hw, cz - rz*hw
    local ex, ey, ez = cx + rx*hw, cy + ry*hw, cz + rz*hw

    dxDrawMaterialLine3D(
        sx, sy, sz,
        ex, ey, ez,
        material,
        height,
        tocolor(255, 255, 255, 255),
        cx + cnx, cy + cny, cz + cnz      -- point the surface faces
    )
end

addEventHandler("onClientRender", root, function()
    local px, py, pz = getElementPosition(localPlayer)
    local dim, int = getElementDimension(localPlayer), getElementInterior(localPlayer)

    for _, g in pairs(Graffiti) do
        if g.canvas and g.dimension == dim and g.interior == int then
            local d = Util.dist3D(px, py, pz, g.x, g.y, g.z)
            if d <= Config.RenderDistance then
                Canvas.flush(g.canvas)
                Graffiti_drawSurface(g.x, g.y, g.z, g.nx, g.ny, g.nz, g.width, g.height, g.canvas.rt)
            end
        end
    end
end)

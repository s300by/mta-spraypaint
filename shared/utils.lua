--[[
    spraypaint - shared helpers (client and server)
]]--

Util = {}

-- ─── Vector math ─────────────────────────────────────────────────────────────

function Util.normalize(x, y, z)
    local len = math.sqrt(x*x + y*y + z*z)
    if len < 0.0001 then return 0, 0, 1 end
    return x/len, y/len, z/len
end

function Util.cross(ax, ay, az, bx, by, bz)
    return ay*bz - az*by,
           az*bx - ax*bz,
           ax*by - ay*bx
end

function Util.dot(ax, ay, az, bx, by, bz)
    return ax*bx + ay*by + az*bz
end

function Util.dist3D(ax, ay, az, bx, by, bz)
    local dx, dy, dz = bx-ax, by-ay, bz-az
    return math.sqrt(dx*dx + dy*dy + dz*dz)
end

-- Derives the canvas basis from the wall normal alone: "right" (horizontally
-- along the wall) and "up" (vertically up the wall). That is why only the
-- normal has to be stored in the database.
function Util.basisFromNormal(nx, ny, nz)
    nx, ny, nz = Util.normalize(nx, ny, nz)

    -- On a nearly horizontal surface (floor/ceiling) "right" cannot be derived
    -- from world up - the vectors would be parallel and the cross product zero.
    local rx, ry, rz
    if math.abs(nz) > 0.99 then
        rx, ry, rz = 1, 0, 0
    else
        rx, ry, rz = Util.normalize(Util.cross(0, 0, 1, nx, ny, nz))
    end

    local ux, uy, uz = Util.normalize(Util.cross(nx, ny, nz, rx, ry, rz))
    return rx, ry, rz, ux, uy, uz, nx, ny, nz
end

-- World position of a point on the canvas. u/v are 0..1, origin top left.
function Util.canvasToWorld(canvas, u, v)
    local rx, ry, rz, ux, uy, uz = Util.basisFromNormal(canvas.nx, canvas.ny, canvas.nz)
    local ox = (u - 0.5) * canvas.width
    local oy = (0.5 - v) * canvas.height
    return canvas.x + rx*ox + ux*oy,
           canvas.y + ry*ox + uy*oy,
           canvas.z + rz*ox + uz*oy
end

-- Intersection of a ray with the canvas plane -> u/v coordinates. Returns nil
-- when the ray misses the surface or points away from the wall.
function Util.rayToCanvasUV(canvas, ox, oy, oz, dx, dy, dz)
    local rx, ry, rz, ux, uy, uz, nx, ny, nz = Util.basisFromNormal(canvas.nx, canvas.ny, canvas.nz)

    local denom = Util.dot(dx, dy, dz, nx, ny, nz)
    if math.abs(denom) < 0.0001 then return nil end    -- ray is parallel to the plane

    local t = Util.dot(canvas.x - ox, canvas.y - oy, canvas.z - oz, nx, ny, nz) / denom
    if t <= 0 then return nil end                      -- plane is behind the player

    local hx, hy, hz = ox + dx*t, oy + dy*t, oz + dz*t
    local lx, ly, lz = hx - canvas.x, hy - canvas.y, hz - canvas.z

    local px = Util.dot(lx, ly, lz, rx, ry, rz)
    local py = Util.dot(lx, ly, lz, ux, uy, uz)

    local u = px / canvas.width  + 0.5
    local v = 0.5 - py / canvas.height

    if u < 0 or u > 1 or v < 0 or v > 1 then return nil end
    return u, v, t, hx, hy, hz
end

-- ─── Zones ───────────────────────────────────────────────────────────────────

function Util.isBlacklisted(x, y, z)
    for _, zone in ipairs(Config.BlacklistedZones) do
        if Util.dist3D(x, y, z, zone.x, zone.y, zone.z) <= (zone.radius or 50.0) then
            return true
        end
    end
    return false
end

-- ─── Stroke validation ───────────────────────────────────────────────────────

-- Validates the structure of strokes arriving from a client. The server must
-- not trust them - a client can send anything, including data that would kill
-- everyone else's FPS when drawn.
function Util.validateStrokes(strokes)
    if type(strokes) ~= "table" then return nil, "invalid format" end
    if #strokes == 0 then return nil, "empty canvas" end
    if #strokes > Config.MaxStrokes then return nil, "too many strokes" end

    local total = 0
    local clean = {}

    for i = 1, #strokes do
        local s = strokes[i]
        if type(s) ~= "table" or type(s.p) ~= "table" then return nil, "invalid stroke" end

        local color = tonumber(s.c)
        local brush = tonumber(s.b)
        if not color or not Config.Colors[color] then return nil, "invalid color" end
        if not brush or not Config.BrushSizes[brush] then return nil, "invalid brush" end

        local pts = s.p
        local n = #pts
        if n < 2 or n % 2 ~= 0 then return nil, "invalid stroke points" end
        if n / 2 > Config.MaxPointsPerStroke then return nil, "stroke is too long" end

        local cp = {}
        for j = 1, n do
            local val = tonumber(pts[j])
            if not val or val < 0 or val > 1 then return nil, "point outside the canvas" end
            -- 3 decimals = half a pixel on a 512 canvas. Storing finer values
            -- is invisible and only inflates the JSON and the traffic.
            cp[j] = math.floor(val * 1000 + 0.5) / 1000
        end

        total = total + n / 2
        if total > Config.MaxTotalPoints then return nil, "too many points" end

        clean[i] = { c = color, b = brush, p = cp }
    end

    return clean
end

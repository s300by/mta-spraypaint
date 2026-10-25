--[[
    spraypaint - aiming

    Aiming goes through the centre of the screen with the camera (a classic
    crosshair), not with a free cursor, so the player can look around and spray
    at the same time.
]]--

Aim = {}

-- Ray from the camera towards where the player is looking.
function Aim.getRay()
    local cx, cy, cz, tx, ty, tz = getCameraMatrix()
    local dx, dy, dz = Util.normalize(tx - cx, ty - cy, tz - cz)
    return cx, cy, cz, dx, dy, dz
end

-- What the player is aiming at in the world. Returns the hit position and the
-- surface normal.
function Aim.getWorldHit(maxDistance)
    local ox, oy, oz, dx, dy, dz = Aim.getRay()
    local ex, ey, ez = ox + dx*maxDistance, oy + dy*maxDistance, oz + dz*maxDistance

    local hit, hx, hy, hz, element, nx, ny, nz = processLineOfSight(
        ox, oy, oz, ex, ey, ez,
        true,       -- buildings
        false,      -- vehicles
        false,      -- players
        true,       -- objects
        false,      -- dummies
        false,      -- seeThroughStuff
        false,      -- ignoreSomeObjectsForCamera
        false,      -- shootThroughStuff
        localPlayer -- ignored element
    )

    if not hit then return nil end
    if not nx then return nil end   -- without a normal the surface cannot be oriented

    -- The normal has to point out of the wall, i.e. towards the player
    if Util.dot(nx, ny, nz, dx, dy, dz) > 0 then
        nx, ny, nz = -nx, -ny, -nz
    end

    return hx, hy, hz, nx, ny, nz, element
end

-- Where the player is aiming on a specific canvas. Returns u/v in 0..1.
function Aim.getCanvasHit(canvasDef, maxDistance)
    local ox, oy, oz, dx, dy, dz = Aim.getRay()
    local u, v, t = Util.rayToCanvasUV(canvasDef, ox, oy, oz, dx, dy, dz)
    if not u then return nil end
    if t > maxDistance then return nil end
    return u, v, t
end

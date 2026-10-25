--[[
    spraypaint - HUD of the spraying mode
]]--

local sw, sh = guiGetScreenSize()

local function drawCrosshair(r, g, b)
    local cx, cy = sw / 2, sh / 2
    dxDrawRectangle(cx - 8, cy - 1, 16, 2, tocolor(r, g, b, 200), true)
    dxDrawRectangle(cx - 1, cy - 8, 2, 16, tocolor(r, g, b, 200), true)
end

local function drawHint(text)
    dxDrawText(text, 0, sh - 92, sw, sh - 92, tocolor(255, 255, 255, 220),
               1.0, "default-bold", "center", "top", false, false, true)
end

-- ─── Spraying ────────────────────────────────────────────────────────────────

function HUD_draw(mode, corner1, spray)
    if mode == "select" then
        drawCrosshair(120, 220, 255)

        -- The first marked corner has to stay visible, or the second one is
        -- placed blind
        if corner1 then
            local scx, scy = getScreenFromWorldPosition(corner1.x, corner1.y, corner1.z)
            if scx then
                dxDrawRectangle(scx - 5, scy - 5, 10, 10, tocolor(120, 220, 255, 230), true)
            end
            drawHint("Mark the SECOND corner  •  Backspace = cancel")
        else
            drawHint("Aim at a wall and mark the FIRST corner with the left button  •  Backspace = cancel")
        end
        return
    end

    -- The editor draws its own panel, the HUD has no business there
    if mode == "editor" then return end

    if mode == "spraying" and spray then
        local elapsed = getTickCount() - spray.startedAt
        local pct = math.min(1, elapsed / Config.SprayDuration)

        local barW, barH = 320, 14
        local x, y = (sw - barW) / 2, sh - 110

        dxDrawText("SPRAYING", 0, y - 26, sw, y - 26,
                   tocolor(255, 255, 255, 235), 1.1, "default-bold", "center", "top", false, false, true)
        dxDrawRectangle(x, y, barW, barH, tocolor(0, 0, 0, 160), true)
        dxDrawRectangle(x, y, barW * pct, barH, tocolor(120, 220, 255, 230), true)

        drawHint("Backspace = interrupt")
    end
end

-- ─── Wiping ──────────────────────────────────────────────────────────────────

-- progress = nil while aiming, 0..1 during the wiping animation
function HUD_drawEraser(target, progress)
    drawCrosshair(255, 200, 120)

    if progress then
        local barW, barH = 300, 14
        local x, y = (sw - barW) / 2, sh - 110

        dxDrawText("WIPING GRAFFITI", 0, y - 26, sw, y - 26,
                   tocolor(255, 255, 255, 235), 1.1, "default-bold", "center", "top", false, false, true)
        dxDrawRectangle(x, y, barW, barH, tocolor(0, 0, 0, 160), true)
        dxDrawRectangle(x, y, barW * math.min(1, progress), barH, tocolor(255, 170, 60, 230), true)

        drawHint("Backspace = interrupt")
        return
    end

    if not target then
        drawHint("Aim at a graffiti in range  •  Backspace = cancel")
        return
    end

    -- Outline of the targeted graffiti, so it is clear what will be wiped
    local rx, ry, rz, ux, uy, uz = Util.basisFromNormal(target.nx, target.ny, target.nz)
    local hw, hh = target.width * 0.5, target.height * 0.5
    local col = tocolor(255, 200, 120, 220)

    local function corner(sx, sy)
        return target.x + rx*hw*sx + ux*hh*sy,
               target.y + ry*hw*sx + uy*hh*sy,
               target.z + rz*hw*sx + uz*hh*sy
    end

    local ax, ay, az = corner(-1,  1)
    local bx, by, bz = corner( 1,  1)
    local cx, cy, cz = corner( 1, -1)
    local dx, dy, dz = corner(-1, -1)

    dxDrawLine3D(ax, ay, az, bx, by, bz, col, 3)
    dxDrawLine3D(bx, by, bz, cx, cy, cz, col, 3)
    dxDrawLine3D(cx, cy, cz, dx, dy, dz, col, 3)
    dxDrawLine3D(dx, dy, dz, ax, ay, az, col, 3)

    drawHint("Left button = wipe this graffiti  •  Backspace = cancel")
end

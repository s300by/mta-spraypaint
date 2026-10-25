--[[
    spraypaint - the spraying flow

    /spray -> the server verifies the spray can
           -> SELECT:   the player marks two corners on a wall
           -> EDITOR:   draws the design on a 2D canvas (c_editor.lua)
           -> SPRAYING: animation, the graffiti appears on the wall gradually
           -> saved on the server, the item is taken

    Cancelling is possible any time until the animation ends; the item is not
    taken in that case.
]]--

Paint = {}

local mode        = nil     -- nil | "select" | "editor" | "spraying"
local lockedColor = nil     -- forced color of colored spray cans
local corner1     = nil     -- the first marked corner
local canvasDef   = nil     -- geometry of the selected surface
local prop        = nil

-- State of the spraying phase
local spray = nil           -- { def, strokes, preview, previewCanvas, startedAt, ... }

-- ─── Prop and animation ──────────────────────────────────────────────────────

local function attachProp(model)
    if not model then return end
    prop = createObject(model, 0, 0, 0)
    if not prop then return end
    setElementCollisionsEnabled(prop, false)

    local a = Config.PropAttach
    BoneAttach.attach(prop, localPlayer, a.bone,
        a.pos[1], a.pos[2], a.pos[3],
        a.rot[1], a.rot[2], a.rot[3])
end

local function removeProp()
    if isElement(prop) then
        BoneAttach.detach(prop)
        destroyElement(prop)
    end
    prop = nil
end

-- ─── Controls ────────────────────────────────────────────────────────────────

local blockedControls = { "fire", "aim_weapon", "next_weapon", "previous_weapon", "action" }
local movementControls = { "forwards", "backwards", "left", "right", "jump", "sprint" }

local function setControlsBlocked(blocked)
    for _, c in ipairs(blockedControls) do toggleControl(c, not blocked) end
end

local function setMovementBlocked(blocked)
    for _, c in ipairs(movementControls) do toggleControl(c, not blocked) end
end

-- ─── Stopping ────────────────────────────────────────────────────────────────

function Paint.stop(silent)
    if not mode then return end

    if Editor.isOpen() then Editor.close() end

    if spray then
        if spray.previewCanvas then Canvas.destroy(spray.previewCanvas) end
        spray = nil
    end

    mode        = nil
    corner1     = nil
    canvasDef   = nil
    lockedColor = nil

    setControlsBlocked(false)
    setMovementBlocked(false)
    removeProp()
    setPedAnimation(localPlayer, false)
    setElementData(localPlayer, "spraypaint:busy", false, false)

    unbindKey(Config.Keys.Action, "down", Paint.onAction)
    unbindKey(Config.Keys.Cancel, "down", Paint.onCancel)

    if not silent then
        Notify("Spray", "Spraying cancelled.", {200, 200, 200})
    end
end

-- ─── Starting ────────────────────────────────────────────────────────────────

function Paint.start(forcedColor)
    if mode then return end
    if Eraser and Eraser.isActive() then return end
    if isPedInVehicle(localPlayer) then
        return Notify("Spray", "You can't spray inside a vehicle.", {255, 80, 80})
    end

    mode        = "select"
    corner1     = nil
    lockedColor = forcedColor

    setControlsBlocked(true)
    attachProp(Config.SprayCanModel)
    setElementData(localPlayer, "spraypaint:busy", true, false)

    bindKey(Config.Keys.Action, "down", Paint.onAction)
    bindKey(Config.Keys.Cancel, "down", Paint.onCancel)

    Notify("Spray", "Aim at a wall and mark two corners of the surface with the left button.",
        {120, 220, 255})
end

addEvent("spraypaint:beginPaint", true)
addEventHandler("spraypaint:beginPaint", root, function(forcedColor)
    Paint.start(forcedColor)
end)

-- ─── Selecting the surface ───────────────────────────────────────────────────

-- Turns two corners on the same wall into a rectangle aligned with the vertical.
local function buildCanvasDef(c1, x2, y2, z2)
    local rx, ry, rz, ux, uy, uz = Util.basisFromNormal(c1.nx, c1.ny, c1.nz)

    local dx, dy, dz = x2 - c1.x, y2 - c1.y, z2 - c1.z
    local a = Util.dot(dx, dy, dz, rx, ry, rz)
    local b = Util.dot(dx, dy, dz, ux, uy, uz)

    local width, height = math.abs(a), math.abs(b)

    if width < Config.MinAreaSize or height < Config.MinAreaSize then
        return nil, "The surface is too small."
    end

    width  = math.min(width,  Config.MaxAreaWidth)
    height = math.min(height, Config.MaxAreaHeight)

    local ca = (a >= 0 and 1 or -1) * width  * 0.5
    local cb = (b >= 0 and 1 or -1) * height * 0.5

    return {
        x  = c1.x + rx*ca + ux*cb,
        y  = c1.y + ry*ca + uy*cb,
        z  = c1.z + rz*ca + uz*cb,
        nx = c1.nx, ny = c1.ny, nz = c1.nz,
        width = width, height = height,
    }
end

local function notify(text, color)
    Notify("Spray", text, color or {255, 150, 50})
end

local function handleSelectClick()
    local hx, hy, hz, nx, ny, nz = Aim.getWorldHit(Config.SelectionMaxDistance)
    if not hx then return notify("Aim at a wall in range.") end

    if Util.isBlacklisted(hx, hy, hz) then
        return notify("You can't spray here.", {255, 80, 80})
    end

    if not corner1 then
        corner1 = { x = hx, y = hy, z = hz, nx = nx, ny = ny, nz = nz }
        return notify("First corner marked. Mark the second one.", {120, 220, 255})
    end

    -- The second corner has to lie on a surface facing the same way, otherwise
    -- the canvas would hang in mid-air
    if Util.dot(nx, ny, nz, corner1.nx, corner1.ny, corner1.nz) < 0.9 then
        return notify("Both corners must be on the same wall.")
    end

    local def, err = buildCanvasDef(corner1, hx, hy, hz)
    if not def then return notify(err) end

    canvasDef = def
    corner1   = nil
    Paint.openEditor()
end

-- ─── Editor ──────────────────────────────────────────────────────────────────

function Paint.openEditor()
    mode = "editor"

    -- No walking while drawing; the mouse belongs to the editor
    setMovementBlocked(true)

    local ok = Editor.open(lockedColor,
        function(strokes) Paint.beginSpraying(strokes) end,
        function() Paint.stop() end)

    if not ok then
        notify("Could not open the editor.", {255, 80, 80})
        Paint.stop(true)
    end
end

-- ─── Spraying phase ──────────────────────────────────────────────────────────

-- Turns the player towards the wall so the animation doesn't look like they are
-- spraying into thin air.
local function facePlayerToWall(def)
    local dx, dy = -def.nx, -def.ny
    if math.abs(dx) < 0.001 and math.abs(dy) < 0.001 then return end
    setPedRotation(localPlayer, math.deg(math.atan2(-dx, dy)))
end

function Paint.beginSpraying(strokes)
    mode = "spraying"
    setMovementBlocked(true)

    local total = 0
    for i = 1, #strokes do total = total + #strokes[i].p / 2 end

    local preview = {}
    spray = {
        def           = canvasDef,
        strokes       = strokes,
        totalPoints   = total,
        preview       = preview,
        previewCanvas = Canvas.new(preview, true),
        startedAt     = getTickCount(),
        revealed      = 0,
        curStroke     = 1,
        curPoint      = 0,
    }

    if not spray.previewCanvas then
        notify("Could not create the canvas.", {255, 80, 80})
        return Paint.stop(true)
    end

    facePlayerToWall(canvasDef)
    setPedAnimation(localPlayer, Config.SprayAnimBlock, Config.SprayAnimName, -1, true, false, false)

    Notify("Spray", "Spraying...", {120, 220, 255})
end

-- Reveals the points of the design gradually, so the graffiti "grows" on the
-- wall over time. Points are only ever APPENDED to the preview, which is what
-- makes the incremental render target drawing work without redrawing anything
-- from scratch.
local function revealProgress(progress)
    local target = math.floor(spray.totalPoints * progress)

    while spray.revealed < target do
        local si = spray.curStroke
        local src = spray.strokes[si]
        if not src then break end

        if not spray.preview[si] then
            spray.preview[si] = { c = src.c, b = src.b, p = {} }
            spray.curPoint = 0
        end

        if spray.curPoint * 2 >= #src.p then
            spray.curStroke = si + 1
            spray.curPoint  = 0
        else
            spray.curPoint = spray.curPoint + 1
            local dst = spray.preview[si].p
            dst[#dst + 1] = src.p[spray.curPoint*2 - 1]
            dst[#dst + 1] = src.p[spray.curPoint*2]
            spray.revealed = spray.revealed + 1
        end
    end
end

local function finishSpraying()
    local def = spray.def

    triggerServerEvent("spraypaint:save", localPlayer, {
        x = def.x, y = def.y, z = def.z,
        nx = def.nx, ny = def.ny, nz = def.nz,
        width = def.width, height = def.height,
        dimension = getElementDimension(localPlayer),
        interior  = getElementInterior(localPlayer),
        strokes   = spray.strokes,
    })

    Paint.stop(true)
end

local function updateSpraying()
    local elapsed = getTickCount() - spray.startedAt
    local progress = math.min(1, elapsed / Config.SprayDuration)

    revealProgress(progress)

    -- If something drags the player away from the wall, spraying is aborted.
    -- The threshold has headroom below the server limit so the client doesn't
    -- send something the server would reject anyway.
    local px, py, pz = getElementPosition(localPlayer)
    if Util.dist3D(px, py, pz, spray.def.x, spray.def.y, spray.def.z)
       > Config.MaxSaveDistance - Config.SprayMoveTolerance then
        notify("You moved away from the wall, spraying aborted.")
        return Paint.stop(true)
    end

    if progress >= 1 then
        finishSpraying()
        return false
    end

    return true
end

-- ─── Key actions ─────────────────────────────────────────────────────────────

function Paint.onAction()
    if mode == "select" then handleSelectClick() end
end

function Paint.onCancel()
    -- Inside the editor, Backspace is handled by the editor itself
    if mode == "select" or mode == "spraying" then Paint.stop() end
end

-- ─── Render loop ─────────────────────────────────────────────────────────────

addEventHandler("onClientRender", root, function()
    if not mode then return end

    if mode == "spraying" and spray then
        -- updateSpraying may end the spraying; after that spray is gone
        if updateSpraying() and spray then
            Canvas.flush(spray.previewCanvas)
            Graffiti_drawSurface(spray.def.x, spray.def.y, spray.def.z,
                                 spray.def.nx, spray.def.ny, spray.def.nz,
                                 spray.def.width, spray.def.height, spray.previewCanvas.rt)
        end
    end

    HUD_draw(mode, corner1, spray)
end)

-- ─── Access for the other modules ────────────────────────────────────────────

function Paint.getMode() return mode end

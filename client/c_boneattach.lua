--[[
    spraypaint - minimal bone attachment (client side).

    Replaces the external bone_attach resource. All this script needs is to keep
    the spray can / cloth in the player's hand while the animation plays.

    The bone's world position is read every frame with getPedBonePosition() and
    the configured offset is applied in the ped's local space (X = right,
    Y = forward, Z = up). Good enough for a prop in a hand during a fixed
    animation, and it costs one element per player at most.

    The render handler is only active while something is attached.
]]--

BoneAttach = {}

local attached = {}        -- [element] = { ped, bone, pos, rot }
local handlerActive = false

local function update()
    for el, a in pairs(attached) do
        if not isElement(el) or not isElement(a.ped) then
            attached[el] = nil
        else
            local bx, by, bz = getPedBonePosition(a.ped, a.bone)
            if bx then
                local _, _, pedRz = getElementRotation(a.ped)
                local rad = math.rad(pedRz)
                local cos, sin = math.cos(rad), math.sin(rad)
                local ox, oy, oz = a.pos[1], a.pos[2], a.pos[3]

                setElementPosition(el,
                    bx + ox * cos - oy * sin,
                    by + ox * sin + oy * cos,
                    bz + oz, false)
                setElementRotation(el, a.rot[1], a.rot[2], pedRz + a.rot[3])
            end
        end
    end

    if not next(attached) and handlerActive then
        removeEventHandler("onClientPedsProcessed", root, update)
        handlerActive = false
    end
end

function BoneAttach.attach(el, ped, bone, x, y, z, rx, ry, rz)
    if not isElement(el) or not isElement(ped) then return false end

    attached[el] = {
        ped  = ped,
        bone = tonumber(bone) or 12,
        pos  = { tonumber(x) or 0, tonumber(y) or 0, tonumber(z) or 0 },
        rot  = { tonumber(rx) or 0, tonumber(ry) or 0, tonumber(rz) or 0 },
    }

    if not handlerActive then
        addEventHandler("onClientPedsProcessed", root, update)
        handlerActive = true
    end
    return true
end

function BoneAttach.detach(el)
    attached[el] = nil
    return true
end

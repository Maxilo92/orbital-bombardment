-- Names and timings shared between the prototypes and control.lua.
local shared = {}

shared.CANNON = "orbital-cannon"
shared.DESIGNATOR = "orbital-strike-designator"
shared.TECHNOLOGY = "orbital-bombardment"

-- Ammo item -> what comes down on the target. Every ammo for the cannon needs an
-- entry here; `radius` is what the target marker draws. A round with
-- `bomblets` breaks up above the target and rains that many `strike`s over a
-- circle of `spread` tiles instead of falling as one.
shared.AMMO = {
    ["tungsten-penetrator"] = {strike = "orbital-penetrator-strike", radius = 10},
    ["tungsten-slug"] = {strike = "orbital-slug-strike", radius = 4},
    ["orbital-cluster-rod"] = {strike = "orbital-cluster-bomblet", radius = 14, bomblets = 12, spread = 12},
}

-- The order rounds are offered in on the designator's ammo bar.
shared.AMMO_ORDER = {"tungsten-penetrator", "tungsten-slug", "orbital-cluster-rod"}

-- {ammo name = count} of the cannon rounds in an inventory, any quality.
function shared.count_ammo(inventory)
    local counts = {}
    if not inventory then return counts end
    for _, item in pairs(inventory.get_contents()) do
        if shared.AMMO[item.name] then
            counts[item.name] = (counts[item.name] or 0) + item.count
        end
    end
    return counts
end

shared.FLIGHT_TICKS = 300  -- firing to impact: the warning countdown on the ground
shared.FALL_TICKS = 10     -- the last part of that: the rod covers FALL_HEIGHT in a sixth of a second
shared.FALL_HEIGHT = 100   -- tiles above the target the rod starts its visible fall
shared.RELOAD_TICKS = 600  -- per cannon
shared.MAX_QUEUE = 40      -- marked targets waiting per force and planet

return shared

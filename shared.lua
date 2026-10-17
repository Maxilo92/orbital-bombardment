-- Names and timings shared between the prototypes and control.lua.
local shared = {}

shared.CANNON = "orbital-cannon"
shared.DESIGNATOR = "orbital-strike-designator"
shared.TECHNOLOGY = "orbital-bombardment"

-- Ammo item -> what comes down on the target. Every ammo for the cannon needs an
-- entry here; `radius` is what the target marker draws. A round with
-- `bomblets` breaks up above the target and rains about that many `strike`s
-- over a circle of `spread` tiles instead of falling as one; a round with
-- `emp` releases the EMP described below where it lands.
shared.AMMO = {
    ["tungsten-penetrator"] = {strike = "orbital-penetrator-strike", radius = 10},
    ["tungsten-slug"] = {strike = "orbital-slug-strike", radius = 4},
    ["orbital-cluster-rod"] = {strike = "orbital-cluster-bomblet", radius = 14, bomblets = 12, spread = 12},
    ["orbital-emp-rod"] = {strike = "orbital-emp-strike", radius = 12, emp = true},
}

-- The order rounds are offered in on the designator's ammo bar.
shared.AMMO_ORDER = {"tungsten-penetrator", "tungsten-slug", "orbital-cluster-rod", "orbital-emp-rod"}

-- The EMP: electric damage to everything hostile in the circle, a stun for
-- units, worms and nests switched off for a while, and tesla-style chain
-- lightning jumping from victim to victim.
shared.EMP_DAMAGE = 1200
shared.EMP_DISABLE_TICKS = 8 * 60
shared.EMP_STUN_TICKS = 5 * 60
shared.EMP_CHAINS = 4         -- chain lightnings started from ground zero
shared.EMP_CHAIN_JUMPS = 8
shared.EMP_CHAIN_RANGE = 9
shared.EMP_CHAIN_DAMAGE = 150
shared.EMP_TENDRILS = 8       -- arcs crackling out into the circle
shared.EMP_LIGHTNING = 1      -- one bolt at ground zero, no storm

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

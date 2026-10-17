-- Names and timings shared between the prototypes and control.lua.
local shared = {}

shared.CANNON = "orbital-cannon"
shared.DESIGNATOR = "orbital-strike-designator"
shared.TECHNOLOGY = "orbital-bombardment"

-- Ammo item -> what comes down on the target. Every ammo for the cannon needs an
-- entry here; `radius` is what the target marker draws, `flight` the ticks
-- from firing to impact (the countdown on the ground), `reload` how long the
-- cannon needs before its next shot. A round with `bomblets` breaks up above
-- the target and rains about that many `strike`s over a circle of `spread`
-- tiles instead of falling as one; a round with
-- `emp` releases the EMP described below where it lands, one with `napalm`
-- sprays burning streams over its circle. A `guided` round locks on to an
-- enemy instead of a spot and follows it until shortly before impact.
shared.AMMO = {
    -- the all-rounder: a whole nest cluster in one hit
    ["tungsten-penetrator"] = {strike = "orbital-penetrator-strike", radius = 10, flight = 5 * 60, reload = 10 * 60},
    -- the quick shot: fastest down, fastest reload, one target only
    ["tungsten-slug"] = {strike = "orbital-slug-strike", radius = 2.5, flight = 2 * 60, reload = 4 * 60},
    -- the widest circle by far, but many light hits instead of one heavy one
    ["orbital-cluster-rod"] = {strike = "orbital-cluster-bomblet", radius = 20, bomblets = 16, spread = 18,
                               flight = 7 * 60, reload = 12 * 60},
    -- barely hurts, but stops everything in a wide circle - and arrives fast
    ["orbital-emp-rod"] = {strike = "orbital-emp-strike", radius = 14, emp = true, flight = 3 * 60, reload = 8 * 60},
    -- a tight circle that keeps burning
    ["orbital-incendiary-rod"] = {strike = "orbital-incendiary-strike", radius = 7, napalm = true,
                                  flight = 6 * 60, reload = 10 * 60},
    -- slow and patient: tracks its target the whole long way down
    ["orbital-guided-rod"] = {strike = "orbital-guided-strike", radius = 4, guided = true, flight = 8 * 60, reload = 15 * 60},
}

-- The order rounds are offered in on the designator's ammo bar.
shared.AMMO_ORDER = {"tungsten-penetrator", "tungsten-slug", "orbital-cluster-rod", "orbital-emp-rod", "orbital-incendiary-rod", "orbital-guided-rod"}

-- The EMP: electric damage to everything hostile in the circle, a stun for
-- units, worms and nests switched off for a while, and tesla-style chain
-- lightning jumping from victim to victim.
shared.EMP_DAMAGE = 600
shared.EMP_DISABLE_TICKS = 8 * 60
shared.EMP_STUN_TICKS = 5 * 60
shared.EMP_CHAINS = 4         -- chain lightnings started from ground zero
shared.EMP_CHAIN_JUMPS = 8
shared.EMP_CHAIN_RANGE = 9
shared.EMP_CHAIN_DAMAGE = 150
shared.EMP_TENDRILS = 8       -- arcs crackling out into the circle

-- The incendiary rod: burning streams sprayed from ground zero over the
-- circle; where they land the ground burns for NAPALM_BURN_TICKS.
shared.NAPALM_STREAMS = 22

-- The guided rod: the designator snaps to the nearest enemy within
-- GUIDED_SNAP_RADIUS of the click. The rod follows it until GUIDED_LOCK_TICKS
-- before impact, then commits to where the target will be by then.
shared.GUIDED_SNAP_RADIUS = 8
shared.GUIDED_LOCK_TICKS = 60
shared.GUIDED_MAX_LEAD = 15 -- tiles the aim may be led ahead of the target
shared.NAPALM_BURN_TICKS = 15 * 60

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

shared.FALL_TICKS = 10     -- the last part of that: the rod covers FALL_HEIGHT in a sixth of a second
shared.FALL_HEIGHT = 100   -- tiles above the target the rod starts its visible fall
shared.MAX_QUEUE = 40      -- marked targets waiting per force and planet

return shared

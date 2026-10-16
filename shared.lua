-- Names and timings shared between the prototypes and control.lua.
local shared = {}

shared.CANNON = "orbital-cannon"
shared.DESIGNATOR = "orbital-strike-designator"
shared.TECHNOLOGY = "orbital-bombardment"

-- Ammo item -> what comes down on the target. Every ammo for the cannon needs an
-- entry here; the strike radius is what the target marker draws.
shared.AMMO = {
    ["tungsten-penetrator"] = {strike = "orbital-penetrator-strike", radius = 10},
}

shared.FLIGHT_TICKS = 300  -- firing to impact: the warning countdown on the ground
shared.FALL_TICKS = 10     -- the last part of that: the rod covers FALL_HEIGHT in a sixth of a second
shared.FALL_HEIGHT = 100   -- tiles above the target the rod starts its visible fall
shared.RELOAD_TICKS = 600  -- per cannon
shared.MAX_QUEUE = 40      -- marked targets waiting per force and planet

return shared

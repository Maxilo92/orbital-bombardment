-- Tungsten penetrator: a kinetic rod. No explosive, no fallout - it hits hard,
-- digs a crater and levels cliffs at ground zero.
--
-- The ammo_type below is never run by the engine: the cannon cannot fire on its
-- own (see cannon.lua), and control.lua turns a spent round into the strike
-- listed for it in shared.AMMO. It only has to be a valid ammo definition.

local penetrator = {
    type = "ammo",
    name = "tungsten-penetrator",
    icons = {{icon = "__space-age__/graphics/icons/railgun-ammo.png", tint = {r = 1, g = 0.82, b = 0.62}}},
    ammo_category = "orbital-strike",
    ammo_type = {
        target_type = "position",
        action = {
            type = "direct",
            action_delivery = {
                type = "instant",
                target_effects = {{type = "script", effect_id = "orbital-penetrator-unused"}},
            },
        },
    },
    subgroup = "ammo",
    order = "d[explosive-cannon-shell]-e[orbital]-a[tungsten-penetrator]",
    stack_size = 10,
    weight = 50 * kg, -- twenty per rocket
}

local recipe = {
    type = "recipe",
    name = "tungsten-penetrator",
    enabled = false,
    energy_required = 15,
    ingredients = {
        {type = "item", name = "tungsten-plate", amount = 10},
        {type = "item", name = "tungsten-carbide", amount = 4},
        {type = "item", name = "low-density-structure", amount = 1},
        {type = "item", name = "processing-unit", amount = 1},
    },
    results = {{type = "item", name = "tungsten-penetrator", amount = 1}},
}

data:extend({penetrator, recipe})

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

-- Tungsten slug: a plain cast bar. Cheap, and almost no blast - the whole
-- impact goes into whatever it hits. The sniper shot of the two rounds.
local slug = table.deepcopy(penetrator)
slug.name = "tungsten-slug"
slug.icons = {{icon = "__space-age__/graphics/icons/tungsten-plate.png", tint = {r = 0.85, g = 0.88, b = 1}}}
slug.order = "d[explosive-cannon-shell]-e[orbital]-b[tungsten-slug]"
slug.stack_size = 20
slug.weight = 40 * kg -- twenty-five per rocket

local slug_recipe = {
    type = "recipe",
    name = "tungsten-slug",
    enabled = false,
    energy_required = 5,
    ingredients = {
        {type = "item", name = "tungsten-plate", amount = 10},
    },
    results = {{type = "item", name = "tungsten-slug", amount = 1}},
}

data:extend({slug, slug_recipe})

-- Cluster rod: breaks up high above the target and rains a dozen bomblets over
-- a wide circle - for nests spread too far apart for one penetrator.
local cluster = table.deepcopy(penetrator)
cluster.name = "orbital-cluster-rod"
cluster.icons = {{icon = "__space-age__/graphics/icons/railgun-ammo.png", tint = {r = 1, g = 0.55, b = 0.35}}}
cluster.order = "d[explosive-cannon-shell]-e[orbital]-c[cluster-rod]"
cluster.stack_size = 10
cluster.weight = 50 * kg

local cluster_recipe = {
    type = "recipe",
    name = "orbital-cluster-rod",
    enabled = false,
    energy_required = 20,
    ingredients = {
        {type = "item", name = "tungsten-carbide", amount = 6},
        {type = "item", name = "explosives", amount = 10},
        {type = "item", name = "low-density-structure", amount = 2},
        {type = "item", name = "processing-unit", amount = 2},
    },
    results = {{type = "item", name = "orbital-cluster-rod", amount = 1}},
}

data:extend({cluster, cluster_recipe})

-- EMP rod: a bundle of tesla charges from Fulgora in a tungsten shell. Little
-- damage; it stuns units, switches off worms and nests for a while and sends
-- tesla chain lightning through the target - the strike to open with before
-- going in on the ground.
local emp = table.deepcopy(penetrator)
emp.name = "orbital-emp-rod"
emp.icons = {{icon = "__space-age__/graphics/icons/railgun-ammo.png", tint = {r = 0.5, g = 0.8, b = 1}}}
emp.order = "d[explosive-cannon-shell]-e[orbital]-d[emp-rod]"
emp.stack_size = 10
emp.weight = 50 * kg

local emp_recipe = {
    type = "recipe",
    name = "orbital-emp-rod",
    enabled = false,
    energy_required = 20,
    ingredients = {
        {type = "item", name = "tesla-ammo", amount = 10},
        {type = "item", name = "supercapacitor", amount = 2},
        {type = "item", name = "tungsten-plate", amount = 5},
        {type = "item", name = "processing-unit", amount = 1},
    },
    results = {{type = "item", name = "orbital-emp-rod", amount = 1}},
}

data:extend({emp, emp_recipe})

local shared = require("shared")

-- Sits right after Artillery (which Space Age already gates behind Vulcanus)
-- and tungsten steel, and costs a step more than Artillery's 1500.
data:extend({
    {
        type = "technology",
        name = shared.TECHNOLOGY,
        icons = {{icon = "__base__/graphics/technology/artillery.png", icon_size = 256, tint = {r = 0.78, g = 0.84, b = 1}}},
        prerequisites = {"artillery", "tungsten-steel"},
        effects = {
            {type = "unlock-recipe", recipe = shared.CANNON},
            {type = "unlock-recipe", recipe = "tungsten-penetrator"},
            {type = "unlock-recipe", recipe = "tungsten-slug"},
            {type = "unlock-recipe", recipe = "orbital-steel-rod"},
        },
        unit = {
            count = 2000,
            time = 60,
            ingredients = {
                {"automation-science-pack", 1},
                {"logistic-science-pack", 1},
                {"chemical-science-pack", 1},
                {"military-science-pack", 1},
                {"utility-science-pack", 1},
                {"space-science-pack", 1},
                {"metallurgic-science-pack", 1},
            },
        },
    },
})

data:extend({
    {
        type = "technology",
        name = "orbital-cluster-munition",
        icons = {{icon = "__base__/graphics/technology/artillery.png", icon_size = 256, tint = {r = 1, g = 0.62, b = 0.45}}},
        prerequisites = {shared.TECHNOLOGY},
        effects = {
            {type = "unlock-recipe", recipe = "orbital-cluster-rod"},
        },
        unit = {
            count = 1500,
            time = 60,
            ingredients = {
                {"automation-science-pack", 1},
                {"logistic-science-pack", 1},
                {"chemical-science-pack", 1},
                {"military-science-pack", 1},
                {"utility-science-pack", 1},
                {"space-science-pack", 1},
                {"metallurgic-science-pack", 1},
            },
        },
    },
})

data:extend({
    {
        type = "technology",
        name = "orbital-emp-munition",
        icons = {{icon = "__base__/graphics/technology/artillery.png", icon_size = 256, tint = {r = 0.55, g = 0.8, b = 1}}},
        prerequisites = {shared.TECHNOLOGY, "electromagnetic-science-pack"},
        effects = {
            {type = "unlock-recipe", recipe = "orbital-emp-rod"},
        },
        unit = {
            count = 1500,
            time = 60,
            ingredients = {
                {"automation-science-pack", 1},
                {"logistic-science-pack", 1},
                {"chemical-science-pack", 1},
                {"military-science-pack", 1},
                {"utility-science-pack", 1},
                {"space-science-pack", 1},
                {"metallurgic-science-pack", 1},
                {"electromagnetic-science-pack", 1},
            },
        },
    },
})

data:extend({
    {
        type = "technology",
        name = "orbital-incendiary-munition",
        icons = {{icon = "__base__/graphics/technology/artillery.png", icon_size = 256, tint = {r = 1, g = 0.5, b = 0.3}}},
        prerequisites = {shared.TECHNOLOGY, "flamethrower"},
        effects = {
            {type = "unlock-recipe", recipe = "orbital-incendiary-rod"},
        },
        unit = {
            count = 1500,
            time = 60,
            ingredients = {
                {"automation-science-pack", 1},
                {"logistic-science-pack", 1},
                {"chemical-science-pack", 1},
                {"military-science-pack", 1},
                {"utility-science-pack", 1},
                {"space-science-pack", 1},
                {"metallurgic-science-pack", 1},
            },
        },
    },
})

data:extend({
    {
        type = "technology",
        name = "orbital-guided-munition",
        icons = {{icon = "__base__/graphics/technology/artillery.png", icon_size = 256, tint = {r = 0.75, g = 1, b = 0.6}}},
        prerequisites = {shared.TECHNOLOGY},
        effects = {
            {type = "unlock-recipe", recipe = "orbital-guided-rod"},
        },
        unit = {
            count = 2000,
            time = 60,
            ingredients = {
                {"automation-science-pack", 1},
                {"logistic-science-pack", 1},
                {"chemical-science-pack", 1},
                {"military-science-pack", 1},
                {"utility-science-pack", 1},
                {"space-science-pack", 1},
                {"metallurgic-science-pack", 1},
            },
        },
    },
})

data:extend({
    {
        type = "technology",
        name = shared.FIRE_CONTROL,
        icons = {{icon = "__base__/graphics/technology/artillery.png", icon_size = 256, tint = {r = 1, g = 0.9, b = 0.55}}},
        prerequisites = {shared.TECHNOLOGY},
        effects = {
            {type = "nothing", effect_description = {"orbital-bombardment.fire-control-effect"}, use_icon_overlay_constant = true},
        },
        unit = {
            count = 1500,
            time = 60,
            ingredients = {
                {"automation-science-pack", 1},
                {"logistic-science-pack", 1},
                {"chemical-science-pack", 1},
                {"military-science-pack", 1},
                {"utility-science-pack", 1},
                {"space-science-pack", 1},
                {"metallurgic-science-pack", 1},
            },
        },
    },
})

-- Infinite research. Both are counted by control.lua: the strikes are made by
-- script, so the vanilla bonus modifiers would not reach them.
local function infinite(name, tint, description)
    return {
        type = "technology",
        name = name,
        icons = {{icon = "__base__/graphics/technology/artillery.png", icon_size = 256, tint = tint}},
        prerequisites = {shared.TECHNOLOGY},
        effects = {{type = "nothing", effect_description = description, use_icon_overlay_constant = true}},
        max_level = "infinite",
        upgrade = true,
        unit = {
            count_formula = "1000 * 1.5^(L-1)",
            time = 60,
            ingredients = {
                {"automation-science-pack", 1},
                {"logistic-science-pack", 1},
                {"chemical-science-pack", 1},
                {"military-science-pack", 1},
                {"utility-science-pack", 1},
                {"space-science-pack", 1},
                {"metallurgic-science-pack", 1},
            },
        },
    }
end

data:extend({
    infinite(shared.DAMAGE_TECH, {r = 1, g = 0.45, b = 0.35},
        {"orbital-bombardment.damage-tech-effect", tostring(math.floor(shared.DAMAGE_PER_LEVEL * 100))}),
    infinite(shared.RELOAD_TECH, {r = 0.45, g = 0.75, b = 1},
        {"orbital-bombardment.reload-tech-effect", tostring(math.floor(shared.RELOAD_PER_LEVEL * 100))}),
})

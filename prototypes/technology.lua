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

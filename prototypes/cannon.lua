-- The orbital cannon: an artillery turret that only stands on space platforms.
--
-- It is an artillery turret because that is what already brings everything a
-- gun on a platform needs - an ammo slot that only takes its own ammo, inserter
-- and logistics support, the vanilla turret window, rotation and recoil. It never
-- fires on its own (disable_automatic_firing) and its ammo category is one no
-- vanilla flare or remote can trigger, so the engine never shoots it at all:
-- control.lua takes a round out of the ammo slot and sends the strike down to the
-- planet the platform is parked over.

local shared = require("shared")

local TINT = {r = 0.78, g = 0.84, b = 1}

-- Tints every sprite in a picture definition except its shadows.
local function tint(picture)
    if type(picture) ~= "table" then return end
    if picture.layers then
        for _, layer in pairs(picture.layers) do tint(layer) end
    elseif picture.filename or picture.filenames or picture.stripes then
        if not picture.draw_as_shadow then picture.tint = TINT end
    else
        for _, child in pairs(picture) do tint(child) end
    end
end

local gun = table.deepcopy(data.raw["gun"]["artillery-wagon-cannon"])
gun.name = "orbital-cannon-gun"
gun.attack_parameters.ammo_category = "orbital-strike"

local category = {
    type = "ammo-category",
    name = "orbital-strike",
    icon = "__base__/graphics/icons/ammo-category/artillery-shell.png",
    subgroup = "ammo-category",
}

local cannon = table.deepcopy(data.raw["artillery-turret"]["artillery-turret"])
cannon.name = shared.CANNON
cannon.icon = nil
cannon.icons = {{icon = "__base__/graphics/icons/artillery-turret.png", tint = TINT}}
cannon.minable = {mining_time = 1, result = shared.CANNON}
cannon.fast_replaceable_group = nil
cannon.next_upgrade = nil
cannon.gun = gun.name
cannon.disable_automatic_firing = true
cannon.alert_when_attacking = false
cannon.inventory_size = 1
cannon.ammo_stack_limit = 10
cannon.automated_ammo_count = 5
cannon.max_health = 3000
-- Space Age heats artillery against Aquilo's cold; a platform has no use for it.
cannon.heating_energy = nil
-- Platforms only. Pressure 0 is the same condition the thruster and the asteroid
-- collector use.
cannon.surface_conditions = {{property = "pressure", min = 0, max = 0}}
tint(cannon.base_picture)
tint(cannon.cannon_base_pictures)
tint(cannon.cannon_barrel_pictures)
cannon.map_color = {r = 0.55, g = 0.65, b = 1}

local item = table.deepcopy(data.raw["item"]["artillery-turret"])
item.name = shared.CANNON
item.icon = nil
item.icons = cannon.icons
item.place_result = shared.CANNON
item.order = "b[turret]-d[artillery-turret]-c[orbital-cannon]"
item.weight = 500 * kg -- two per rocket

local recipe = {
    type = "recipe",
    name = shared.CANNON,
    enabled = false,
    energy_required = 30,
    ingredients = {
        {type = "item", name = "artillery-turret", amount = 1},
        {type = "item", name = "tungsten-plate", amount = 50},
        {type = "item", name = "low-density-structure", amount = 20},
        {type = "item", name = "processing-unit", amount = 20},
    },
    results = {{type = "item", name = shared.CANNON, amount = 1}},
}

-- Muzzle flash on the platform when the cannon fires: the vanilla artillery
-- flash plus a cold blue light, since the round leaves at railgun speed.
local flash = table.deepcopy(data.raw["explosion"]["artillery-cannon-muzzle-flash"])
flash.name = "orbital-cannon-muzzle-flash"
flash.light = {intensity = 1, size = 18, color = {r = 0.55, g = 0.8, b = 1}}

data:extend({gun, category, cannon, item, recipe, flash})

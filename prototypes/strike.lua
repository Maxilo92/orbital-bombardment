-- What comes down on the planet: the falling rod and its impact, plus the
-- sounds control.lua plays around it.
--
-- The rod is a plain projectile that control.lua spawns FALL_HEIGHT tiles north
-- of the target and sends straight down, timed to land when the warning
-- countdown runs out. Seen in Factorio's top-down perspective, something
-- streaking down the screen at that speed reads as falling out of the sky.
--
-- The impact borrows the atomic bomb's blast-wave technique (invisible wave
-- projectiles fired out of ground zero, each dropping dust or a shockwave
-- fragment where it lands) at a much smaller scale and in the vanilla colours:
-- this is a kinetic hit, not a nuclear one.

local shared = require("shared")
local sounds = require("__base__.prototypes.entity.sounds")
local rocket_pictures = require("__base__.prototypes.entity.rocket-projectile-pictures")

local MOD = "__orbital-bombardment__"

local function scale_all(anim, factor)
    if type(anim) ~= "table" then return end
    if anim.layers then
        for _, layer in pairs(anim.layers) do scale_all(layer, factor) end
    elseif anim.filename or anim.filenames or anim.stripes then
        anim.scale = (anim.scale or 1) * factor
    else
        for _, child in pairs(anim) do scale_all(child, factor) end
    end
end

-- Fires `count` invisible projectiles from ground zero to random points within
-- `radius` - the atomic rocket's blast-wave mechanism.
local function wave(projectile, count, radius, speed)
    return {
        type = "nested-result",
        action = {
            type = "area",
            show_in_tooltip = false,
            target_entities = false,
            trigger_from_target = true,
            repeat_count = count,
            radius = radius,
            action_delivery = {
                type = "projectile",
                projectile = projectile,
                starting_speed = speed,
                starting_speed_deviation = 0.075,
            },
        },
    }
end

local function wave_projectile(name, source, payload)
    local projectile = table.deepcopy(data.raw["projectile"][source])
    projectile.name = name
    projectile.action = {{type = "direct", action_delivery = {type = "instant", target_effects = {payload}}}}
    return projectile
end

local function area_damage(radius, damages)
    local effects = {}
    for _, damage in pairs(damages) do
        effects[#effects + 1] = {type = "damage", damage = damage}
    end
    return {
        type = "nested-result",
        action = {
            type = "area",
            radius = radius,
            action_delivery = {type = "instant", target_effects = effects},
        },
    }
end

--------------------------------------------------------------------------------
-- sounds
--------------------------------------------------------------------------------

local function variations(path, count, volume)
    local list = {}
    for i = 1, count do
        list[i] = {filename = path .. "-" .. i .. ".ogg", volume = volume}
    end
    return list
end

data:extend({
    {
        type = "sound",
        name = "orbital-cannon-fire",
        category = "weapon",
        variations = variations("__space-age__/sound/entity/railgun-turret/railgun-turret-gunshot", 5, 0.8),
        audible_distance_modifier = 1.5,
    },
    {
        -- A sonic boom as the rod breaks through: Fulgora's thunder cracks.
        type = "sound",
        name = "orbital-sonic-boom",
        category = "explosion",
        variations = variations("__space-age__/sound/explosions/lightning-effect", 5, 0.7),
        audible_distance_modifier = 3,
    },
    {
        type = "sound",
        name = "orbital-reentry",
        category = "explosion",
        variations = variations(MOD .. "/sound/reentry", 3, 0.9),
        audible_distance_modifier = 2,
    },
})

--------------------------------------------------------------------------------
-- impact visuals
--------------------------------------------------------------------------------

local flash = table.deepcopy(data.raw["explosion"]["big-artillery-explosion"])
flash.name = "orbital-impact-flash"
scale_all(flash.animations, 1.6)
flash.light = {intensity = 1, size = 45, color = {r = 1, g = 0.82, b = 0.6}}
flash.light_intensity_peak_start_progress = 0
flash.light_intensity_peak_end_progress = 0.15
flash.light_intensity_factor_final = 0
flash.light_size_factor_initial = 0.5
flash.light_size_factor_final = 0.7

local p_dust = wave_projectile("orbital-wave-dust", "atomic-bomb-wave-spawns-cluster-nuke-explosion",
    {type = "create-entity", entity_name = "cluster-nuke-explosion"})
local p_fire = wave_projectile("orbital-wave-fire", "atomic-bomb-wave-spawns-fire-smoke-explosion",
    {type = "create-explosion", entity_name = "atomic-fire-smoke",
     max_movement_distance = 7, max_movement_distance_deviation = 1,
     inherit_movement_distance_from_projectile = true, cycle_while_moving = true})
local p_shock = wave_projectile("orbital-wave-shockwave", "atomic-bomb-wave-spawns-nuke-shockwave-explosion",
    {type = "create-explosion", entity_name = "atomic-nuke-shockwave",
     max_movement_distance = 8, max_movement_distance_deviation = 1,
     inherit_movement_distance_from_projectile = true, cycle_while_moving = true})

data:extend({flash, p_dust, p_fire, p_shock})

--------------------------------------------------------------------------------
-- the penetrator
--------------------------------------------------------------------------------

local radius = shared.AMMO["tungsten-penetrator"].radius

-- White-hot head with a flickering re-entry trail (generated by
-- tools/orbital_assets.py). Drawn as glow so it burns through the night.
local beam = {
    filename = MOD .. "/graphics/falling-rod.png",
    priority = "high",
    width = 96,
    height = 640,
    frame_count = 4,
    line_length = 4,
    animation_speed = 0.5,
    scale = 1,
    -- Put the head, not the middle of the trail, on the rod's position. The
    -- engine rotates the sprite to the flight direction but not this shift, so
    -- the value is for the only direction the rod ever flies: straight down,
    -- which turns the sprite upside down and leaves the head 1.75 tiles above
    -- its lower end.
    shift = {0, -(640 / 64 / 2 - 56 / 32)},
    draw_as_glow = true,
}

local rod = {
    type = "projectile",
    name = "orbital-penetrator-strike",
    flags = {"not-on-map"},
    hidden = true,
    acceleration = 0,
    max_speed = 5,
    rotatable = true,
    animation = beam,
    light = {intensity = 1, size = 24, color = {r = 1, g = 0.65, b = 0.35}},
    smoke = rocket_pictures.smoke,
    action = {
        type = "direct",
        action_delivery = {
            type = "instant",
            target_effects = {
                {type = "destroy-cliffs", radius = 6, explosion_at_trigger = "explosion"},
                {type = "create-entity", entity_name = flash.name},
                {type = "create-entity", entity_name = "huge-scorchmark", offsets = {{0, -0.5}}, check_buildability = true},
                {type = "set-tile", tile_name = "nuclear-ground", radius = 4, apply_projection = true,
                 tile_collision_mask = {layers = {water_tile = true}}},
                {type = "destroy-decoratives", radius = radius, include_soft_decoratives = true,
                 include_decals = true, invoke_decorative_trigger = true, decoratives_with_trigger_only = false},
                {type = "invoke-tile-trigger", repeat_count = 1},
                {type = "create-particle", particle_name = "stone-particle-big", repeat_count = 40,
                 initial_height = 0.5, initial_vertical_speed = 0.12, initial_vertical_speed_deviation = 0.08,
                 speed_from_center = 0.15, speed_from_center_deviation = 0.1, offset_deviation = {{-1, -1}, {1, 1}},
                 only_when_visible = true},
                {type = "create-particle", particle_name = "stone-particle-medium", repeat_count = 80,
                 initial_height = 0.4, initial_vertical_speed = 0.1, initial_vertical_speed_deviation = 0.08,
                 speed_from_center = 0.2, speed_from_center_deviation = 0.12, offset_deviation = {{-1.5, -1.5}, {1.5, 1.5}},
                 only_when_visible = true},
                {type = "camera-effect", duration = 50, ease_in_duration = 3, ease_out_duration = 50, delay = 0,
                 strength = 4, full_strength_max_distance = 60, max_distance = 250},
                {type = "play-sound", sound = sounds.nuclear_explosion(0.6), play_on_target_position = true, max_distance = 500},
                {type = "play-sound", sound = sounds.large_explosion(1.0), play_on_target_position = true, max_distance = 300},
                -- Ground zero: nothing survives a direct hit.
                area_damage(4, {{amount = 10000, type = "physical"}}),
                -- The blast around it is still enough for a fully evolved nest
                -- (3500 HP, 15% physical resistance) or a behemoth worm.
                area_damage(radius, {{amount = 3000, type = "explosion"}, {amount = 1500, type = "physical"}}),
                wave(p_dust.name, 220, radius, 0.3),
                wave(p_fire.name, 120, 2, 0.28),
                wave(p_shock.name, 260, 3, 0.3),
            },
        },
    },
}

data:extend({rod})

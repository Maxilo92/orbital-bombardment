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

-- The blast wave leaves ground zero fast and brakes hard (negative
-- acceleration), so it reads as an explosive punch rather than a slow bloom.
local function braking(projectile, acceleration)
    projectile.acceleration = acceleration
    return projectile
end
-- A tighter, shorter-lived dust puff than the atomic bomb's: the ring should
-- mark the blast radius, not roll on far past it.
local dust = table.deepcopy(data.raw["explosion"]["cluster-nuke-explosion"])
dust.name = "orbital-impact-dust"
scale_all(dust.animations, 0.75)
dust.scale_increment_per_tick = 0.001
dust.fade_out_duration = 20
local p_dust = braking(wave_projectile("orbital-wave-dust", "atomic-bomb-wave-spawns-cluster-nuke-explosion",
    {type = "create-entity", entity_name = dust.name}), -0.035)
local p_fire = braking(wave_projectile("orbital-wave-fire", "atomic-bomb-wave-spawns-fire-smoke-explosion",
    {type = "create-explosion", entity_name = "atomic-fire-smoke",
     max_movement_distance = 4, max_movement_distance_deviation = 1,
     inherit_movement_distance_from_projectile = true, cycle_while_moving = true}), -0.03)
local p_shock = braking(wave_projectile("orbital-wave-shockwave", "atomic-bomb-wave-spawns-nuke-shockwave-explosion",
    {type = "create-explosion", entity_name = "atomic-nuke-shockwave",
     max_movement_distance = 4, max_movement_distance_deviation = 1,
     inherit_movement_distance_from_projectile = true, cycle_while_moving = true}), -0.04)

-- Secondary fireballs going off around ground zero over the first fifth of a
-- second, so the impact ripples instead of popping once.
local burst = table.deepcopy(data.raw["explosion"]["big-explosion"])
burst.name = "orbital-impact-burst"
burst.delay = 0
burst.delay_deviation = 12
scale_all(burst.animations, 1.3)

data:extend({flash, dust, p_dust, p_fire, p_shock, burst})

--------------------------------------------------------------------------------
-- the fall
--------------------------------------------------------------------------------

-- A rod at several hundred metres per second is not seen, its trail is: a
-- white-hot head streaks from the sky to the ground in four frames, then the
-- ionised column glows on, cools and fades (graphics generated by
-- tools/orbital_assets.py). The bottom of each frame is ground zero, so the
-- sprite is shifted up by half its height minus the head.
local STREAK_FRAMES, STREAK_SPEED = 16, 0.4 -- 4 descent frames = 10 ticks = FALL_TICKS
local streak_animation = {
    filename = MOD .. "/graphics/reentry-streak.png",
    priority = "high",
    width = 96,
    height = 1024,
    frame_count = STREAK_FRAMES,
    line_length = STREAK_FRAMES,
    animation_speed = STREAK_SPEED,
    shift = {0, -(1024 / 2 - 30) / 32},
    draw_as_glow = true,
}
local streak = {
    type = "explosion",
    name = "orbital-reentry-streak",
    flags = {"not-on-map"},
    hidden = true,
    animations = {streak_animation},
    light = {intensity = 1, size = 30, color = {r = 1, g = 0.7, b = 0.45}},
    light_intensity_factor_final = 0,
    light_size_factor_final = 0.5,
}
-- The same streak for the map and minimap, where entities are not drawn;
-- control.lua draws it there with rendering.draw_animation and sets the speed
-- itself. The prototype's own speed is 1 so it cannot slow that down: with
-- 0.4 here the map streak ran late (reported in 0.2.0), consistent with the
-- engine multiplying both speeds.
local streak_chart = table.deepcopy(streak_animation)
streak_chart.type = "animation"
streak_chart.name = "orbital-reentry-streak-chart"
streak_chart.draw_as_glow = nil
streak_chart.animation_speed = 1

data:extend({streak, streak_chart})

--------------------------------------------------------------------------------
-- the penetrator
--------------------------------------------------------------------------------

local radius = shared.AMMO["tungsten-penetrator"].radius

-- The projectile only carries the impact to the ground in exactly FALL_TICKS;
-- everything visible about the fall is the streak above.
local rod = {
    type = "projectile",
    name = "orbital-penetrator-strike",
    flags = {"not-on-map"},
    hidden = true,
    acceleration = 0,
    max_speed = 50,
    rotatable = false,
    light = {intensity = 1, size = 20, color = {r = 1, g = 0.85, b = 0.7}},
    action = {
        type = "direct",
        action_delivery = {
            type = "instant",
            target_effects = {
                {type = "destroy-cliffs", radius = 6, explosion_at_trigger = "explosion"},
                {type = "create-entity", entity_name = flash.name},
                {type = "create-entity", entity_name = burst.name, repeat_count = 8, offset_deviation = {{-3.5, -3.5}, {3.5, 3.5}}},
                {type = "create-entity", entity_name = "huge-scorchmark", offsets = {{0, -0.5}}},
                {type = "set-tile", tile_name = "nuclear-ground", radius = 4, apply_projection = true,
                 tile_collision_mask = {layers = {water_tile = true}}},
                {type = "destroy-decoratives", radius = radius, include_soft_decoratives = true,
                 include_decals = true, invoke_decorative_trigger = true, decoratives_with_trigger_only = false},
                {type = "invoke-tile-trigger", repeat_count = 1},
                -- Ejecta: rock thrown up and out fast enough to leave motion trails.
                {type = "create-particle", particle_name = "stone-particle-big", repeat_count = 50,
                 initial_height = 0.5, initial_vertical_speed = 0.3, initial_vertical_speed_deviation = 0.15,
                 speed_from_center = 0.32, speed_from_center_deviation = 0.18, offset_deviation = {{-1, -1}, {1, 1}},
                 tail_length = 6, tail_length_deviation = 4, tail_width = 3, only_when_visible = true},
                {type = "create-particle", particle_name = "stone-particle-medium", repeat_count = 120,
                 initial_height = 0.4, initial_vertical_speed = 0.22, initial_vertical_speed_deviation = 0.14,
                 speed_from_center = 0.45, speed_from_center_deviation = 0.25, offset_deviation = {{-1.5, -1.5}, {1.5, 1.5}},
                 tail_length = 10, tail_length_deviation = 6, tail_width = 2, only_when_visible = true},
                {type = "create-particle", particle_name = "spark-particle-debris", repeat_count = 60,
                 initial_height = 0.6, initial_vertical_speed = 0.25, initial_vertical_speed_deviation = 0.15,
                 speed_from_center = 0.5, speed_from_center_deviation = 0.3, offset_deviation = {{-1, -1}, {1, 1}},
                 tail_length = 12, tail_length_deviation = 6, tail_width = 2, only_when_visible = true},
                -- A short, hard punch rather than a long rumble.
                {type = "camera-effect", duration = 30, ease_in_duration = 1, ease_out_duration = 45, delay = 0,
                 strength = 7, full_strength_max_distance = 50, max_distance = 250},
                {type = "play-sound", sound = sounds.nuclear_explosion(0.85), play_on_target_position = true, max_distance = 600},
                {type = "play-sound", sound = sounds.large_explosion(1.0), play_on_target_position = true, max_distance = 300},
                {type = "play-sound", sound = sounds.nuclear_explosion_aftershock(0.35), play_on_target_position = true, max_distance = 600},
                -- Ground zero: nothing survives a direct hit.
                area_damage(4, {{amount = 10000, type = "physical"}}),
                -- The blast around it is still enough for a fully evolved nest
                -- (3500 HP, 15% physical resistance) or a behemoth worm.
                area_damage(radius, {{amount = 3000, type = "explosion"}, {amount = 1500, type = "physical"}}),
                wave(p_dust.name, 170, radius, 0.9),
                wave(p_fire.name, 80, 2, 0.8),
                wave(p_shock.name, 200, 3, 1.0),
                -- The crater keeps smouldering for a while.
                {type = "nested-result", action = {
                    type = "area", target_entities = false, trigger_from_target = true,
                    repeat_count = 4, radius = 3, show_in_tooltip = false,
                    action_delivery = {type = "instant", target_effects = {
                        {type = "create-entity", entity_name = "nuclear-smouldering-smoke-source",
                         tile_collision_mask = {layers = {water_tile = true}}},
                    }},
                }},
            },
        },
    },
}

data:extend({rod})

--------------------------------------------------------------------------------
-- the slug
--------------------------------------------------------------------------------

local slug_radius = shared.AMMO["tungsten-slug"].radius

local slug_flash = table.deepcopy(data.raw["explosion"]["big-explosion"])
slug_flash.name = "orbital-slug-flash"
slug_flash.light = {intensity = 1, size = 20, color = {r = 1, g = 0.85, b = 0.65}}
slug_flash.light_intensity_factor_final = 0
slug_flash.light_size_factor_final = 0.6

-- Same fall as the penetrator; a pinpoint hit with the splinters but without
-- the dust ring and the fireballs.
local slug_rod = table.deepcopy(rod)
slug_rod.name = "orbital-slug-strike"
slug_rod.light = {intensity = 1, size = 12, color = {r = 1, g = 0.85, b = 0.7}}
slug_rod.action.action_delivery.target_effects = {
    {type = "create-entity", entity_name = slug_flash.name},
    {type = "create-entity", entity_name = "medium-scorchmark", offsets = {{0, -0.5}}},
    {type = "destroy-decoratives", radius = slug_radius, include_soft_decoratives = true,
     include_decals = true, invoke_decorative_trigger = true, decoratives_with_trigger_only = false},
    {type = "invoke-tile-trigger", repeat_count = 1},
    {type = "create-particle", particle_name = "stone-particle-big", repeat_count = 20,
     initial_height = 0.5, initial_vertical_speed = 0.28, initial_vertical_speed_deviation = 0.12,
     speed_from_center = 0.3, speed_from_center_deviation = 0.15, offset_deviation = {{-0.5, -0.5}, {0.5, 0.5}},
     tail_length = 6, tail_length_deviation = 4, tail_width = 3, only_when_visible = true},
    {type = "create-particle", particle_name = "stone-particle-medium", repeat_count = 60,
     initial_height = 0.4, initial_vertical_speed = 0.22, initial_vertical_speed_deviation = 0.12,
     speed_from_center = 0.4, speed_from_center_deviation = 0.2, offset_deviation = {{-0.5, -0.5}, {0.5, 0.5}},
     tail_length = 10, tail_length_deviation = 6, tail_width = 2, only_when_visible = true},
    {type = "create-particle", particle_name = "spark-particle-debris", repeat_count = 50,
     initial_height = 0.6, initial_vertical_speed = 0.25, initial_vertical_speed_deviation = 0.15,
     speed_from_center = 0.5, speed_from_center_deviation = 0.3, offset_deviation = {{-0.5, -0.5}, {0.5, 0.5}},
     tail_length = 12, tail_length_deviation = 6, tail_width = 2, only_when_visible = true},
    {type = "camera-effect", duration = 20, ease_in_duration = 1, ease_out_duration = 30, delay = 0,
     strength = 3, full_strength_max_distance = 30, max_distance = 150},
    {type = "play-sound", sound = sounds.large_explosion(1.0), play_on_target_position = true, max_distance = 300},
    -- Whatever is hit takes the whole impact.
    area_damage(1.5, {{amount = 25000, type = "physical"}}),
    area_damage(slug_radius, {{amount = 1500, type = "physical"}, {amount = 500, type = "explosion"}}),
    wave(p_dust.name, 40, 3, 0.6),
}

data:extend({slug_flash, slug_rod})

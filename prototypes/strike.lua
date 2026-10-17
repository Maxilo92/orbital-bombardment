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

-- A tighter, shorter-lived dust puff than the atomic bomb's: the ring should
-- mark the blast radius, not roll on far past it.
local dust = table.deepcopy(data.raw["explosion"]["cluster-nuke-explosion"])
dust.name = "orbital-impact-dust"
scale_all(dust.animations, 0.75)
dust.scale_increment_per_tick = 0.001
dust.fade_out_duration = 20
-- The blast wave leaves ground zero fast and brakes hard (negative
-- acceleration), so it reads as an explosive punch rather than a slow bloom.
--
-- Every fragment is created standing still where its projectile lands, and the
-- projectiles fly out to the blast radius: the ring still sweeps outwards,
-- because near targets are reached first, but it stops dead at the radius.
-- The atomic bomb's own fragments use create-explosion instead, which keeps
-- the projectile's speed - measured, they rolled on 30 tiles out (three times
-- the blast radius) whatever max_movement_distance said.
local function braking(projectile, acceleration)
    projectile.acceleration = acceleration
    return projectile
end
local p_dust = braking(wave_projectile("orbital-wave-dust", "atomic-bomb-wave-spawns-cluster-nuke-explosion",
    {type = "create-entity", entity_name = dust.name}), -0.035)
local p_fire = braking(wave_projectile("orbital-wave-fire", "atomic-bomb-wave-spawns-fire-smoke-explosion",
    {type = "create-entity", entity_name = "atomic-fire-smoke"}), -0.035)
local p_shock = braking(wave_projectile("orbital-wave-shockwave", "atomic-bomb-wave-spawns-nuke-shockwave-explosion",
    {type = "create-entity", entity_name = "atomic-nuke-shockwave"}), -0.04)

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

-- A smaller streak for the cluster rod's bomblets. The shift scales with it so
-- the head still lands on ground zero.
local SMALL = 0.55
local streak_small = table.deepcopy(streak)
streak_small.name = "orbital-reentry-streak-small"
streak_small.animations[1].scale = SMALL
streak_small.animations[1].shift = {0, -(1024 / 2 - 30) / 32 * SMALL}
streak_small.light = {intensity = 0.8, size = 14, color = {r = 1, g = 0.7, b = 0.45}}
local streak_small_chart = table.deepcopy(streak_chart)
streak_small_chart.name = "orbital-reentry-streak-small-chart"
streak_small_chart.scale = SMALL
streak_small_chart.shift = streak_small.animations[1].shift

data:extend({streak, streak_chart, streak_small, streak_small_chart})

--------------------------------------------------------------------------------
-- the penetrator
--------------------------------------------------------------------------------

local radius = shared.AMMO["tungsten-penetrator"].radius

-- Every round leaves its own mark, so the aftermath tells which one hit:
-- a crater of nuclear ground, then a scorchmark on top, then crater
-- decoratives. The order matters: scorchmarks are removed when a tile is
-- placed under them, so a crater set after the scorchmark erased it (which is
-- why 0.6 and earlier left hardly a trace).
local function crater(tile_radius, scorchmark, decorative)
    local effects = {
        {type = "set-tile", tile_name = "nuclear-ground", radius = tile_radius, apply_projection = true,
         tile_collision_mask = {layers = {water_tile = true}}},
        {type = "create-entity", entity_name = scorchmark, offsets = {{0, -0.5}}},
    }
    if decorative then
        effects[#effects + 1] = {type = "create-decorative", decorative = decorative,
            spawn_min = 1, spawn_max = 1, spawn_min_radius = 0, spawn_max_radius = 0.5, apply_projection = true}
    end
    return effects
end

local function with(list, extra)
    for _, effect in ipairs(extra) do list[#list + 1] = effect end
    return list
end

-- The damage of a round, from its zones in shared.AMMO - the same numbers the
-- strike planner in control.lua reckons with.
local function zone_effects(ammo, key)
    local effects = {}
    for _, zone in ipairs(shared.AMMO[ammo][key or "zones"]) do
        local damages = {}
        for type, amount in pairs(zone.damage) do damages[#damages + 1] = {amount = amount, type = type} end
        table.sort(damages, function(x, y) return x.type < y.type end)
        effects[#effects + 1] = area_damage(zone.radius, damages)
    end
    return effects
end

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
                {type = "set-tile", tile_name = "nuclear-ground", radius = 5, apply_projection = true,
                 tile_collision_mask = {layers = {water_tile = true}}},
                {type = "create-entity", entity_name = "huge-scorchmark", offsets = {{0, -0.5}}},
                {type = "create-decorative", decorative = "crater-large", spawn_min = 1, spawn_max = 1,
                 spawn_min_radius = 0, spawn_max_radius = 0.5, apply_projection = true},
                {type = "create-decorative", decorative = "nuclear-ground-patch", spawn_min = 18, spawn_max = 26,
                 spawn_min_radius = 5.5, spawn_max_radius = 8, apply_projection = true, spread_evenly = true},
                {type = "create-decorative", decorative = "crater-small", spawn_min = 4, spawn_max = 7,
                 spawn_min_radius = 3, spawn_max_radius = 7, apply_projection = true},
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
                wave(p_dust.name, 170, radius, 0.9),
                wave(p_fire.name, 80, 5, 0.8),
                wave(p_shock.name, 200, radius * 0.9, 1.0),
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

-- Ground zero: nothing survives a direct hit; the blast around it is still
-- enough for a fully evolved nest (3500 HP, 15% physical resistance).
with(rod.action.action_delivery.target_effects, zone_effects("tungsten-penetrator"))

data:extend({rod})

--------------------------------------------------------------------------------
-- the slug
--------------------------------------------------------------------------------


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
slug_rod.action.action_delivery.target_effects = with(crater(1.5, "medium-scorchmark", "crater-small"), {
    {type = "create-entity", entity_name = slug_flash.name},
    {type = "destroy-decoratives", radius = shared.AMMO["tungsten-slug"].radius, include_soft_decoratives = true,
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
    wave(p_dust.name, 40, 3, 0.6),
})

with(slug_rod.action.action_delivery.target_effects, zone_effects("tungsten-slug"))

data:extend({slug_flash, slug_rod})

--------------------------------------------------------------------------------
-- the cluster rod's bomblets
--------------------------------------------------------------------------------

-- Each bomblet is a small penetrator: enough to destroy a fully evolved nest it
-- lands next to (3500 HP), with a short ripple of fire and a burst of
-- splinters. Twelve of them over a 12 tile circle.
local bomblet = table.deepcopy(rod)
bomblet.name = "orbital-cluster-bomblet"
bomblet.light = {intensity = 0.8, size = 10, color = {r = 1, g = 0.8, b = 0.6}}
bomblet.action.action_delivery.target_effects = with(crater(1.2, "medium-scorchmark", "crater-small"), {
    {type = "create-entity", entity_name = burst.name},
    {type = "create-entity", entity_name = burst.name, repeat_count = 2, offset_deviation = {{-1.5, -1.5}, {1.5, 1.5}}},
    {type = "destroy-decoratives", radius = 3, include_soft_decoratives = true,
     include_decals = true, invoke_decorative_trigger = true, decoratives_with_trigger_only = false},
    {type = "create-particle", particle_name = "stone-particle-medium", repeat_count = 25,
     initial_height = 0.4, initial_vertical_speed = 0.2, initial_vertical_speed_deviation = 0.1,
     speed_from_center = 0.35, speed_from_center_deviation = 0.2, offset_deviation = {{-0.5, -0.5}, {0.5, 0.5}},
     tail_length = 8, tail_length_deviation = 4, tail_width = 2, only_when_visible = true},
    {type = "create-particle", particle_name = "spark-particle-debris", repeat_count = 15,
     initial_height = 0.6, initial_vertical_speed = 0.22, initial_vertical_speed_deviation = 0.12,
     speed_from_center = 0.45, speed_from_center_deviation = 0.25, offset_deviation = {{-0.5, -0.5}, {0.5, 0.5}},
     tail_length = 10, tail_length_deviation = 5, tail_width = 2, only_when_visible = true},
    {type = "camera-effect", duration = 15, ease_in_duration = 1, ease_out_duration = 20, delay = 0,
     strength = 1.2, full_strength_max_distance = 40, max_distance = 200},
    {type = "play-sound", sound = sounds.large_explosion(0.8), play_on_target_position = true, max_distance = 300},
    wave(p_dust.name, 25, 3, 0.6),
})

with(bomblet.action.action_delivery.target_effects, zone_effects("orbital-cluster-rod"))

data:extend({bomblet})

--------------------------------------------------------------------------------
-- the EMP rod
--------------------------------------------------------------------------------

-- The rod's own impact is only the visible part of the EMP: a blue-white
-- flash and a burst of electric sparks. Stun, shutdown, the discharge arcs and
-- the lightning are applied by control.lua on the same tick. (A blue-tinted
-- shockwave ring was tried and came out as a murky teal dust dome.)
local EMP_BLUE = {r = 0.45, g = 0.75, b = 1}

local function tint_all(anim, tint)
    if type(anim) ~= "table" then return end
    if anim.layers then
        for _, layer in pairs(anim.layers) do tint_all(layer, tint) end
    elseif anim.filename or anim.filenames or anim.stripes then
        anim.tint = tint
    else
        for _, child in pairs(anim) do tint_all(child, tint) end
    end
end

local emp_flash = table.deepcopy(data.raw["explosion"]["big-explosion"])
emp_flash.name = "orbital-emp-flash"
tint_all(emp_flash.animations, EMP_BLUE)
scale_all(emp_flash.animations, 1.5)
emp_flash.light = {intensity = 1, size = 40, color = {r = 0.5, g = 0.8, b = 1}}
emp_flash.light_intensity_factor_final = 0
emp_flash.light_size_factor_final = 0.6

-- The stun: the vanilla slowdown sticker's swirl, turned electric blue.
local stun = {
    type = "sticker",
    name = "orbital-emp-stun",
    flags = {"not-on-map"},
    hidden = true,
    duration_in_ticks = shared.EMP_STUN_TICKS,
    target_movement_modifier = 0.02,
    vehicle_speed_modifier = 0.1,
    animation = {
        filename = "__base__/graphics/entity/slowdown-sticker/slowdown-sticker.png",
        line_length = 5,
        width = 42,
        height = 48,
        frame_count = 50,
        animation_speed = 1,
        tint = {r = 0.35, g = 0.65, b = 1, a = 0.8},
        shift = {0, -0.3},
        draw_as_glow = true,
    },
}

local emp_rod = table.deepcopy(rod)
emp_rod.name = "orbital-emp-strike"
emp_rod.light = {intensity = 1, size = 16, color = {r = 0.6, g = 0.85, b = 1}}
emp_rod.action.action_delivery.target_effects = {
    {type = "create-entity", entity_name = emp_flash.name},
    {type = "create-entity", entity_name = "small-scorchmark", offsets = {{0, -0.5}}},
    {type = "create-particle", particle_name = "spark-particle-debris", repeat_count = 120,
     initial_height = 0.6, initial_vertical_speed = 0.2, initial_vertical_speed_deviation = 0.15,
     speed_from_center = 0.5, speed_from_center_deviation = 0.35, offset_deviation = {{-1, -1}, {1, 1}},
     tail_length = 12, tail_length_deviation = 6, tail_width = 2, tint = {r = 0.6, g = 0.85, b = 1},
     only_when_visible = true},
    {type = "camera-effect", duration = 20, ease_in_duration = 1, ease_out_duration = 30, delay = 0,
     strength = 3, full_strength_max_distance = 40, max_distance = 200},
    {type = "play-sound", sound = {variations = {
        {filename = "__space-age__/sound/explosions/lightning-effect-1.ogg", volume = 0.9},
        {filename = "__space-age__/sound/explosions/lightning-effect-3.ogg", volume = 0.9},
        {filename = "__space-age__/sound/explosions/lightning-effect-5.ogg", volume = 0.9},
     }}, play_on_target_position = true, max_distance = 400},
    {type = "play-sound", sound = sounds.large_explosion(0.6), play_on_target_position = true, max_distance = 300},
}

-- The rod itself still hits whatever it lands on.
with(emp_rod.action.action_delivery.target_effects, zone_effects("orbital-emp-rod"))

-- The arcs from ground zero to the victims. Space Age's tesla beams carry the
-- tesla gun's damage and chain on from target to target - measured, they killed
-- units 25 tiles outside the EMP. This copy only draws: no damage, no chain.
local arc = table.deepcopy(data.raw["beam"]["chain-tesla-gun-beam-bounce"])
arc.name = "orbital-emp-arc"
arc.action = nil

-- The chain lightning, the Space Age tesla mechanic itself: from each victim
-- the arc jumps on to the next enemy, forks now and then, and stuns whatever
-- it touches. Own copies so range, jumps and damage suit the EMP - the tesla
-- gun's chain wandered far outside the circle.
local chain_beam = table.deepcopy(data.raw["beam"]["chain-tesla-gun-beam-bounce"])
chain_beam.name = "orbital-emp-chain-beam"
chain_beam.action = {
    type = "direct",
    action_delivery = {
        type = "instant",
        target_effects = {
            {type = "damage", damage = {amount = shared.EMP_CHAIN_DAMAGE, type = "electric"}},
            {type = "push-back", distance = 0.25},
            -- the tesla turret's own stun and slow, plus the EMP's longer stun
            {type = "create-sticker", sticker = "tesla-turret-stun"},
            {type = "create-sticker", sticker = "tesla-turret-slow"},
            {type = "create-sticker", sticker = stun.name},
        },
    },
}
local chain = {
    type = "chain-active-trigger",
    name = "orbital-emp-chain",
    max_jumps = shared.EMP_CHAIN_JUMPS,
    max_range_per_jump = shared.EMP_CHAIN_RANGE,
    jump_delay_ticks = 6,
    fork_chance = 0.25,
    action = {
        type = "direct",
        action_delivery = {
            type = "beam",
            beam = chain_beam.name,
            max_length = shared.EMP_CHAIN_RANGE + 0.5,
            duration = 30,
            add_to_shooter = false,
            destroy_with_source_or_target = false,
            source_offset = {0, 0},
        },
    },
}
-- control.lua starts a chain by sending this invisible carrier from ground
-- zero to a victim; when it arrives, the chain begins there.
local chain_starter = {
    type = "projectile",
    name = "orbital-emp-chain-starter",
    flags = {"not-on-map"},
    hidden = true,
    acceleration = 0,
    max_speed = 50,
    action = {
        type = "direct",
        action_delivery = {
            type = "instant",
            target_effects = {
                {type = "nested-result", action = {type = "direct", action_delivery = {type = "chain", chain = chain.name}}},
            },
        },
    },
}

data:extend({emp_flash, stun, emp_rod, arc, chain_beam, chain, chain_starter})

--------------------------------------------------------------------------------
-- the incendiary rod
--------------------------------------------------------------------------------

-- Napalm: the flamethrower's own ground fire, hotter and burning for a fixed
-- time. The vanilla flame's 13/60 damage per tick is nothing against a nest:
-- nests take 3 less per hit and resist 60% of fire, worms 70%, so measured it
-- left a nest at 91% after 20 seconds. 8 per tick burns a nest down when two
-- flames reach it. Flames are not refuelled by further streams, so they go out
-- after NAPALM_BURN_TICKS instead of burning on for most of a minute.
local napalm_flame = table.deepcopy(data.raw["fire"]["fire-flame"])
napalm_flame.name = "orbital-napalm-flame"
napalm_flame.damage_per_tick = {amount = shared.NAPALM_DAMAGE_PER_TICK, type = "fire"}
napalm_flame.maximum_damage_multiplier = 1
napalm_flame.damage_multiplier_increase_per_added_fuel = 0
napalm_flame.initial_lifetime = shared.NAPALM_BURN_TICKS
napalm_flame.lifetime_increase_by = 0
napalm_flame.maximum_lifetime = shared.NAPALM_BURN_TICKS
napalm_flame.maximum_spread_count = 30
-- Its mark: charred ground, darker and lasting far longer than a flamethrower's.
napalm_flame.burnt_patch_lifetime = 5 * 60 * 60
napalm_flame.burnt_patch_alpha_default = 0.85

-- The flamethrower's stream, flying faster and setting napalm instead of its
-- ordinary fire where it lands. control.lua sprays these out from ground zero.
local napalm_stream = table.deepcopy(data.raw["stream"]["flamethrower-fire-stream"])
napalm_stream.name = "orbital-napalm-stream"
napalm_stream.particle_horizontal_speed = 0.55
napalm_stream.particle_horizontal_speed_deviation = 0.05
for _, action in pairs(napalm_stream.action) do
    local effects = action.action_delivery.target_effects
    for _, effect in pairs(effects) do
        if effect.type == "create-fire" then effect.entity_name = napalm_flame.name end
    end
    if action.type == "direct" then
        -- Every splash chars the ground: together a blackened disc, the
        -- incendiary rod's mark (the flames' own burnt patches are too faint).
        effects[#effects + 1] = {type = "create-entity", entity_name = "medium-scorchmark", offsets = {{0, -0.5}}}
    end
end

local incendiary_rod = table.deepcopy(rod)
incendiary_rod.name = "orbital-incendiary-strike"
incendiary_rod.light = {intensity = 1, size = 18, color = {r = 1, g = 0.6, b = 0.3}}
incendiary_rod.action.action_delivery.target_effects = {
    {type = "create-entity", entity_name = flash.name},
    {type = "create-entity", entity_name = burst.name, repeat_count = 5, offset_deviation = {{-2.5, -2.5}, {2.5, 2.5}}},
    {type = "create-entity", entity_name = "medium-scorchmark", offsets = {{0, -0.5}}},
    {type = "nested-result", action = {
        type = "area", target_entities = false, trigger_from_target = true,
        repeat_count = 6, radius = shared.AMMO["orbital-incendiary-rod"].radius * 0.8, show_in_tooltip = false,
        action_delivery = {type = "instant", target_effects = {
            {type = "create-entity", entity_name = "nuclear-smouldering-smoke-source",
             tile_collision_mask = {layers = {water_tile = true}}},
        }},
    }},
    {type = "create-particle", particle_name = "spark-particle-debris", repeat_count = 60,
     initial_height = 0.6, initial_vertical_speed = 0.25, initial_vertical_speed_deviation = 0.15,
     speed_from_center = 0.45, speed_from_center_deviation = 0.3, offset_deviation = {{-1, -1}, {1, 1}},
     tail_length = 12, tail_length_deviation = 6, tail_width = 2, tint = {r = 1, g = 0.6, b = 0.25},
     only_when_visible = true},
    {type = "camera-effect", duration = 25, ease_in_duration = 1, ease_out_duration = 35, delay = 0,
     strength = 4, full_strength_max_distance = 50, max_distance = 220},
    {type = "play-sound", sound = sounds.large_explosion(1.0), play_on_target_position = true, max_distance = 300},
    wave(p_fire.name, 60, 4, 0.8),
}

-- The burst itself, before the fire takes over.
with(incendiary_rod.action.action_delivery.target_effects, zone_effects("orbital-incendiary-rod"))

data:extend({napalm_flame, napalm_stream, incendiary_rod})

--------------------------------------------------------------------------------
-- the guided rod
--------------------------------------------------------------------------------

-- A slug with a seeker: everything goes into what it locked on to, with a
-- little more blast than the plain slug so a target that dodged at the last
-- moment still gets hurt. Its mark is a crater between slug and penetrator.
local guided_rod = table.deepcopy(rod)
guided_rod.name = "orbital-guided-strike"
guided_rod.light = {intensity = 1, size = 14, color = {r = 0.8, g = 1, b = 0.7}}
guided_rod.action.action_delivery.target_effects = with(crater(2.5, "big-scorchmark", "crater-small"), {
    {type = "create-entity", entity_name = slug_flash.name},
    {type = "create-entity", entity_name = burst.name, repeat_count = 2, offset_deviation = {{-1, -1}, {1, 1}}},
    {type = "invoke-tile-trigger", repeat_count = 1},
    {type = "create-particle", particle_name = "stone-particle-big", repeat_count = 25,
     initial_height = 0.5, initial_vertical_speed = 0.28, initial_vertical_speed_deviation = 0.12,
     speed_from_center = 0.3, speed_from_center_deviation = 0.15, offset_deviation = {{-0.5, -0.5}, {0.5, 0.5}},
     tail_length = 6, tail_length_deviation = 4, tail_width = 3, only_when_visible = true},
    {type = "create-particle", particle_name = "spark-particle-debris", repeat_count = 50,
     initial_height = 0.6, initial_vertical_speed = 0.25, initial_vertical_speed_deviation = 0.15,
     speed_from_center = 0.5, speed_from_center_deviation = 0.3, offset_deviation = {{-0.5, -0.5}, {0.5, 0.5}},
     tail_length = 12, tail_length_deviation = 6, tail_width = 2, only_when_visible = true},
    {type = "camera-effect", duration = 20, ease_in_duration = 1, ease_out_duration = 30, delay = 0,
     strength = 3.5, full_strength_max_distance = 40, max_distance = 180},
    {type = "play-sound", sound = sounds.large_explosion(1.0), play_on_target_position = true, max_distance = 300},
    wave(p_dust.name, 50, 4, 0.7),
})

with(guided_rod.action.action_delivery.target_effects, zone_effects("orbital-guided-rod"))

data:extend({guided_rod})

--------------------------------------------------------------------------------
-- the steel rod
--------------------------------------------------------------------------------

-- A small kinetic hit: enough for units and worms, two of them for a fully
-- evolved nest. Its mark is a small crater.
local steel_rod = table.deepcopy(rod)
steel_rod.name = "orbital-steel-strike"
steel_rod.light = {intensity = 0.8, size = 12, color = {r = 1, g = 0.85, b = 0.7}}
steel_rod.action.action_delivery.target_effects = with(crater(1.8, "medium-scorchmark", "crater-small"), {
    {type = "create-entity", entity_name = slug_flash.name},
    {type = "create-entity", entity_name = burst.name},
    {type = "invoke-tile-trigger", repeat_count = 1},
    {type = "create-particle", particle_name = "stone-particle-medium", repeat_count = 40,
     initial_height = 0.4, initial_vertical_speed = 0.2, initial_vertical_speed_deviation = 0.1,
     speed_from_center = 0.35, speed_from_center_deviation = 0.2, offset_deviation = {{-0.5, -0.5}, {0.5, 0.5}},
     tail_length = 8, tail_length_deviation = 4, tail_width = 2, only_when_visible = true},
    {type = "create-particle", particle_name = "spark-particle-debris", repeat_count = 25,
     initial_height = 0.6, initial_vertical_speed = 0.22, initial_vertical_speed_deviation = 0.12,
     speed_from_center = 0.45, speed_from_center_deviation = 0.25, offset_deviation = {{-0.5, -0.5}, {0.5, 0.5}},
     tail_length = 10, tail_length_deviation = 5, tail_width = 2, only_when_visible = true},
    {type = "camera-effect", duration = 15, ease_in_duration = 1, ease_out_duration = 20, delay = 0,
     strength = 2, full_strength_max_distance = 30, max_distance = 150},
    {type = "play-sound", sound = sounds.large_explosion(0.8), play_on_target_position = true, max_distance = 300},
    wave(p_dust.name, 40, 4, 0.7),
})

with(steel_rod.action.action_delivery.target_effects, zone_effects("orbital-steel-rod"))

data:extend({steel_rod})

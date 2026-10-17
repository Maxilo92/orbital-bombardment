local shared = require("shared")

local CANNON = shared.CANNON
local DESIGNATOR = shared.DESIGNATOR
local UPDATE_INTERVAL = 10
local REENTRY_SOUND_TICKS = 75 -- the roar is 1.25 s long and ends on the impact
local GUI_NAME = "orbital_cannon_status"
local SELECTOR_NAME = "orbital_ammo_selector"

-- Render colours are premultiplied (rgb already scaled by alpha).
local LINE_QUEUED = {r = 0.85, g = 0.65, b = 0.1, a = 0.85}
local LINE_INBOUND = {r = 0.9, g = 0.12, b = 0.05, a = 0.9}
local FILL_INBOUND = {r = 0.1, g = 0.012, b = 0.008, a = 0.1}
local TEXT_QUEUED = {r = 1, g = 0.82, b = 0.3}
local TEXT_INBOUND = {r = 1, g = 0.35, b = 0.25}

--------------------------------------------------------------------------------
-- storage
--------------------------------------------------------------------------------

-- storage.cannons    [unit_number] = {entity = LuaEntity, ready_tick = uint}
-- storage.targets    array, oldest first, of
--                    {force_index, surface_index, planet, position, ammo, state = "queued" | "inbound",
--                     reason, radius, impact_tick, sound_played, fall_spawned, flashed,
--                     objects = {LuaRenderObject}, label = LuaRenderObject, label_key,
--                     guided rounds also: entity (followed until locked), locked,
--                     seen_position, seen_tick (for the lead)}
-- storage.guis       [player_index] = unit_number of the cannon whose window is open
-- storage.selected   [player_index] = ammo the player's designator marks targets for
-- storage.selectors  [player_index] = true while the ammo bar is shown
-- storage.rng        LuaRandomGenerator for where cluster bomblets land
-- storage.scheduled  array of things to do on a given tick, {tick, kind, ...}:
--                    "fall" (a bomblet), "emp", "napalm", "bonus" (research
--                    damage on an impact) and "enable" (an entity the EMP
--                    switched off)
-- storage.threats    [force_index][surface_index] = array of {position, from, tick}:
--                    recent enemy attacks on the force's buildings (defence mode)
-- storage.defending  [force_index] = true while one of its cannons defends
-- storage.nests      [surface_index] = {tick, list}: enemy spawners, refreshed
--                    every minute (clearing mode)
-- storage.ignore_chart  tests only: the headless benchmark never charts
--
-- Each cannon also carries `auto` = {mode = "off" | "defend" | "clear", ammo,
-- reserve, status}: its fire-control settings.
local function init_storage()
    storage.cannons = storage.cannons or {}
    storage.targets = storage.targets or {}
    storage.guis = storage.guis or {}
    storage.selected = storage.selected or {}
    storage.selectors = storage.selectors or {}
    storage.rng = storage.rng or game.create_random_generator()
    storage.scheduled = storage.scheduled or {}
    storage.threats = storage.threats or {}
    storage.defending = storage.defending or {}
    storage.nests = storage.nests or {}
    for _, cannon in pairs(storage.cannons) do
        cannon.auto = cannon.auto or {mode = "off", ammo = shared.AUTO_DEFAULT_AMMO, reserve = 2}
    end
    -- Targets from 0.3 and earlier knew only one round.
    for _, target in pairs(storage.targets) do
        target.ammo = target.ammo or "tungsten-penetrator"
    end
end

local function register(entity)
    if entity and entity.valid and entity.name == CANNON and not storage.cannons[entity.unit_number] then
        storage.cannons[entity.unit_number] = {
            entity = entity,
            ready_tick = 0,
            auto = {mode = "off", ammo = shared.AUTO_DEFAULT_AMMO, reserve = 2},
        }
    end
end

local function rescan_cannons()
    for id, cannon in pairs(storage.cannons) do
        if not cannon.entity.valid then storage.cannons[id] = nil end
    end
    for _, surface in pairs(game.surfaces) do
        for _, entity in pairs(surface.find_entities_filtered{name = CANNON}) do
            register(entity)
        end
    end
end

--------------------------------------------------------------------------------
-- cannons
--------------------------------------------------------------------------------

-- Name of the space location the cannon's platform is parked at, or nil while
-- it is travelling (or the cannon somehow stands on a planet).
local function orbit_of(entity)
    local platform = entity.surface.platform
    local location = platform and platform.space_location
    return location and location.name
end

local function ammo_inventory(entity)
    return entity.get_inventory(defines.inventory.artillery_turret_ammo)
end

-- The first stack of `ammo` in the cannon, or nil.
local function ammo_stack(entity, ammo)
    local inventory = ammo_inventory(entity)
    if not inventory then return nil end
    for i = 1, #inventory do
        local stack = inventory[i]
        if stack.valid_for_read and stack.name == ammo then return stack end
    end
    return nil
end

-- A cannon of `force` parked over `planet` that can fire `ammo` right now, or
-- nil and the reason none can: "no-cannon", "no-ammo" or "reloading". A target
-- the fire control picked for one cannon is only fired by that cannon.
local function pick_cannon(force_index, planet, ammo, tick, target)
    local reason = "no-cannon"
    local only = target and target.cannon_id
    for id, cannon in pairs(storage.cannons) do
        local entity = cannon.entity
        if not entity.valid then
            storage.cannons[id] = nil
        elseif entity.force.index == force_index and orbit_of(entity) == planet and (not only or only == id) then
            if not ammo_stack(entity, ammo) then
                if reason == "no-cannon" then reason = "no-ammo" end
            elseif cannon.ready_tick > tick then
                reason = "reloading"
            else
                return cannon
            end
        end
    end
    return nil, reason
end

local function has_cannon_over(force_index, planet)
    for _, cannon in pairs(storage.cannons) do
        local entity = cannon.entity
        if entity.valid and entity.force.index == force_index and orbit_of(entity) == planet then
            return true
        end
    end
    return false
end

-- Rounds of each ammo loaded in the force's cannons over `planet`.
local function rounds_over(force_index, planet)
    local counts = {}
    for _, cannon in pairs(storage.cannons) do
        local entity = cannon.entity
        if entity.valid and entity.force.index == force_index and orbit_of(entity) == planet then
            for name, count in pairs(shared.count_ammo(ammo_inventory(entity))) do
                counts[name] = (counts[name] or 0) + count
            end
        end
    end
    return counts
end

-- Levels of an infinite research that are done.
local function levels(force, name)
    local tech = force.technologies[name]
    if not tech then return 0 end
    return tech.researched and tech.level or tech.level - 1
end

local function damage_bonus(force)
    return levels(force, shared.DAMAGE_TECH) * shared.DAMAGE_PER_LEVEL
end

local function reload_ticks(force, ammo)
    return math.ceil(shared.AMMO[ammo].reload / (1 + levels(force, shared.RELOAD_TECH) * shared.RELOAD_PER_LEVEL))
end

local STRIKE_AMMO = {} -- strike prototype -> its ammo
for ammo, data in pairs(shared.AMMO) do STRIKE_AMMO[data.strike] = ammo end

local function is_unlocked(force, ammo)
    local recipe = force.recipes[ammo]
    return recipe ~= nil and recipe.enabled
end

--------------------------------------------------------------------------------
-- target markers
--------------------------------------------------------------------------------

local function destroy_markers(target)
    for _, object in pairs(target.objects) do
        if object.valid then object.destroy() end
    end
    target.objects = {}
    target.label = nil
    target.label_key = nil
end

-- Where a marker is drawn: on the followed enemy while a guided round is
-- still tracking it (render objects then move with it on their own), on the
-- fixed target position otherwise.
local function tracking(target)
    return target.entity and target.entity.valid and not target.locked
end

local function anchor(target, dy)
    if tracking(target) then
        return {entity = target.entity, offset = {0, dy or 0}}
    end
    return {x = target.position.x, y = target.position.y + (dy or 0)}
end

local function update_label(target, tick)
    local label = target.label
    if not (label and label.valid) then return end
    local text, key
    if target.state == "inbound" then
        local seconds = math.max(0, math.ceil((target.impact_tick - tick) / 60))
        if target.entity then
            local mode = tracking(target) and "tracking" or "locked"
            key = mode .. seconds
            text = {"orbital-bombardment.marker-" .. mode, seconds}
        else
            key = "in" .. seconds
            text = {"orbital-bombardment.marker-inbound", seconds}
        end
    else
        key = "q" .. target.reason
        text = {"orbital-bombardment.marker-queued",
            {"orbital-bombardment.reason-" .. target.reason, "[item=" .. target.ammo .. "]"}}
    end
    if target.auto then
        key = "auto" .. key
        text = {"orbital-bombardment.marker-auto", {"orbital-bombardment.auto-mode-" .. target.auto.mode}, text}
    end
    if key ~= target.label_key then
        label.text = text
        target.label_key = key
    end
end

-- Only the marking force sees its markers. Circles are drawn both in the world
-- and on the map, so they stay visible when remote view zooms out to the chart.
local function draw_markers(target, tick)
    destroy_markers(target)
    local surface = game.surfaces[target.surface_index]
    if not surface then return end
    local inbound = target.state == "inbound"
    local forces = {target.force_index}
    local objects = target.objects

    for _, mode in pairs({"game", "chart"}) do
        objects[#objects + 1] = rendering.draw_circle{
            color = inbound and LINE_INBOUND or LINE_QUEUED,
            radius = target.radius,
            width = inbound and 5 or 3,
            filled = false,
            target = anchor(target),
            surface = surface,
            forces = forces,
            render_mode = mode,
            draw_on_ground = true,
        }
    end
    if inbound then
        objects[#objects + 1] = rendering.draw_circle{
            color = FILL_INBOUND,
            radius = target.radius,
            filled = true,
            target = anchor(target),
            surface = surface,
            forces = forces,
            draw_on_ground = true,
        }
        -- A blinking bullseye at ground zero.
        objects[#objects + 1] = rendering.draw_circle{
            color = LINE_INBOUND,
            radius = 1.2,
            filled = true,
            target = anchor(target),
            surface = surface,
            forces = forces,
            draw_on_ground = true,
            blink_interval = 20,
        }
        objects[#objects + 1] = rendering.draw_circle{
            color = LINE_INBOUND,
            radius = target.radius * 0.5,
            width = 3,
            filled = false,
            target = anchor(target),
            surface = surface,
            forces = forces,
            draw_on_ground = true,
        }
    end
    -- The round's icon in front of the label, so mixed targets stay apart.
    target.label = rendering.draw_text{
        text = "",
        surface = surface,
        target = anchor(target, -target.radius - 1),
        color = inbound and TEXT_INBOUND or TEXT_QUEUED,
        scale = 3,
        alignment = "center",
        vertical_alignment = "bottom",
        forces = forces,
        use_rich_text = true,
    }
    objects[#objects + 1] = target.label
    objects[#objects + 1] = rendering.draw_sprite{
        sprite = "item/" .. target.ammo,
        target = anchor(target, -target.radius - 3.2),
        surface = surface,
        forces = forces,
        x_scale = 1.5,
        y_scale = 1.5,
    }
    update_label(target, tick)
end

--------------------------------------------------------------------------------
-- firing
--------------------------------------------------------------------------------

local function fire(cannon, target, tick)
    local entity = cannon.entity
    local ammo = shared.AMMO[target.ammo]
    local stack = ammo_stack(entity, target.ammo)
    if stack.count > 1 then
        stack.count = stack.count - 1
    else
        stack.clear()
    end
    cannon.ready_tick = tick + reload_ticks(entity.force, target.ammo)

    local surface = entity.surface
    -- The vanilla flash is an oriented explosion and needs a direction: the
    -- barrel points out into space, straight up the screen.
    local x, y = entity.position.x, entity.position.y
    surface.create_entity{name = "orbital-cannon-muzzle-flash", position = {x, y - 1.5}, target = {x, y - 10}}
    surface.play_sound{path = "orbital-cannon-fire", position = entity.position}

    target.state = "inbound"
    -- Impact lands on the processing grid, so the fall starts exactly
    -- FALL_TICKS before it and the map flash goes off on the impact tick.
    target.impact_tick = math.ceil((tick + ammo.flight) / UPDATE_INTERVAL) * UPDATE_INTERVAL
    draw_markers(target, tick)
end

-- A falling body covers FALL_HEIGHT tiles in FALL_TICKS - far too fast to see
-- as an object. What is seen is the streak explosion, whose head reaches the
-- ground in the same ten ticks. Neither is drawn on the map, so the streak is
-- drawn there as well (render_mode "chart"), started on its first frame.
local STREAK_SPEED, STREAK_FRAMES = 0.4, 16 -- as in prototypes/strike.lua

local function schedule(tick, kind, data)
    data.tick = tick
    data.kind = kind
    storage.scheduled[#storage.scheduled + 1] = data
end

local function spawn_fall(surface, position, strike, force, tick, small)
    surface.create_entity{
        name = strike,
        position = {x = position.x, y = position.y - shared.FALL_HEIGHT},
        target = position,
        speed = shared.FALL_HEIGHT / shared.FALL_TICKS,
        force = force,
    }
    local bonus = force and damage_bonus(force) or 0
    if bonus > 0 then
        schedule(tick + shared.FALL_TICKS, "bonus", {
            surface_index = surface.index,
            position = position,
            ammo = STRIKE_AMMO[strike],
            force_index = force.index,
            bonus = bonus,
        })
    end
    local streak = small and "orbital-reentry-streak-small" or "orbital-reentry-streak"
    surface.create_entity{name = streak, position = position}
    rendering.draw_animation{
        animation = streak .. "-chart",
        target = position,
        surface = surface,
        render_mode = "chart",
        animation_speed = STREAK_SPEED,
        animation_offset = -(tick * STREAK_SPEED) % STREAK_FRAMES,
        time_to_live = math.floor(STREAK_FRAMES / STREAK_SPEED),
    }
end

-- A random point within `radius` of `center`. With `even` the points spread
-- evenly over the disc; without, they bunch towards the centre.
local function random_in_disc(center, radius, even)
    local rng = storage.rng
    local angle = rng() * 2 * math.pi
    local distance = (even and math.sqrt(rng()) or rng()) * radius
    return {x = center.x + math.cos(angle) * distance, y = center.y + math.sin(angle) * distance}
end

-- The cluster rod first splits into a few pods, and each pod scatters its
-- bomblets around its own point: clumps and gaps instead of an even sprinkle.
-- The bomblets come down one after another over about half a second.
local function spawn_cluster(target, surface, ammo, tick)
    local rng = storage.rng
    local pods = {}
    for i = 1, rng(3, 4) do
        pods[i] = random_in_disc(target.position, ammo.spread * 0.7, true)
    end
    local delay = 0
    local last = tick
    for _ = 1, rng(ammo.bomblets - 2, ammo.bomblets + 2) do
        local pod = pods[rng(1, #pods)]
        schedule(tick + delay, "fall", {
            surface_index = surface.index,
            position = random_in_disc(pod, ammo.spread * 0.35, false),
            strike = ammo.strike,
            force_index = target.force_index,
            small = true,
        })
        last = tick + delay
        delay = delay + rng(0, 4)
    end
    -- Keep the marker up until the last bomblet is down.
    target.done_tick = last + shared.FALL_TICKS
end

local function spawn_strike(target, surface, tick)
    local ammo = shared.AMMO[target.ammo]
    local force = game.forces[target.force_index]
    if ammo.bomblets then
        spawn_cluster(target, surface, ammo, tick)
    else
        spawn_fall(surface, target.position, ammo.strike, force, tick, false)
        local effect = ammo.emp and "emp" or ammo.napalm and "napalm"
        if effect then
            schedule(tick + shared.FALL_TICKS, effect, {
                surface_index = surface.index,
                position = target.position,
                force_index = target.force_index,
                radius = ammo.radius,
            })
        end
    end
    surface.play_sound{path = "orbital-sonic-boom", position = target.position}
    target.fall_spawned = true
end

--------------------------------------------------------------------------------
-- the EMP
--------------------------------------------------------------------------------

local EMP_TYPES = {"unit", "spider-unit", "segmented-unit", "unit-spawner", "turret"}
local EMP_STUNNABLE = {["unit"] = true, ["spider-unit"] = true}
local EMP_DISABLE = {["unit-spawner"] = true, ["turret"] = true}

-- Everything hostile in the circle takes electric damage. Units are stunned by
-- a sticker; worms and nests cannot carry one, so they are switched off for a
-- while instead (disabled_by_script, which exists in 2.0 and 2.1 alike).
-- Arcs crackle out from ground zero, and chain lightning - the Space Age tesla
-- mechanic - starts on a few victims and jumps on from enemy to enemy.
local function emp(event, tick)
    local surface = game.surfaces[event.surface_index]
    local force = game.forces[event.force_index]
    if not (surface and force) then return end
    local center, radius = event.position, event.radius

    local victims = {}
    for _, entity in pairs(surface.find_entities_filtered{position = center, radius = radius, type = EMP_TYPES}) do
        if entity.valid and force.is_enemy(entity.force) then
            victims[#victims + 1] = entity
        end
    end

    for i = #victims, 2, -1 do -- shuffle, so the chains start on random victims
        local j = storage.rng(1, i)
        victims[i], victims[j] = victims[j], victims[i]
    end
    for index, entity in ipairs(victims) do
        if entity.valid and index <= shared.EMP_CHAINS then
            -- An arc to the victim, and from there the chain lightning jumps on.
            surface.create_entity{
                name = "orbital-emp-arc",
                position = center,
                source_position = {center.x, center.y - 1},
                target = entity,
                duration = 30,
            }
            surface.create_entity{
                name = "orbital-emp-chain-starter",
                position = center,
                target = entity,
                speed = 2,
                force = force,
            }
        end
        if entity.valid and EMP_STUNNABLE[entity.type] then
            surface.create_entity{name = "orbital-emp-stun", position = entity.position, target = entity}
        elseif entity.valid and EMP_DISABLE[entity.type] and not entity.disabled_by_script then
            entity.disabled_by_script = true
            schedule(tick + shared.EMP_DISABLE_TICKS, "enable", {entity = entity})
        end
        if entity.valid then
            entity.damage(shared.EMP_DAMAGE * (1 + damage_bonus(force)), force, "electric")
        end
    end

    -- The discharge itself: arcs crackling out from ground zero in every
    -- direction, to the edge of the circle.
    for i = 1, shared.EMP_TENDRILS do
        local angle = (i + storage.rng()) / shared.EMP_TENDRILS * 2 * math.pi
        local reach = radius * (0.55 + 0.45 * storage.rng())
        surface.create_entity{
            name = "orbital-emp-arc",
            position = center,
            source_position = {center.x, center.y - 1},
            target_position = {center.x + math.cos(angle) * reach, center.y + math.sin(angle) * reach},
            duration = storage.rng(18, 34),
        }
    end

end

--------------------------------------------------------------------------------
-- the incendiary rod
--------------------------------------------------------------------------------

-- The rod bursts on impact and sprays burning streams - the flamethrower's own
-- stream, only aimed out from ground zero - to points all over the circle.
-- Where a stream lands it sets fire to the ground and to whatever stands
-- there, exactly as a flamethrower would. A core of flames burns at ground
-- zero itself.
local function napalm(event)
    local surface = game.surfaces[event.surface_index]
    local force = game.forces[event.force_index]
    if not (surface and force) then return end
    local center = event.position
    for _ = 1, shared.NAPALM_STREAMS do
        surface.create_entity{
            name = "orbital-napalm-stream",
            position = center,
            source_position = {center.x, center.y - 0.5},
            target_position = random_in_disc(center, event.radius, true),
            force = force,
        }
    end
    for _ = 1, 5 do
        surface.create_entity{
            name = "orbital-napalm-flame",
            position = random_in_disc(center, 2, true),
            force = force,
            initial_ground_flame_count = 4,
        }
    end
end

-- The research damage bonus: the round's own zones once more, scaled by the
-- bonus, on the same tick as the impact.
local function bonus_damage(event)
    local surface = game.surfaces[event.surface_index]
    local force = game.forces[event.force_index]
    local data = shared.AMMO[event.ammo]
    if not (surface and force and data) then return end
    for _, zone in ipairs(data.zones) do
        for _, entity in pairs(surface.find_entities_filtered{position = event.position, radius = zone.radius}) do
            if entity.valid and entity.is_entity_with_health and entity.destructible then
                for type, amount in pairs(zone.damage) do
                    if entity.valid then entity.damage(amount * event.bonus, force, type) end
                end
            end
        end
    end
end

local function run_scheduled(tick)
    local scheduled = storage.scheduled
    for i = #scheduled, 1, -1 do
        local event = scheduled[i]
        if event.tick <= tick then
            table.remove(scheduled, i)
            local surface = event.surface_index and game.surfaces[event.surface_index]
            if event.kind == "fall" and surface then
                spawn_fall(surface, event.position, event.strike, game.forces[event.force_index], tick, event.small)
            elseif event.kind == "emp" then
                emp(event, tick)
            elseif event.kind == "napalm" then
                napalm(event)
            elseif event.kind == "bonus" then
                bonus_damage(event)
            elseif event.kind == "enable" and event.entity.valid then
                event.entity.disabled_by_script = false
            end
        end
    end
end

-- The blast on the map: the strike circle flares up and fades.
local function flash_on_map(target, surface)
    for i, alpha in ipairs({0.9, 0.45, 0.2}) do
        rendering.draw_circle{
            color = {r = alpha, g = alpha * 0.55, b = alpha * 0.15, a = alpha},
            radius = target.radius,
            filled = true,
            target = target.position,
            surface = surface,
            render_mode = "chart",
            time_to_live = 15 * i,
        }
    end
    target.flashed = true
end

-- Queued targets fire oldest first, one per ready cannon - the player's own
-- targets before any the fire control picked.
local function fire_queued(tick)
    for pass = 1, 2 do
        local want_auto = pass == 2
        for _, target in ipairs(storage.targets) do
            if target.state == "queued" and (target.auto ~= nil) == want_auto then
                local cannon, reason = pick_cannon(target.force_index, target.planet, target.ammo, tick, target)
                if cannon then
                    fire(cannon, target, tick)
                elseif reason ~= target.reason then
                    target.reason = reason
                    update_label(target, tick)
                end
            end
        end
    end
end

-- A guided round follows its enemy: the target position moves with it, and
-- the last two sightings give its velocity. GUIDED_LOCK_TICKS before impact
-- the aim is fixed where the enemy will be by then. An enemy that dies before
-- the lock leaves the aim where it was last seen.
local function guide(target, tick)
    local entity = target.entity
    if target.locked then return end
    if entity.valid then
        local now = entity.position
        if target.seen_tick and tick > target.seen_tick then
            local dt = tick - target.seen_tick
            target.velocity = {x = (now.x - target.seen_position.x) / dt, y = (now.y - target.seen_position.y) / dt}
        end
        target.seen_position, target.seen_tick = now, tick
        target.position = {x = now.x, y = now.y}
    end
    if target.state == "inbound" and (tick >= target.impact_tick - shared.GUIDED_LOCK_TICKS or not entity.valid) then
        local lead = target.velocity or {x = 0, y = 0}
        local remaining = math.max(0, target.impact_tick - tick)
        local dx, dy = lead.x * remaining, lead.y * remaining
        local length = math.sqrt(dx * dx + dy * dy)
        if length > shared.GUIDED_MAX_LEAD then
            dx, dy = dx / length * shared.GUIDED_MAX_LEAD, dy / length * shared.GUIDED_MAX_LEAD
        end
        target.position = {x = target.position.x + dx, y = target.position.y + dy}
        target.locked = true
        draw_markers(target, tick)
    end
end

local function process_targets(tick)
    local targets = storage.targets
    for i = #targets, 1, -1 do
        local target = targets[i]
        local surface = game.surfaces[target.surface_index]
        if target.auto and target.state == "queued" and tick - (target.created or tick) > shared.AUTO_STALE_TICKS then
            -- The fire control's pick went stale (its cannon left orbit or ran
            -- dry in the meantime); it will pick afresh.
            destroy_markers(target)
            table.remove(targets, i)
        elseif target.entity and target.state == "queued" and not target.entity.valid then
            -- The enemy died before any cannon could fire at it: nothing to hit.
            destroy_markers(target)
            table.remove(targets, i)
        elseif not surface then
            destroy_markers(target)
            table.remove(targets, i)
        elseif target.state == "inbound" then
            if target.entity then guide(target, tick) end
            if not target.sound_played and tick >= target.impact_tick - REENTRY_SOUND_TICKS then
                surface.play_sound{path = "orbital-reentry", position = target.position}
                target.sound_played = true
            end
            if not target.fall_spawned and tick >= target.impact_tick - shared.FALL_TICKS then
                spawn_strike(target, surface, tick)
            end
            if target.fall_spawned and not target.flashed and tick >= target.impact_tick then
                flash_on_map(target, surface)
            end
            if tick >= (target.done_tick or target.impact_tick) + UPDATE_INTERVAL then
                destroy_markers(target)
                table.remove(targets, i)
            else
                update_label(target, tick)
            end
        end
    end

    for _, target in ipairs(targets) do
        if target.entity and target.state == "queued" and target.entity.valid then
            target.position = target.entity.position
        end
    end
    fire_queued(tick)
end

--------------------------------------------------------------------------------
-- marking and cancelling targets
--------------------------------------------------------------------------------

local GUIDED_TYPES = {"unit", "spider-unit", "segmented-unit", "segment", "unit-spawner", "turret"}

-- The enemy nearest to `position` a guided round can lock on to, or nil.
local function nearest_enemy(force, surface, position)
    local best, best_distance
    for _, entity in pairs(surface.find_entities_filtered{
        position = position, radius = shared.GUIDED_SNAP_RADIUS, type = GUIDED_TYPES,
    }) do
        if force.is_enemy(entity.force) then
            local dx, dy = entity.position.x - position.x, entity.position.y - position.y
            local distance = dx * dx + dy * dy
            if not best or distance < best_distance then
                best, best_distance = entity, distance
            end
        end
    end
    return best
end

-- Queues a strike with `ammo`. Returns the target, or nil and a localised
-- reason why not. `ignore_chart` exists for headless tests only: the benchmark
-- mode they run in never charts anything.
local function order_strike(force, surface, position, tick, ammo, ignore_chart, auto)
    if not shared.AMMO[ammo] then
        return nil, {"orbital-bombardment.error-unknown-ammo"}
    end
    if not is_unlocked(force, ammo) then
        return nil, {"orbital-bombardment.error-ammo-locked", "[item=" .. ammo .. "]"}
    end
    local planet = surface.planet
    if not planet then
        return nil, {"orbital-bombardment.error-no-planet"}
    end
    local chunk = {x = math.floor(position.x / 32), y = math.floor(position.y / 32)}
    if not (ignore_chart or storage.ignore_chart) and not force.is_chunk_charted(surface, chunk) then
        return nil, {"orbital-bombardment.error-uncharted"}
    end
    if not has_cannon_over(force.index, planet.name) then
        return nil, {"orbital-bombardment.error-no-cannon", planet.prototype.localised_name}
    end
    local followed
    if shared.AMMO[ammo].guided then
        followed = nearest_enemy(force, surface, position)
        if not followed then
            return nil, {"orbital-bombardment.error-no-guided-target", shared.GUIDED_SNAP_RADIUS}
        end
        position = followed.position
    end
    local queued = 0
    for _, other in pairs(storage.targets) do
        if other.force_index == force.index and other.planet == planet.name and other.state == "queued" and not other.auto then
            queued = queued + 1
        end
    end
    if queued >= shared.MAX_QUEUE then
        return nil, {"orbital-bombardment.error-queue-full", shared.MAX_QUEUE}
    end

    local target = {
        force_index = force.index,
        surface_index = surface.index,
        planet = planet.name,
        position = {x = position.x, y = position.y},
        ammo = ammo,
        state = "queued",
        reason = "no-cannon",
        radius = shared.AMMO[ammo].radius,
        objects = {},
        entity = followed,
        auto = auto,
        cannon_id = auto and auto.cannon_id,
        created = tick,
    }
    storage.targets[#storage.targets + 1] = target
    draw_markers(target, tick)
    -- Fire straight away if a cannon is ready instead of waiting for the next
    -- pass - but through the queue, so older targets still go first.
    fire_queued(tick)
    return target
end

--------------------------------------------------------------------------------
-- fire control: the cannon picking its own targets
--------------------------------------------------------------------------------

local AUTO_MODES = {"off", "defend", "clear"}
local THREAT_TICKS = 10 * 60
local NEST_REFRESH_TICKS = 60 * 60

local function fire_control_researched(force)
    local tech = force.technologies[shared.FIRE_CONTROL]
    return tech ~= nil and tech.researched
end

-- How far from the force's own buildings a round may land. The EMP only
-- harms enemies; everything else hurts whatever is in its circle, the cluster
-- rod's bomblets landing anywhere in their spread.
local function safety_radius(ammo)
    local data = shared.AMMO[ammo]
    if data.emp then return 3 end
    return (data.spread or data.radius) + 2
end

local function own_near(surface, force, position, radius)
    return surface.count_entities_filtered{position = position, radius = radius, force = force, limit = 1} > 0
end

local HOSTILE_TYPES = {"unit", "spider-unit", "segmented-unit", "unit-spawner", "turret"}

local function enemies_near(surface, force, position, radius)
    for _, entity in pairs(surface.find_entities_filtered{position = position, radius = radius, type = HOSTILE_TYPES}) do
        if force.is_enemy(entity.force) then return true end
    end
    return false
end

local function already_targeted(force_index, surface_index, position, radius)
    for _, target in pairs(storage.targets) do
        if target.force_index == force_index and target.surface_index == surface_index then
            local dx, dy = target.position.x - position.x, target.position.y - position.y
            if dx * dx + dy * dy < radius * radius then return true end
        end
    end
    return false
end

-- Defence: the most recent attack on the force's buildings. The aim starts on
-- the attacker and steps away from the building it hit until the round would
-- no longer reach anything of the force's own - a barrage in front of the
-- walls, not on them.
local function defend_target(force, surface, ammo, tick)
    local per_force = storage.threats[force.index]
    local list = per_force and per_force[surface.index]
    if not list then return nil end
    local safe, radius = safety_radius(ammo), shared.AMMO[ammo].radius
    for i = #list, 1, -1 do
        local threat = list[i]
        if tick - threat.tick > THREAT_TICKS then
            table.remove(list, i)
        else
            local dx, dy = threat.position.x - threat.from.x, threat.position.y - threat.from.y
            local length = math.sqrt(dx * dx + dy * dy)
            if length < 0.1 then dx, dy, length = 0, -1, 1 end
            dx, dy = dx / length, dy / length
            for step = 0, shared.AUTO_MAX_STEP_OUT, 2 do
                local aim = {x = threat.position.x + dx * step, y = threat.position.y + dy * step}
                if not own_near(surface, force, aim, safe) then
                    -- The attackers may be dead or gone by now: only fire
                    -- where enemies still are.
                    if enemies_near(surface, force, aim, radius + 4)
                        and not already_targeted(force.index, surface.index, aim, radius) then
                        table.remove(list, i)
                        return aim
                    end
                    break
                end
            end
        end
    end
    return nil
end

-- Clearing: the enemy nest in the thickest of the force's pollution - the ones
-- the attacks come from. Charted ground only, nothing next to own buildings.
local function clear_target(force, surface, ammo, tick)
    local cache = storage.nests[surface.index]
    if not cache or tick - cache.tick > NEST_REFRESH_TICKS then
        cache = {tick = tick, list = surface.find_entities_filtered{type = "unit-spawner"}}
        storage.nests[surface.index] = cache
    end
    local safe, radius = safety_radius(ammo), shared.AMMO[ammo].radius
    local best, best_pollution
    for _, nest in pairs(cache.list) do
        if nest.valid and force.is_enemy(nest.force) then
            local p = nest.position
            local pollution = surface.get_pollution(p)
            if pollution > 0 and (not best or pollution > best_pollution)
                and (storage.ignore_chart or force.is_chunk_charted(surface, {x = math.floor(p.x / 32), y = math.floor(p.y / 32)}))
                and not already_targeted(force.index, surface.index, p, radius)
                and not own_near(surface, force, p, safe) then
                best, best_pollution = nest, pollution
            end
        end
    end
    return best and best.position
end

local function pending_auto(cannon_id)
    for _, target in pairs(storage.targets) do
        if target.cannon_id == cannon_id and target.state == "queued" then return true end
    end
    return false
end

-- Which forces need attacks on their buildings recorded. The damage event is
-- only listened to while at least one cannon defends.
local DAMAGE_FILTER = {}
for _, excluded in ipairs({"unit", "unit-spawner", "turret", "spider-unit", "segmented-unit", "segment",
    "tree", "simple-entity", "fish", "asteroid", "plant"}) do
    DAMAGE_FILTER[#DAMAGE_FILTER + 1] = {filter = "type", type = excluded, invert = true, mode = "and"}
end

local function on_damaged(event)
    local cause, entity = event.cause, event.entity
    if not (cause and cause.valid and entity.valid) then return end
    local force = entity.force
    if not storage.defending[force.index] or not force.is_enemy(cause.force) then return end
    local per_force = storage.threats[force.index] or {}
    storage.threats[force.index] = per_force
    local list = per_force[entity.surface.index] or {}
    per_force[entity.surface.index] = list
    local position = cause.position
    for _, threat in pairs(list) do
        local dx, dy = threat.position.x - position.x, threat.position.y - position.y
        if dx * dx + dy * dy < 64 then
            threat.position, threat.from, threat.tick = position, entity.position, event.tick
            return
        end
    end
    if #list >= 20 then table.remove(list, 1) end
    list[#list + 1] = {position = position, from = entity.position, tick = event.tick}
end

local function update_damage_handler()
    if next(storage.defending or {}) then
        script.on_event(defines.events.on_entity_damaged, on_damaged, DAMAGE_FILTER)
    else
        script.on_event(defines.events.on_entity_damaged, nil)
    end
end

local function refresh_defending()
    local defending = {}
    for _, cannon in pairs(storage.cannons) do
        if cannon.entity.valid and cannon.auto and cannon.auto.mode == "defend" then
            defending[cannon.entity.force.index] = true
        end
    end
    storage.defending = defending
    update_damage_handler()
end

-- Once a second: every cannon on fire control that is ready, has rounds above
-- its reserve and no pick of its own waiting, picks a target.
local function run_fire_control(tick)
    for id, cannon in pairs(storage.cannons) do
        local entity, auto = cannon.entity, cannon.auto
        if entity.valid and auto and auto.mode ~= "off" then
            local force = entity.force
            local planet_name = orbit_of(entity)
            local planet = planet_name and game.planets[planet_name]
            local surface = planet and planet.surface
            local loaded = shared.count_ammo(ammo_inventory(entity))[auto.ammo] or 0
            if not fire_control_researched(force) then
                auto.status = "locked"
            elseif not surface then
                auto.status = "no-orbit"
            elseif loaded <= auto.reserve then
                auto.status = "reserve"
            elseif not is_unlocked(force, auto.ammo) then
                auto.status = "ammo-locked"
            elseif cannon.ready_tick > tick or pending_auto(id) then
                auto.status = "busy"
            else
                local aim
                if auto.mode == "defend" then
                    aim = defend_target(force, surface, auto.ammo, tick)
                else
                    aim = clear_target(force, surface, auto.ammo, tick)
                end
                if aim then
                    local target = order_strike(force, surface, aim, tick, auto.ammo, false, {cannon_id = id, mode = auto.mode})
                    auto.status = target and "firing" or "idle-" .. auto.mode
                else
                    auto.status = "idle-" .. auto.mode
                end
            end
        end
    end
end

--------------------------------------------------------------------------------
-- area clearing: drag the designator over an area, the strikes plan themselves
--------------------------------------------------------------------------------

-- Every enemy in the area is found, nests and worms weighing more than units.
-- Then, greedily, the strike that covers the most uncovered weight is placed
-- (on the middle of what it covers) until everything is covered. Guided rods
-- get one rod per enemy. Strikes that would land on the force's own buildings
-- are left out and counted.
local function plan_area(force, surface, area, ammo, tick, ignore_chart)
    local data = shared.AMMO[ammo]
    if not data then return nil, {"orbital-bombardment.error-unknown-ammo"} end
    local enemies = {}
    for _, entity in pairs(surface.find_entities_filtered{area = area, type = HOSTILE_TYPES}) do
        if force.is_enemy(entity.force) then
            local static = entity.type == "unit-spawner" or entity.type == "turret"
            enemies[#enemies + 1] = {position = entity.position, weight = static and 3 or 1}
        end
    end
    if #enemies == 0 then
        return nil, {"orbital-bombardment.area-empty"}
    end

    -- How far one strike reaches, for planning. A little inside the real
    -- radius, since the strike is aimed at the middle of its group.
    local reach = data.guided and 0.5 or (data.spread or data.radius) * 0.8
    local reach2 = reach * reach
    local function close(a, b)
        local dx, dy = a.x - b.x, a.y - b.y
        return dx * dx + dy * dy <= reach2
    end

    local covered, aims = {}, {}
    while true do
        local best, best_score
        for i, enemy in ipairs(enemies) do
            if not covered[i] then
                local score = 0
                for j, other in ipairs(enemies) do
                    if not covered[j] and close(enemy.position, other.position) then score = score + other.weight end
                end
                if not best or score > best_score then best, best_score = i, score end
            end
        end
        if not best then break end
        local center = enemies[best].position
        local x, y, n = 0, 0, 0
        for j, other in ipairs(enemies) do
            if not covered[j] and close(center, other.position) then
                covered[j] = true
                x, y, n = x + other.position.x, y + other.position.y, n + 1
            end
        end
        aims[#aims + 1] = data.guided and center or {x = x / n, y = y / n}
    end

    local planned, skipped, full = 0, 0, false
    local safe = safety_radius(ammo)
    for _, aim in ipairs(aims) do
        if own_near(surface, force, aim, safe) then
            skipped = skipped + 1
        else
            local target, err = order_strike(force, surface, aim, tick, ammo, ignore_chart)
            if target then
                planned = planned + 1
            elseif err and err[1] == "orbital-bombardment.error-queue-full" then
                full = true
                break
            elseif planned == 0 and err and err[1] ~= "orbital-bombardment.error-no-guided-target"
                and err[1] ~= "orbital-bombardment.error-uncharted" then
                return nil, err -- no cannon, locked round, not a planet: says it all
            end
        end
    end
    return planned, {"orbital-bombardment.area-planned", planned, #enemies, skipped, full and 1 or 0}
end

--------------------------------------------------------------------------------
-- the strike planner behind "automatic" ammo
--------------------------------------------------------------------------------

-- Works out which rounds to fire where so that every enemy in the area dies,
-- with what is actually loaded over the planet, at the lowest cost.
--
-- Damage: each round's zones from shared.AMMO against the enemy's real health
-- (evolution included) and resistances, measured to the edge of its collision
-- box. The cluster rod counts with the expected share of its bomblets, the
-- EMP with its pulse, the incendiary rod with the part of the napalm a
-- structure sits in (units run out of it but keep burning).
-- Cannons: every cannon over the planet with its own loaded rounds, reload and
-- flight times. A strike goes to the cannon that can land it earliest, so
-- with many cannons rounds fly in parallel and with few the planner leans
-- towards fewer, heavier strikes.
-- Choice: greedily, the strike with the most damage value per cost - cost being
-- the round's worth (dearer as it runs short) plus PLAN_TIME_COST per second
-- until it lands - until every enemy is expected dead, nothing loaded still
-- helps, or the queue is full. Greed alone favours cheap rounds that only
-- wound, so this is run several times with partial damage counting less and
-- less, and the plan with the lowest total - rounds, time until the last
-- impact, survivors - is taken. All damage numbers are worked out once up
-- front; the passes only track health.
local PLAN_TIME_COST = 0.4      -- cost units per second until impact
local PLAN_WEIGHT = {static = 3, big = 5, unit = 1}
local PLAN_NAPALM_SHARE = 0.4   -- share of the burn a structure in the circle takes
local PLAN_UNIT_FIRE = 1500     -- napalm and fire sticker on a unit caught in it
local PLAN_NEIGHBOURHOOD = 8    -- aims are also tried at the middle of each enemy's neighbours
local PLAN_MIN_SCORE = 0.01
local PLAN_MAX_ENEMIES = 200    -- beyond this, drag a smaller area
local PLAN_SCARCITY = 2         -- a round with n left is worth (1 + PLAN_SCARCITY / n) times its cost
local PLAN_SURVIVOR_COST = 50   -- per weight of an enemy a plan leaves alive
local PLAN_EXPONENTS = {1, 2, 4}
local BIG_TYPES = {["segmented-unit"] = true, ["spider-unit"] = true}
local STATIC_TYPES = {["unit-spawner"] = true, ["turret"] = true}

local function resisted(amount, type, resistances)
    local resistance = resistances and resistances[type]
    if not resistance then return amount end
    if amount <= resistance.decrease then return 0 end
    return (amount - resistance.decrease) * (1 - resistance.percent)
end

-- Damage one round of `ammo` does to `enemy` at `distance` from the aim,
-- distance already measured to the edge of the enemy.
local function strike_damage(ammo, distance, enemy, bonus)
    local data = shared.AMMO[ammo]
    local total = 0
    if data.bomblets then
        if distance <= data.spread then
            local zone = data.zones[1]
            local reach = zone.radius + enemy.size
            local hits = data.bomblets * math.min(1, reach * reach / (data.spread * data.spread))
            for type, amount in pairs(zone.damage) do
                total = total + hits * resisted(amount, type, enemy.resistances)
            end
        end
        return total * (1 + bonus)
    end
    for _, zone in ipairs(data.zones) do
        if distance <= zone.radius then
            for type, amount in pairs(zone.damage) do
                total = total + resisted(amount, type, enemy.resistances)
            end
        end
    end
    if data.emp and distance <= data.radius then
        total = total + resisted(shared.EMP_DAMAGE, "electric", enemy.resistances)
    end
    if data.napalm and distance <= data.radius then
        if enemy.kind == "unit" then
            total = total + PLAN_UNIT_FIRE
        else
            total = total + resisted(shared.NAPALM_DAMAGE_PER_TICK, "fire", enemy.resistances)
                * shared.NAPALM_BURN_TICKS * PLAN_NAPALM_SHARE
        end
    end
    return total * (1 + bonus)
end

local function plan_smart(force, surface, area, tick, ignore_chart)
    local planet = surface.planet
    if not planet then return nil, {"orbital-bombardment.error-no-planet"} end

    -- The cannons over the planet: their own rounds and when each can fire.
    local cannons = {}
    for id, cannon in pairs(storage.cannons) do
        local entity = cannon.entity
        if entity.valid and entity.force.index == force.index and orbit_of(entity) == planet.name then
            local stock = {}
            for ammo, count in pairs(shared.count_ammo(ammo_inventory(entity))) do
                if is_unlocked(force, ammo) then stock[ammo] = count end
            end
            cannons[#cannons + 1] = {id = id, ready = math.max(0, cannon.ready_tick - tick), stock = stock}
        end
    end
    if #cannons == 0 then
        return nil, {"orbital-bombardment.error-no-cannon", planet.prototype.localised_name}
    end
    -- Rounds already promised to waiting targets are not available.
    local queued = 0
    for _, target in pairs(storage.targets) do
        if target.state == "queued" and target.force_index == force.index and target.planet == planet.name then
            if not target.auto then queued = queued + 1 end
            for _, cannon in ipairs(cannons) do
                if (cannon.stock[target.ammo] or 0) > 0 then
                    cannon.stock[target.ammo] = cannon.stock[target.ammo] - 1
                    break
                end
            end
        end
    end

    -- The enemies.
    local enemies = {}
    for _, entity in pairs(surface.find_entities_filtered{area = area, type = HOSTILE_TYPES}) do
        if force.is_enemy(entity.force) and entity.health and #enemies < PLAN_MAX_ENEMIES then
            local box = entity.prototype.collision_box
            local kind = BIG_TYPES[entity.type] and "big" or STATIC_TYPES[entity.type] and "static" or "unit"
            enemies[#enemies + 1] = {
                position = entity.position,
                hp = entity.health,
                resistances = entity.prototype.resistances,
                size = math.max(-box.left_top.x, box.right_bottom.x, -box.left_top.y, box.right_bottom.y),
                kind = kind,
                weight = PLAN_WEIGHT[kind],
            }
        end
    end
    if #enemies == 0 then return nil, {"orbital-bombardment.area-empty"} end

    -- Aims: every enemy, and the middle of every enemy's neighbourhood.
    local aims = {}
    local near2 = PLAN_NEIGHBOURHOOD * PLAN_NEIGHBOURHOOD
    for i, enemy in ipairs(enemies) do
        aims[#aims + 1] = {position = enemy.position, enemy = i}
        local x, y, n = 0, 0, 0
        for _, other in ipairs(enemies) do
            local dx, dy = other.position.x - enemy.position.x, other.position.y - enemy.position.y
            if dx * dx + dy * dy <= near2 then x, y, n = x + other.position.x, y + other.position.y, n + 1 end
        end
        if n > 1 then aims[#aims + 1] = {position = {x = x / n, y = y / n}} end
    end

    -- Damage of every round from every aim to every enemy it reaches, once.
    -- A guided rod only goes for an enemy aim and follows that enemy.
    local max_reach = 0
    for _, data in pairs(shared.AMMO) do max_reach = math.max(max_reach, data.spread or data.radius) end
    local bonus = damage_bonus(force)
    local hits = {} -- hits[ammo][aim] = {{enemy, damage}, ...}
    for ammo, data in pairs(shared.AMMO) do
        hits[ammo] = {}
        for a, aim in ipairs(aims) do
            local list = {}
            if not data.guided or aim.enemy then
                for e, enemy in ipairs(enemies) do
                    local dx, dy = enemy.position.x - aim.position.x, enemy.position.y - aim.position.y
                    local distance = math.sqrt(dx * dx + dy * dy) - enemy.size
                    if data.guided and e == aim.enemy then distance = 0 end
                    if distance <= max_reach then
                        local damage = strike_damage(ammo, math.max(0, distance), enemy, bonus)
                        if damage > 0 then list[#list + 1] = {e, damage} end
                    end
                end
            end
            hits[ammo][a] = list
        end
    end

    local safe = {} -- safe[ammo .. a]: would this strike miss our own buildings?
    local function is_safe(ammo, a)
        local key = ammo .. "|" .. a
        if safe[key] == nil then
            safe[key] = not own_near(surface, force, aims[a].position, safety_radius(ammo))
        end
        return safe[key]
    end

    -- One greedy pass. `exponent` sets how much partial damage counts: at 1 a
    -- strike that leaves five nests at half health looks as good as one that
    -- kills two and a half of them; higher values favour finishing enemies
    -- off. Rounds get dearer as they run short.
    local room = shared.MAX_QUEUE - queued
    local function plan(exponent)
        local hp, stock, ready = {}, {}, {}
        for e, enemy in ipairs(enemies) do hp[e] = enemy.hp end
        for c, cannon in ipairs(cannons) do
            stock[c], ready[c] = {}, cannon.ready
            for ammo, count in pairs(cannon.stock) do stock[c][ammo] = count end
        end
        local strikes, spent = {}, 0
        while #strikes < room do
            local best
            for ammo, data in pairs(shared.AMMO) do
                local cannon, left = nil, 0
                for c in ipairs(cannons) do
                    local n = stock[c][ammo] or 0
                    left = left + n
                    if n > 0 and (not cannon or ready[c] < ready[cannon]) then cannon = c end
                end
                if cannon then
                    local impact = ready[cannon] + data.flight
                    local worth = data.cost * (1 + PLAN_SCARCITY / left)
                    local cost = worth + PLAN_TIME_COST * impact / 60
                    for a, list in pairs(hits[ammo]) do
                        local value = 0
                        for _, hit in ipairs(list) do
                            local e = hit[1]
                            if hp[e] > 0 then
                                value = value + enemies[e].weight * math.min(1, hit[2] / hp[e]) ^ exponent
                            end
                        end
                        local score = value / cost
                        if score > PLAN_MIN_SCORE and (not best or score > best.score) and is_safe(ammo, a) then
                            best = {score = score, ammo = ammo, aim = a, cannon = cannon, impact = impact, worth = worth}
                        end
                    end
                end
            end
            if not best then break end
            for _, hit in ipairs(hits[best.ammo][best.aim]) do
                hp[hit[1]] = hp[hit[1]] - hit[2]
            end
            stock[best.cannon][best.ammo] = stock[best.cannon][best.ammo] - 1
            best.fire_at = ready[best.cannon]
            ready[best.cannon] = ready[best.cannon] + reload_ticks(force, best.ammo)
            spent = spent + best.worth
            strikes[#strikes + 1] = best
            local alive = false
            for e = 1, #enemies do if hp[e] > 0 then alive = true break end end
            if not alive then break end
        end
        local last, surviving, lost = 0, 0, 0
        for _, strike in ipairs(strikes) do last = math.max(last, strike.impact) end
        for e, enemy in ipairs(enemies) do
            if hp[e] > 0 then surviving, lost = surviving + 1, lost + enemy.weight end
        end
        return strikes, spent + PLAN_TIME_COST * last / 60 + PLAN_SURVIVOR_COST * lost, surviving
    end

    -- Several passes, the cheapest whole plan wins.
    local strikes, surviving, best_total
    for _, exponent in ipairs(PLAN_EXPONENTS) do
        local candidate, total, left = plan(exponent)
        if not best_total or total < best_total then
            strikes, surviving, best_total = candidate, left, total
        end
    end

    -- Queue them in the order they are meant to fire.
    table.sort(strikes, function(x, y) return x.fire_at < y.fire_at end)
    local used, last_impact, full = {}, 0, false
    for _, planned in ipairs(strikes) do
        local target, err = order_strike(force, surface, aims[planned.aim].position, tick, planned.ammo, ignore_chart)
        if target then
            used[planned.ammo] = (used[planned.ammo] or 0) + 1
            last_impact = math.max(last_impact, planned.impact)
        elseif err and err[1] == "orbital-bombardment.error-queue-full" then
            full = true
            break
        end
    end

    local list = {""}
    for _, ammo in ipairs(shared.AMMO_ORDER) do
        if used[ammo] then list[#list + 1] = used[ammo] .. "× [item=" .. ammo .. "]  " end
    end
    if #list == 1 then
        return 0, {"orbital-bombardment.area-smart-none", #enemies}
    end
    return #strikes, {"orbital-bombardment.area-smart", list, #enemies, math.ceil(last_impact / 60), surviving, full and 1 or 0}
end

local function area_center(area)
    return {
        x = (area.left_top.x + area.right_bottom.x) / 2,
        y = (area.left_top.y + area.right_bottom.y) / 2,
    }
end

-- Cancels the force's queued targets inside the area, or within a couple of
-- tiles of a single click. Returns how many were cancelled and how many in the
-- area had already been fired.
local function cancel_targets(force, surface, area)
    local center = area_center(area)
    local cancelled, inbound = 0, 0
    local targets = storage.targets
    for i = #targets, 1, -1 do
        local target = targets[i]
        if target.force_index == force.index and target.surface_index == surface.index then
            local p = target.position
            local inside = p.x >= area.left_top.x and p.x <= area.right_bottom.x
                and p.y >= area.left_top.y and p.y <= area.right_bottom.y
            local dx, dy = p.x - center.x, p.y - center.y
            if inside or dx * dx + dy * dy <= 4 then
                if target.state == "queued" then
                    destroy_markers(target)
                    table.remove(targets, i)
                    cancelled = cancelled + 1
                else
                    inbound = inbound + 1
                end
            end
        end
    end
    return cancelled, inbound
end

local function notify(player, message)
    player.create_local_flying_text{text = message, create_at_cursor = true}
end

--------------------------------------------------------------------------------
-- ammo bar, shown while the designator is in hand
--------------------------------------------------------------------------------

local function unlocked_ammo(force)
    local list = {}
    for _, ammo in ipairs(shared.AMMO_ORDER) do
        if is_unlocked(force, ammo) then list[#list + 1] = ammo end
    end
    return list
end

-- The player's chosen ammo, falling back to the first unlocked one.
-- "auto" lets the mod pick the round per target; it is the default.
local AUTO_AMMO = "auto"

local function selected_ammo(player)
    local selected = storage.selected[player.index] or AUTO_AMMO
    if selected == AUTO_AMMO then return AUTO_AMMO end
    if shared.AMMO[selected] and is_unlocked(player.force, selected) then
        return selected
    end
    return AUTO_AMMO
end

-- Radius, time to impact, reload and damage in one tooltip block, so the
-- rounds can be told apart before they are fired.
local function ammo_stats(ammo, force)
    local data = shared.AMMO[ammo]
    local reload = force and reload_ticks(force, ammo) or data.reload
    local bonus = force and damage_bonus(force) or 0
    local lines = {"", "[color=255,230,192]",
        {"orbital-bombardment.ammo-stats", data.radius, data.flight / 60, math.floor(reload / 6 + 0.5) / 10}, "\n",
        {"orbital-bombardment.damage-" .. ammo}}
    if bonus > 0 then
        lines[#lines + 1] = "\n"
        lines[#lines + 1] = {"orbital-bombardment.damage-bonus", math.floor(bonus * 100 + 0.5)}
    end
    lines[#lines + 1] = "[/color]"
    return lines
end

local function hide_selector(player)
    local frame = player.gui.screen[SELECTOR_NAME]
    if frame then frame.destroy() end
    storage.selectors[player.index] = nil
end

-- Counts follow the planet in view: in remote view that is the planet below,
-- not the platform the player is standing on.
local function update_selector(player)
    local frame = player.gui.screen[SELECTOR_NAME]
    if not frame then return end
    local planet = player.surface.planet
    local counts = planet and rounds_over(player.force.index, planet.name) or {}
    local selected = selected_ammo(player)
    for _, button in pairs(frame.buttons.children) do
        local ammo = button.tags.orbital_ammo
        button.toggled = ammo == selected
        if ammo ~= AUTO_AMMO then
            button.number = planet and (counts[ammo] or 0) or nil
        end
    end
end

local function show_selector(player)
    hide_selector(player)
    local ammo_list = unlocked_ammo(player.force)
    if #ammo_list == 0 then return end
    local frame = player.gui.screen.add{
        type = "frame",
        name = SELECTOR_NAME,
        caption = {"orbital-bombardment.selector-title"},
        direction = "vertical",
    }
    frame.style.use_header_filler = false
    local buttons = frame.add{type = "frame", name = "buttons", style = "slot_button_deep_frame", direction = "horizontal"}
    buttons.add{
        type = "sprite-button",
        style = "slot_button",
        sprite = "virtual-signal/signal-anything",
        tooltip = {"", "[font=default-bold]", {"orbital-bombardment.ammo-auto"}, "[/font]\n", {"orbital-bombardment.ammo-auto-tooltip"}},
        tags = {orbital_ammo = AUTO_AMMO},
    }
    for _, ammo in ipairs(ammo_list) do
        buttons.add{
            type = "sprite-button",
            style = "slot_button",
            sprite = "item/" .. ammo,
            tooltip = {"", "[font=default-bold]", {"item-name." .. ammo}, "[/font]\n", {"item-description." .. ammo},
                "\n\n", ammo_stats(ammo, player.force)},
            tags = {orbital_ammo = ammo},
        }
    end
    -- Top centre, below where the vanilla alerts and research sit.
    local scale = player.display_scale
    local width = ((#ammo_list + 1) * 40 + 24) * scale
    frame.location = {x = math.floor((player.display_resolution.width - width) / 2), y = math.floor(90 * scale)}
    storage.selectors[player.index] = true
    update_selector(player)
end

local function holds_designator(player)
    local stack = player.cursor_stack
    return stack and stack.valid_for_read and stack.name == DESIGNATOR
end

--------------------------------------------------------------------------------
-- status window next to the cannon's own window
--------------------------------------------------------------------------------

local function close_gui(player)
    local frame = player.gui.relative[GUI_NAME]
    if frame then frame.destroy() end
    storage.guis[player.index] = nil
end

local function status_lines(cannon, tick)
    local entity = cannon.entity
    local planet = orbit_of(entity)
    local lines = {}
    if planet and game.planets[planet] then
        lines[1] = {"orbital-bombardment.status-orbit", game.planets[planet].prototype.localised_name}
    else
        lines[1] = {"orbital-bombardment.status-travelling"}
    end

    local loaded = {""}
    for _, ammo in ipairs(shared.AMMO_ORDER) do
        local count = shared.count_ammo(ammo_inventory(entity))[ammo]
        if count then loaded[#loaded + 1] = "[item=" .. ammo .. "] " .. count .. "   " end
    end
    if #loaded == 1 then
        lines[2] = {"orbital-bombardment.status-no-ammo"}
    elseif cannon.ready_tick > tick then
        lines[2] = {"orbital-bombardment.status-reloading", math.ceil((cannon.ready_tick - tick) / 60)}
    else
        lines[2] = {"orbital-bombardment.status-ready"}
    end
    lines[3] = #loaded > 1 and {"orbital-bombardment.status-loaded", loaded} or ""

    local queued, inbound = 0, 0
    if planet then
        for _, target in pairs(storage.targets) do
            if target.force_index == entity.force.index and target.planet == planet then
                if target.state == "queued" then queued = queued + 1 else inbound = inbound + 1 end
            end
        end
    end
    lines[4] = {"orbital-bombardment.status-targets", queued, inbound}
    return lines
end

-- The fire-control settings, below the status lines.
local function build_auto_section(container, cannon, force)
    container.clear()
    container.add{type = "label", caption = {"orbital-bombardment.auto-title"}, style = "caption_label"}
    if not fire_control_researched(force) then
        local label = container.add{type = "label", caption = {"orbital-bombardment.auto-locked"}}
        label.style.single_line = false
        label.style.maximal_width = 260
        return
    end
    local auto = cannon.auto
    local id = cannon.entity.unit_number

    local mode_row = container.add{type = "flow", direction = "horizontal"}
    mode_row.style.vertical_align = "center"
    mode_row.add{type = "label", caption = {"orbital-bombardment.auto-mode"}}
    local items, selected = {}, 1
    for i, mode in ipairs(AUTO_MODES) do
        items[i] = {"orbital-bombardment.auto-mode-" .. mode}
        if mode == auto.mode then selected = i end
    end
    mode_row.add{type = "drop-down", items = items, selected_index = selected, tags = {orbital_auto = "mode", cannon = id}}

    container.add{type = "label", caption = {"orbital-bombardment.auto-ammo"}}
    local buttons = container.add{type = "frame", style = "slot_button_deep_frame", direction = "horizontal"}
    for _, ammo in ipairs(shared.AMMO_ORDER) do
        if is_unlocked(force, ammo) then
            buttons.add{
                type = "sprite-button",
                style = "slot_button",
                sprite = "item/" .. ammo,
                toggled = auto.ammo == ammo,
                tooltip = {"", "[font=default-bold]", {"item-name." .. ammo}, "[/font]\n", ammo_stats(ammo, force)},
                tags = {orbital_auto = "ammo", cannon = id, ammo = ammo},
            }
        end
    end

    local reserve_row = container.add{type = "flow", direction = "horizontal"}
    reserve_row.style.vertical_align = "center"
    reserve_row.add{type = "label", caption = {"orbital-bombardment.auto-reserve"}, tooltip = {"orbital-bombardment.auto-reserve-tooltip"}}
    reserve_row.add{
        type = "slider", style = "notched_slider",
        minimum_value = 0, maximum_value = 10, value = auto.reserve, value_step = 1, discrete_values = true,
        tags = {orbital_auto = "reserve", cannon = id},
    }
    reserve_row.add{type = "label", name = "reserve_value", caption = tostring(auto.reserve)}

    local status = container.add{type = "label", name = "auto_status"}
    status.style.single_line = false
    status.style.maximal_width = 260
    status.style.font_color = {r = 0.7, g = 0.7, b = 0.7}
end

local function update_gui(player, tick)
    local frame = player.gui.relative[GUI_NAME]
    local cannon = storage.cannons[storage.guis[player.index] or 0]
    if not (frame and cannon and cannon.entity.valid) then
        close_gui(player)
        return
    end
    for i, line in pairs(status_lines(cannon, tick)) do
        frame.inner["line" .. i].caption = line
    end
    local status = frame.auto and frame.auto.auto_status
    if status then
        local auto = cannon.auto
        status.caption = auto.mode == "off" and "" or {"orbital-bombardment.auto-status-" .. (auto.status or "busy")}
    end
end

local function open_gui(player, entity, tick)
    close_gui(player)
    local frame = player.gui.relative.add{
        type = "frame",
        name = GUI_NAME,
        caption = {"orbital-bombardment.gui-title"},
        direction = "vertical",
        anchor = {
            gui = defines.relative_gui_type.turret_gui,
            position = defines.relative_gui_position.right,
            name = CANNON,
        },
    }
    local inner = frame.add{type = "frame", name = "inner", style = "inside_shallow_frame_with_padding", direction = "vertical"}
    for i = 1, 4 do
        inner.add{type = "label", name = "line" .. i}
    end
    local hint = inner.add{type = "label", caption = {"orbital-bombardment.gui-hint"}}
    hint.style.single_line = false
    hint.style.maximal_width = 260
    hint.style.top_margin = 8
    hint.style.font_color = {r = 0.7, g = 0.7, b = 0.7}
    local auto = frame.add{type = "frame", name = "auto", style = "inside_shallow_frame_with_padding", direction = "vertical"}
    auto.style.top_margin = 8
    storage.guis[player.index] = entity.unit_number
    build_auto_section(auto, storage.cannons[entity.unit_number], player.force)
    update_gui(player, tick)
end

-- Rebuilds the fire-control section for everyone looking at this cannon.
local function refresh_auto_guis(cannon_id)
    for player_index, open_id in pairs(storage.guis) do
        local player = game.get_player(player_index)
        local frame = player and player.gui.relative[GUI_NAME]
        if open_id == cannon_id and frame and frame.auto then
            build_auto_section(frame.auto, storage.cannons[cannon_id], player.force)
        end
    end
end

--------------------------------------------------------------------------------
-- events
--------------------------------------------------------------------------------

script.on_init(function()
    init_storage()
    rescan_cannons()
    refresh_defending()
end)

script.on_configuration_changed(function()
    init_storage()
    rescan_cannons()
    refresh_defending()
end)

-- The damage listener is not saved; re-register it the way the save needs.
script.on_load(function()
    update_damage_handler()
end)

script.on_nth_tick(shared.AUTO_INTERVAL, function(event)
    run_fire_control(event.tick)
end)

script.on_nth_tick(UPDATE_INTERVAL, function(event)
    local tick = event.tick
    if storage.targets[1] then
        process_targets(tick)
    end
    for player_index in pairs(storage.guis) do
        local player = game.get_player(player_index)
        if player then
            update_gui(player, tick)
        else
            storage.guis[player_index] = nil
        end
    end
    for player_index in pairs(storage.selectors) do
        local player = game.get_player(player_index)
        if player and holds_designator(player) then
            update_selector(player)
        elseif player then
            hide_selector(player)
        else
            storage.selectors[player_index] = nil
        end
    end
end)

-- Bomblets, the EMP, napalm and re-enabling worms need tick precision; the
-- 10-tick pass above does not. Nothing to do on almost every tick.
script.on_event(defines.events.on_tick, function(event)
    if storage.scheduled[1] then
        run_scheduled(event.tick)
    end
end)

local BUILT_FILTER = {{filter = "name", name = CANNON}}
local function on_built(event) register(event.entity) end
script.on_event(defines.events.on_built_entity, on_built, BUILT_FILTER)
script.on_event(defines.events.on_robot_built_entity, on_built, BUILT_FILTER)
script.on_event(defines.events.on_space_platform_built_entity, on_built, BUILT_FILTER)
script.on_event(defines.events.script_raised_built, on_built, BUILT_FILTER)
script.on_event(defines.events.script_raised_revive, on_built, BUILT_FILTER)

script.on_event(defines.events.on_player_cursor_stack_changed, function(event)
    local player = game.get_player(event.player_index)
    if not player then return end
    if holds_designator(player) then
        if not player.gui.screen[SELECTOR_NAME] then show_selector(player) end
    elseif storage.selectors[player.index] then
        hide_selector(player)
    end
end)

script.on_event(defines.events.on_gui_click, function(event)
    local element = event.element
    local tags = element.valid and element.tags
    if not tags then return end
    local player = game.get_player(event.player_index)
    if not player then return end
    if tags.orbital_ammo then
        storage.selected[player.index] = tags.orbital_ammo
        update_selector(player)
    elseif tags.orbital_auto == "ammo" then
        local cannon = storage.cannons[tags.cannon]
        if cannon then
            cannon.auto.ammo = tags.ammo
            refresh_auto_guis(tags.cannon)
        end
    end
end)

script.on_event(defines.events.on_gui_selection_state_changed, function(event)
    local element = event.element
    local tags = element.valid and element.tags
    if not (tags and tags.orbital_auto == "mode") then return end
    local cannon = storage.cannons[tags.cannon]
    if not cannon then return end
    cannon.auto.mode = AUTO_MODES[element.selected_index] or "off"
    cannon.auto.status = nil
    refresh_defending()
    refresh_auto_guis(tags.cannon)
end)

script.on_event(defines.events.on_gui_value_changed, function(event)
    local element = event.element
    local tags = element.valid and element.tags
    if not (tags and tags.orbital_auto == "reserve") then return end
    local cannon = storage.cannons[tags.cannon]
    if not cannon then return end
    cannon.auto.reserve = math.floor(element.slider_value + 0.5)
    local value = element.parent.reserve_value
    if value then value.caption = tostring(cannon.auto.reserve) end
end)

-- Shift + right/left click copies the fire-control settings between cannons,
-- like any vanilla machine's settings.
script.on_event(defines.events.on_entity_settings_pasted, function(event)
    local source, destination = event.source, event.destination
    if not (source.valid and destination.valid and source.name == CANNON and destination.name == CANNON) then return end
    register(source)
    register(destination)
    local from = storage.cannons[source.unit_number].auto
    storage.cannons[destination.unit_number].auto = {mode = from.mode, ammo = from.ammo, reserve = from.reserve}
    refresh_defending()
    refresh_auto_guis(destination.unit_number)
end)

-- A click marks one target; dragging a box clears everything in it. With
-- automatic ammo a click plans for the enemies around it.
local CLICK_SIZE = 3
local AUTO_CLICK_REACH = 8

script.on_event(defines.events.on_player_selected_area, function(event)
    if event.item ~= DESIGNATOR then return end
    local player = game.get_player(event.player_index)
    if not player then return end
    local area = event.area
    local width = area.right_bottom.x - area.left_top.x
    local height = area.right_bottom.y - area.left_top.y
    local ammo = selected_ammo(player)
    local click = width < CLICK_SIZE and height < CLICK_SIZE
    if ammo == AUTO_AMMO then
        if click then
            local c = area_center(area)
            area = {left_top = {x = c.x - AUTO_CLICK_REACH, y = c.y - AUTO_CLICK_REACH},
                    right_bottom = {x = c.x + AUTO_CLICK_REACH, y = c.y + AUTO_CLICK_REACH}}
        end
        local _, message = plan_smart(player.force, event.surface, area, event.tick)
        notify(player, message)
    elseif click then
        local target, err = order_strike(player.force, event.surface, area_center(area), event.tick, ammo)
        if not target then notify(player, err) end
    else
        local _, message = plan_area(player.force, event.surface, area, ammo, event.tick)
        notify(player, message)
    end
    update_selector(player)
end)

script.on_event(defines.events.on_player_alt_selected_area, function(event)
    if event.item ~= DESIGNATOR then return end
    local player = game.get_player(event.player_index)
    if not player then return end
    local cancelled, inbound = cancel_targets(player.force, event.surface, event.area)
    if cancelled > 0 then
        notify(player, {"orbital-bombardment.cancelled", cancelled})
    elseif inbound > 0 then
        notify(player, {"orbital-bombardment.cannot-cancel-inbound"})
    else
        notify(player, {"orbital-bombardment.nothing-to-cancel"})
    end
end)

script.on_event(defines.events.on_gui_opened, function(event)
    local entity = event.entity
    if entity and entity.valid and entity.name == CANNON then
        local player = game.get_player(event.player_index)
        register(entity)
        if player then open_gui(player, entity, event.tick) end
    end
end)

script.on_event(defines.events.on_gui_closed, function(event)
    local entity = event.entity
    if entity and entity.valid and entity.name == CANNON then
        local player = game.get_player(event.player_index)
        if player then close_gui(player) end
    end
end)

-- For other mods and for tests: order a strike without a player.
-- options.ammo picks the round (default: the tungsten penetrator);
-- options.ignore_chart skips the charted-area check (see order_strike).
remote.add_interface("orbital-bombardment", {
    order_strike = function(force, surface, position, options)
        force = game.forces[force]
        surface = game.surfaces[surface]
        if not (force and surface and position) then return false, "invalid arguments" end
        options = options or {}
        -- MapPosition may come as {x = .., y = ..} or as {.., ..}.
        position = {x = position.x or position[1], y = position.y or position[2]}
        if not (position.x and position.y) then return false, "invalid arguments" end
        local target, err = order_strike(force, surface, position, game.tick,
            options.ammo or "tungsten-penetrator", options.ignore_chart or false)
        return target ~= nil, err
    end,
    -- Clears an area the way dragging the designator does. area = {left_top, right_bottom}.
    order_area = function(force, surface, area, options)
        force = game.forces[force]
        surface = game.surfaces[surface]
        if not (force and surface and area) then return false, "invalid arguments" end
        options = options or {}
        if options.ammo == "auto" then
            return plan_smart(force, surface, area, game.tick, options.ignore_chart or false)
        end
        local planned, message = plan_area(force, surface, area,
            options.ammo or "tungsten-penetrator", game.tick, options.ignore_chart or false)
        return planned, message
    end,
    -- Fire-control settings of one cannon (by unit number); nil keeps a value.
    set_auto = function(unit_number, mode, ammo, reserve)
        local cannon = storage.cannons[unit_number]
        if not cannon then return false end
        cannon.auto.mode = mode or cannon.auto.mode
        cannon.auto.ammo = ammo or cannon.auto.ammo
        cannon.auto.reserve = reserve or cannon.auto.reserve
        refresh_defending()
        refresh_auto_guis(unit_number)
        return true
    end,
    -- Tests only: the headless benchmark mode never charts anything.
    set_ignore_chart = function(value)
        storage.ignore_chart = value and true or nil
    end,
})

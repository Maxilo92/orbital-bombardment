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
--                     objects = {LuaRenderObject}, label = LuaRenderObject, label_key}
-- storage.guis       [player_index] = unit_number of the cannon whose window is open
-- storage.selected   [player_index] = ammo the player's designator marks targets for
-- storage.selectors  [player_index] = true while the ammo bar is shown
-- storage.rng        LuaRandomGenerator for where cluster bomblets land
-- storage.scheduled  array of things to do on a given tick, {tick, kind, ...}:
--                    "fall" (a bomblet), "emp", "lightning" and "enable" (an
--                    entity the EMP switched off)
local function init_storage()
    storage.cannons = storage.cannons or {}
    storage.targets = storage.targets or {}
    storage.guis = storage.guis or {}
    storage.selected = storage.selected or {}
    storage.selectors = storage.selectors or {}
    storage.rng = storage.rng or game.create_random_generator()
    storage.scheduled = storage.scheduled or {}
    -- Targets from 0.3 and earlier knew only one round.
    for _, target in pairs(storage.targets) do
        target.ammo = target.ammo or shared.AMMO_ORDER[1]
    end
end

local function register(entity)
    if entity and entity.valid and entity.name == CANNON and not storage.cannons[entity.unit_number] then
        storage.cannons[entity.unit_number] = {entity = entity, ready_tick = 0}
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
-- nil and the reason none can: "no-cannon", "no-ammo" or "reloading".
local function pick_cannon(force_index, planet, ammo, tick)
    local reason = "no-cannon"
    for id, cannon in pairs(storage.cannons) do
        local entity = cannon.entity
        if not entity.valid then
            storage.cannons[id] = nil
        elseif entity.force.index == force_index and orbit_of(entity) == planet then
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

local function update_label(target, tick)
    local label = target.label
    if not (label and label.valid) then return end
    local text, key
    if target.state == "inbound" then
        local seconds = math.max(0, math.ceil((target.impact_tick - tick) / 60))
        key = "in" .. seconds
        text = {"orbital-bombardment.marker-inbound", seconds}
    else
        key = "q" .. target.reason
        text = {"orbital-bombardment.marker-queued",
            {"orbital-bombardment.reason-" .. target.reason, "[item=" .. target.ammo .. "]"}}
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
            target = target.position,
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
            target = target.position,
            surface = surface,
            forces = forces,
            draw_on_ground = true,
        }
        -- A blinking bullseye at ground zero.
        objects[#objects + 1] = rendering.draw_circle{
            color = LINE_INBOUND,
            radius = 1.2,
            filled = true,
            target = target.position,
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
            target = target.position,
            surface = surface,
            forces = forces,
            draw_on_ground = true,
        }
    end
    -- The round's icon in front of the label, so mixed targets stay apart.
    target.label = rendering.draw_text{
        text = "",
        surface = surface,
        target = {x = target.position.x, y = target.position.y - target.radius - 1},
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
        target = {x = target.position.x, y = target.position.y - target.radius - 3.2},
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
    local stack = ammo_stack(entity, target.ammo)
    if stack.count > 1 then
        stack.count = stack.count - 1
    else
        stack.clear()
    end
    cannon.ready_tick = tick + shared.RELOAD_TICKS

    local surface = entity.surface
    -- The vanilla flash is an oriented explosion and needs a direction: the
    -- barrel points out into space, straight up the screen.
    local x, y = entity.position.x, entity.position.y
    surface.create_entity{name = "orbital-cannon-muzzle-flash", position = {x, y - 1.5}, target = {x, y - 10}}
    surface.play_sound{path = "orbital-cannon-fire", position = entity.position}

    target.state = "inbound"
    -- Impact lands on the processing grid, so the fall starts exactly
    -- FALL_TICKS before it and the map flash goes off on the impact tick.
    target.impact_tick = math.ceil((tick + shared.FLIGHT_TICKS) / UPDATE_INTERVAL) * UPDATE_INTERVAL
    draw_markers(target, tick)
end

-- A falling body covers FALL_HEIGHT tiles in FALL_TICKS - far too fast to see
-- as an object. What is seen is the streak explosion, whose head reaches the
-- ground in the same ten ticks. Neither is drawn on the map, so the streak is
-- drawn there as well (render_mode "chart"), started on its first frame.
local STREAK_SPEED, STREAK_FRAMES = 0.4, 16 -- as in prototypes/strike.lua

local function spawn_fall(surface, position, strike, force, tick, small)
    surface.create_entity{
        name = strike,
        position = {x = position.x, y = position.y - shared.FALL_HEIGHT},
        target = position,
        speed = shared.FALL_HEIGHT / shared.FALL_TICKS,
        force = force,
    }
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

local function schedule(tick, kind, data)
    data.tick = tick
    data.kind = kind
    storage.scheduled[#storage.scheduled + 1] = data
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
        if ammo.emp then
            schedule(tick + shared.FALL_TICKS, "emp", {
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
-- mechanic - starts on a few victims and jumps on from enemy to enemy. One
-- bolt comes down on ground zero.
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
            entity.damage(shared.EMP_DAMAGE, force, "electric")
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

    for _ = 1, shared.EMP_LIGHTNING do
        schedule(tick + storage.rng(0, 6), "lightning", {
            surface_index = event.surface_index,
            position = random_in_disc(center, 2, true),
        })
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
            elseif event.kind == "lightning" and surface then
                -- Not execute_lightning: that needs the surface's own storm
                -- generator and throws everywhere but Fulgora. Creating the
                -- lightning entity directly works on any planet.
                surface.create_entity{name = "lightning", position = event.position}
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

-- Queued targets fire oldest first, one per ready cannon.
local function fire_queued(tick)
    for _, target in ipairs(storage.targets) do
        if target.state == "queued" then
            local cannon, reason = pick_cannon(target.force_index, target.planet, target.ammo, tick)
            if cannon then
                fire(cannon, target, tick)
            elseif reason ~= target.reason then
                target.reason = reason
                update_label(target, tick)
            end
        end
    end
end

local function process_targets(tick)
    local targets = storage.targets
    for i = #targets, 1, -1 do
        local target = targets[i]
        local surface = game.surfaces[target.surface_index]
        if not surface then
            destroy_markers(target)
            table.remove(targets, i)
        elseif target.state == "inbound" then
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

    fire_queued(tick)
end

--------------------------------------------------------------------------------
-- marking and cancelling targets
--------------------------------------------------------------------------------

-- Queues a strike with `ammo`. Returns the target, or nil and a localised
-- reason why not. `ignore_chart` exists for headless tests only: the benchmark
-- mode they run in never charts anything.
local function order_strike(force, surface, position, tick, ammo, ignore_chart)
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
    if not ignore_chart and not force.is_chunk_charted(surface, chunk) then
        return nil, {"orbital-bombardment.error-uncharted"}
    end
    if not has_cannon_over(force.index, planet.name) then
        return nil, {"orbital-bombardment.error-no-cannon", planet.prototype.localised_name}
    end
    local queued = 0
    for _, other in pairs(storage.targets) do
        if other.force_index == force.index and other.planet == planet.name and other.state == "queued" then
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
    }
    storage.targets[#storage.targets + 1] = target
    draw_markers(target, tick)
    -- Fire straight away if a cannon is ready instead of waiting for the next
    -- pass - but through the queue, so older targets still go first.
    fire_queued(tick)
    return target
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
local function selected_ammo(player)
    local selected = storage.selected[player.index]
    if selected and shared.AMMO[selected] and is_unlocked(player.force, selected) then
        return selected
    end
    return unlocked_ammo(player.force)[1] or shared.AMMO_ORDER[1]
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
        button.number = planet and (counts[ammo] or 0) or nil
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
    for _, ammo in ipairs(ammo_list) do
        buttons.add{
            type = "sprite-button",
            style = "slot_button",
            sprite = "item/" .. ammo,
            tooltip = {"", "[font=default-bold]", {"item-name." .. ammo}, "[/font]\n", {"item-description." .. ammo}},
            tags = {orbital_ammo = ammo},
        }
    end
    -- Top centre, below where the vanilla alerts and research sit.
    local scale = player.display_scale
    local width = (#ammo_list * 40 + 24) * scale
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
    storage.guis[player.index] = entity.unit_number
    update_gui(player, tick)
end

--------------------------------------------------------------------------------
-- events
--------------------------------------------------------------------------------

script.on_init(function()
    init_storage()
    rescan_cannons()
end)

script.on_configuration_changed(function()
    init_storage()
    rescan_cannons()
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

-- Bomblets, lightning and re-enabling worms need tick precision; the 10-tick
-- pass above does not. Nothing to do on almost every tick.
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
    local ammo = element.valid and element.tags and element.tags.orbital_ammo
    if not ammo then return end
    local player = game.get_player(event.player_index)
    if not player then return end
    storage.selected[player.index] = ammo
    update_selector(player)
end)

script.on_event(defines.events.on_player_selected_area, function(event)
    if event.item ~= DESIGNATOR then return end
    local player = game.get_player(event.player_index)
    if not player then return end
    local target, err = order_strike(player.force, event.surface, area_center(event.area), event.tick, selected_ammo(player))
    if not target then notify(player, err) end
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
-- options.ammo picks the round (default: the first in shared.AMMO_ORDER);
-- options.ignore_chart skips the charted-area check (see order_strike).
remote.add_interface("orbital-bombardment", {
    order_strike = function(force, surface, position, options)
        force = game.forces[force]
        surface = game.surfaces[surface]
        if not (force and surface and position) then return false, "invalid arguments" end
        options = options or {}
        local target, err = order_strike(force, surface, position, game.tick,
            options.ammo or shared.AMMO_ORDER[1], options.ignore_chart or false)
        return target ~= nil, err
    end,
})

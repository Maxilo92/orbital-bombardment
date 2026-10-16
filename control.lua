local shared = require("shared")

local CANNON = shared.CANNON
local DESIGNATOR = shared.DESIGNATOR
local UPDATE_INTERVAL = 10
local REENTRY_SOUND_TICKS = 75 -- the roar is 1.25 s long and ends on the impact
local GUI_NAME = "orbital_cannon_status"

-- Render colours are premultiplied (rgb already scaled by alpha).
local LINE_QUEUED = {r = 0.85, g = 0.65, b = 0.1, a = 0.85}
local LINE_INBOUND = {r = 0.9, g = 0.12, b = 0.05, a = 0.9}
local FILL_INBOUND = {r = 0.1, g = 0.012, b = 0.008, a = 0.1}
local TEXT_QUEUED = {r = 1, g = 0.82, b = 0.3}
local TEXT_INBOUND = {r = 1, g = 0.35, b = 0.25}

--------------------------------------------------------------------------------
-- storage
--------------------------------------------------------------------------------

-- storage.cannons  [unit_number] = {entity = LuaEntity, ready_tick = uint}
-- storage.targets  array, oldest first, of
--                  {force_index, surface_index, planet, position, state = "queued" | "inbound",
--                   reason, strike, radius, impact_tick, sound_played, fall_spawned,
--                   objects = {LuaRenderObject}, label = LuaRenderObject, label_key}
-- storage.guis     [player_index] = unit_number of the cannon whose window is open
local function init_storage()
    storage.cannons = storage.cannons or {}
    storage.targets = storage.targets or {}
    storage.guis = storage.guis or {}
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

local function ammo_stack(entity)
    local inventory = entity.get_inventory(defines.inventory.artillery_turret_ammo)
    if not inventory then return nil end
    for i = 1, #inventory do
        local stack = inventory[i]
        if stack.valid_for_read and shared.AMMO[stack.name] then return stack end
    end
    return nil
end

-- A cannon of `force` parked over `planet` that can fire right now, or nil and
-- the reason none can: "no-cannon", "no-ammo" or "reloading".
local function pick_cannon(force_index, planet, tick)
    local reason = "no-cannon"
    for id, cannon in pairs(storage.cannons) do
        local entity = cannon.entity
        if not entity.valid then
            storage.cannons[id] = nil
        elseif entity.force.index == force_index and orbit_of(entity) == planet then
            if not ammo_stack(entity) then
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
        text = {"orbital-bombardment.marker-queued", {"orbital-bombardment.reason-" .. target.reason}}
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
    target.label = rendering.draw_text{
        text = "",
        surface = surface,
        target = {x = target.position.x, y = target.position.y - target.radius - 1},
        color = inbound and TEXT_INBOUND or TEXT_QUEUED,
        scale = 3,
        alignment = "center",
        vertical_alignment = "bottom",
        forces = forces,
    }
    objects[#objects + 1] = target.label
    update_label(target, tick)
end

--------------------------------------------------------------------------------
-- firing
--------------------------------------------------------------------------------

local function fire(cannon, target, tick)
    local entity = cannon.entity
    local stack = ammo_stack(entity)
    local ammo = shared.AMMO[stack.name]
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
    target.strike = ammo.strike
    target.radius = ammo.radius
    target.impact_tick = tick + shared.FLIGHT_TICKS
    draw_markers(target, tick)
end

-- The rod appears FALL_HEIGHT tiles north of the target and drops straight down
-- the screen, arriving FALL_TICKS later.
local function spawn_rod(target, surface)
    local position = target.position
    surface.create_entity{
        name = target.strike,
        position = {x = position.x, y = position.y - shared.FALL_HEIGHT},
        target = position,
        speed = shared.FALL_HEIGHT / shared.FALL_TICKS,
        force = game.forces[target.force_index],
    }
    surface.play_sound{path = "orbital-sonic-boom", position = position}
    target.fall_spawned = true
end

-- Queued targets fire oldest first, one per ready cannon.
local function fire_queued(tick)
    for _, target in ipairs(storage.targets) do
        if target.state == "queued" then
            local cannon, reason = pick_cannon(target.force_index, target.planet, tick)
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
                spawn_rod(target, surface)
            end
            if tick >= target.impact_tick + UPDATE_INTERVAL then
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

-- Queues a strike. Returns the target, or nil and a localised reason why not.
-- `ignore_chart` exists for headless tests only: the benchmark mode they run in
-- never charts anything.
local function order_strike(force, surface, position, tick, ignore_chart)
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
        state = "queued",
        reason = "no-cannon",
        radius = shared.AMMO["tungsten-penetrator"].radius,
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
    if not ammo_stack(entity) then
        lines[2] = {"orbital-bombardment.status-no-ammo"}
    elseif cannon.ready_tick > tick then
        lines[2] = {"orbital-bombardment.status-reloading", math.ceil((cannon.ready_tick - tick) / 60)}
    else
        lines[2] = {"orbital-bombardment.status-ready"}
    end
    local queued, inbound = 0, 0
    if planet then
        for _, target in pairs(storage.targets) do
            if target.force_index == entity.force.index and target.planet == planet then
                if target.state == "queued" then queued = queued + 1 else inbound = inbound + 1 end
            end
        end
    end
    lines[3] = {"orbital-bombardment.status-targets", queued, inbound}
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
    for i = 1, 3 do
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
end)

local BUILT_FILTER = {{filter = "name", name = CANNON}}
local function on_built(event) register(event.entity) end
script.on_event(defines.events.on_built_entity, on_built, BUILT_FILTER)
script.on_event(defines.events.on_robot_built_entity, on_built, BUILT_FILTER)
script.on_event(defines.events.on_space_platform_built_entity, on_built, BUILT_FILTER)
script.on_event(defines.events.script_raised_built, on_built, BUILT_FILTER)
script.on_event(defines.events.script_raised_revive, on_built, BUILT_FILTER)

script.on_event(defines.events.on_player_selected_area, function(event)
    if event.item ~= DESIGNATOR then return end
    local player = game.get_player(event.player_index)
    if not player then return end
    local target, err = order_strike(player.force, event.surface, area_center(event.area), event.tick)
    if not target then notify(player, err) end
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
-- options.ignore_chart skips the charted-area check (see order_strike).
remote.add_interface("orbital-bombardment", {
    order_strike = function(force, surface, position, options)
        force = game.forces[force]
        surface = game.surfaces[surface]
        if not (force and surface and position) then return false, "invalid arguments" end
        local ignore_chart = options and options.ignore_chart or false
        local target, err = order_strike(force, surface, position, game.tick, ignore_chart)
        return target ~= nil, err
    end,
})

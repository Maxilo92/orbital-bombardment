-- The target designator: a selection tool used from remote view of the planet
-- below. Click or drag to mark a target (the centre of the box is where the
-- strike lands); shift-drag to cancel marked targets that have not been fired
-- yet. Spawned from the shortcut bar like the vanilla artillery remote.

local shared = require("shared")

local ICON_TINT = {r = 1, g = 0.55, b = 0.4}

local designator = {
    type = "selection-tool",
    name = shared.DESIGNATOR,
    icons = {{icon = "__base__/graphics/icons/artillery-targeting-remote.png", tint = ICON_TINT}},
    flags = {"only-in-cursor", "not-stackable", "spawnable"},
    auto_recycle = false,
    subgroup = "spawnables",
    order = "b[turret]-d[artillery-turret]-c[orbital-designator]",
    stack_size = 1,
    select = {
        border_color = {r = 1, g = 0.25, b = 0.15},
        cursor_box_type = "not-allowed",
        mode = {"nothing"},
    },
    alt_select = {
        border_color = {r = 1, g = 0.8, b = 0.2},
        cursor_box_type = "copy",
        mode = {"nothing"},
    },
}

local shortcut = {
    type = "shortcut",
    name = "give-" .. shared.DESIGNATOR,
    order = "e[spidertron-remote]-b[orbital]",
    action = "spawn-item",
    item_to_spawn = shared.DESIGNATOR,
    technology_to_unlock = shared.TECHNOLOGY,
    unavailable_until_unlocked = true,
    icons = {{icon = "__base__/graphics/icons/shortcut-toolbar/mip/artillery-targeting-remote-x56.png", icon_size = 56, tint = ICON_TINT}},
    small_icons = {{icon = "__base__/graphics/icons/shortcut-toolbar/mip/artillery-targeting-remote-x24.png", icon_size = 24, tint = ICON_TINT}},
}

data:extend({designator, shortcut})

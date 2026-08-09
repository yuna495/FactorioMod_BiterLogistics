local constants = require("constants")
local state = require("scripts.state")
local nests = require("scripts.nests")
local carriers = require("scripts.carriers")
local cleanup = require("scripts.cleanup")
local gui = require("scripts.gui")
local debug = require("scripts.debug")

local function initialise()
  state.get()
  nests.rescan()
  carriers.validate()
end

script.on_init(initialise)
script.on_configuration_changed(initialise)
script.on_load(function() end)

for _, event_name in pairs({
  defines.events.on_built_entity,
  defines.events.on_robot_built_entity,
  defines.events.script_raised_built,
  defines.events.script_raised_revive,
  defines.events.on_space_platform_built_entity
}) do
  script.on_event(event_name, cleanup.on_built)
end

for _, event_name in pairs({
  defines.events.on_pre_player_mined_item,
  defines.events.on_robot_pre_mined,
  defines.events.script_raised_destroy,
  defines.events.on_entity_died,
  defines.events.on_space_platform_pre_mined
}) do
  script.on_event(event_name, cleanup.on_removed)
end

script.on_event(defines.events.on_entity_cloned, cleanup.on_entity_cloned)
script.on_event(defines.events.on_object_destroyed, cleanup.on_object_destroyed)
script.on_event(defines.events.on_ai_command_completed, carriers.on_ai_command_completed)

script.on_event(defines.events.on_gui_opened, gui.on_opened)
script.on_event(defines.events.on_gui_closed, gui.on_closed)
script.on_event(defines.events.on_gui_text_changed, gui.on_text_changed)
script.on_event(defines.events.on_gui_selection_state_changed, gui.on_selection_state_changed)

script.on_nth_tick(constants.ticks.nest_update_interval, function()
  nests.process_batch(carriers.spawn_from_nest, carriers.wake_for_nest)
end)

script.on_nth_tick(constants.ticks.carrier_update_interval, function()
  carriers.process_batch()
end)

debug.register_commands()

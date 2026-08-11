local constants = require("constants")
local state = require("scripts.state")
local nests = require("scripts.nests")
local depots = require("scripts.depots")
local carriers = require("scripts.carriers")
local cleanup = require("scripts.cleanup")
local gui = require("scripts.gui")
local debug = require("scripts.debug")
local research = require("scripts.research")
local jobs = require("scripts.jobs")
local logistics = require("scripts.logistics")
local range_visuals = require("scripts.range_visuals")
local diagnostics = require("scripts.diagnostics")
local biomass_loot = require("scripts.biomass_loot")

local function event_entity(event)
  return event.created_entity or event.entity or event.destination
end

local function is_visual_entity(entity)
  return entity
    and entity.valid
    and (entity.name == constants.nest_entity or entity.name == constants.depot_entity)
end

local function initialise()
  state.get()
  range_visuals.destroy_all()
  research.rebuild_all(false)
  nests.rescan()
  depots.rescan()
  carriers.validate()
  jobs.cleanup_orphaned()
  jobs.rebuild_reservations()
  research.rebuild_all(true)
  logistics.enqueue_all_requests()
  range_visuals.refresh_all_players()
end

script.on_init(initialise)
script.on_configuration_changed(initialise)
script.on_load(function() end)

local function on_built(event)
  local entity = event_entity(event)
  cleanup.on_built(event)
  if is_visual_entity(entity) then
    range_visuals.refresh_all_players()
  end
end

for _, event_name in pairs({
  defines.events.on_built_entity,
  defines.events.on_robot_built_entity,
  defines.events.script_raised_built,
  defines.events.script_raised_revive,
  defines.events.on_space_platform_built_entity
}) do
  script.on_event(event_name, on_built)
end

local function on_removed(event)
  local entity = event_entity(event)
  local refresh = is_visual_entity(entity)
  if event.name == defines.events.on_entity_died then
    biomass_loot.on_entity_died(event)
    carriers.on_entity_died(event)
  end
  cleanup.on_removed(event)
  if refresh then
    range_visuals.refresh_all_players()
  end
end

for _, event_name in pairs({
  defines.events.on_pre_player_mined_item,
  defines.events.on_robot_pre_mined,
  defines.events.script_raised_destroy,
  defines.events.on_entity_died,
  defines.events.on_space_platform_pre_mined
}) do
  script.on_event(event_name, on_removed)
end

local function on_entity_cloned(event)
  cleanup.on_entity_cloned(event)
  if is_visual_entity(event.destination) then
    range_visuals.refresh_all_players()
  end
end

script.on_event(defines.events.on_entity_cloned, on_entity_cloned)

local function on_object_destroyed(event)
  cleanup.on_object_destroyed(event)
  range_visuals.refresh_all_players()
end

script.on_event(defines.events.on_object_destroyed, on_object_destroyed)
script.on_event(defines.events.on_ai_command_completed, carriers.on_ai_command_completed)
script.on_event(
  defines.events.on_entity_damaged,
  carriers.on_entity_damaged,
  {{filter = "name", name = constants.carrier_unit}}
)
local function on_research_changed(event)
  research.on_research_changed(event)
  if event.research and event.research.valid then
    nests.invalidate_circuit_cache_for_force(event.research.force.name)
  end
  logistics.enqueue_all_requests()
  range_visuals.refresh_all_players()
end

local function on_technology_effects_reset(event)
  research.on_technology_effects_reset(event)
  if event.force and event.force.valid then
    nests.invalidate_circuit_cache_for_force(event.force.name)
  end
  logistics.enqueue_all_requests()
  range_visuals.refresh_all_players()
end

script.on_event(defines.events.on_research_finished, on_research_changed)
if defines.events.on_research_reversed then
  script.on_event(defines.events.on_research_reversed, on_research_changed)
end
script.on_event(defines.events.on_technology_effects_reset, on_technology_effects_reset)

local function on_gui_opened(event)
  gui.on_opened(event)
  if event.player_index then
    range_visuals.refresh_player_index(event.player_index)
  end
end

script.on_event(defines.events.on_gui_opened, on_gui_opened)
script.on_event(defines.events.on_gui_closed, gui.on_closed)
script.on_event(defines.events.on_gui_text_changed, gui.on_text_changed)
script.on_event(defines.events.on_gui_selection_state_changed, gui.on_selection_state_changed)
script.on_event(defines.events.on_gui_elem_changed, gui.on_elem_changed)
script.on_event(defines.events.on_gui_checked_state_changed, gui.on_checked_state_changed)

script.on_event(defines.events.on_selected_entity_changed, function(event)
  range_visuals.refresh_player_index(event.player_index)
end)

script.on_event(defines.events.on_player_cursor_stack_changed, function(event)
  range_visuals.refresh_player_index(event.player_index)
end)

script.on_event(defines.events.on_player_changed_surface, function(event)
  range_visuals.refresh_player_index(event.player_index)
end)

script.on_event(defines.events.on_player_changed_force, function(event)
  range_visuals.refresh_player_index(event.player_index)
end)

script.on_event(defines.events.on_player_left_game, function(event)
  range_visuals.destroy_player(event.player_index)
end)

script.on_nth_tick(constants.ticks.nest_update_interval, function()
  nests.process_batch(logistics.enqueue_request)
  depots.process_batch(carriers.spawn_from_depot, logistics.enqueue_all_requests)
  logistics.process_batch(carriers.assign_job, carriers.on_dispatch_failure)
end)

script.on_nth_tick(constants.ticks.carrier_update_interval, function()
  carriers.process_batch()
end)

script.on_nth_tick(constants.ticks.range_visual_update_interval, function()
  range_visuals.refresh_all_players()
end)

script.on_nth_tick(constants.ticks.diagnostic_alert_update_interval, function()
  diagnostics.process_alerts()
end)

debug.register_commands()

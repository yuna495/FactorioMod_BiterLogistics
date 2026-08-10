local constants = require("constants")
local state = require("scripts.state")
local networks = require("scripts.networks")
local visuals = require("scripts.visuals")

local range_visuals = {}

local function valid_entity(entity)
  return entity and entity.valid
end

local function player_state(data, player_index)
  data.players[player_index] = data.players[player_index] or {}
  local player_data = data.players[player_index]
  player_data.range_render_object_ids = player_data.range_render_object_ids or {}
  return player_data
end

local function render_object(object_id)
  if not object_id then return nil end
  return rendering.get_object_by_id(object_id)
end

local function destroy_object(object_id)
  local object = render_object(object_id)
  if not object then return end
  pcall(function()
    if object.valid ~= false then
      object.destroy()
    end
  end)
end

local function clear_player_objects(player_index)
  local data = state.get()
  local player_data = player_state(data, player_index)
  for _, object_id in ipairs(player_data.range_render_object_ids) do
    destroy_object(object_id)
  end
  player_data.range_render_object_ids = {}
end

local function remember_object(player_index, object)
  if not object then return end
  local player_data = player_state(state.get(), player_index)
  player_data.range_render_object_ids[#player_data.range_render_object_ids + 1] = object.id
end

local function circle_color()
  local color = visuals.color_for("depot")
  return {
    r = color.r,
    g = color.g,
    b = color.b,
    a = constants.visuals.range_alpha
  }
end

local function draw_circle(player, target, surface, radius)
  if not player or not player.valid or not surface or not radius then return nil end

  return rendering.draw_circle{
    color = circle_color(),
    radius = radius,
    width = constants.visuals.range_width,
    filled = false,
    target = target,
    surface = surface,
    players = {player},
    draw_on_ground = true,
    time_to_live = constants.ticks.range_visual_update_interval + 10
  }
end

local function player_matches_record(player, record)
  return player and player.valid
    and record
    and record.force_name == player.force.name
    and record.surface_index == player.surface.index
end

local function draw_depot_range(player, depot)
  if not player_matches_record(player, depot) or not valid_entity(depot.entity) then return end
  local object = draw_circle(player, depot.entity, depot.entity.surface, networks.depot_range(depot))
  remember_object(player.index, object)
end

local function held_item_name(player)
  local stack = player.cursor_stack
  if stack and stack.valid_for_read then
    return stack.name
  end
  return nil
end

local function scoped_depots(player, data)
  local depot_records = {}

  for _, depot in pairs(data.depots) do
    if player_matches_record(player, depot) and valid_entity(depot.entity) then
      depot_records[#depot_records + 1] = depot
    end
  end

  table.sort(depot_records, function(a, b)
    return a.id < b.id
  end)

  return depot_records
end

local function should_draw_visible_depots(player)
  local item_name = held_item_name(player)
  if item_name == constants.depot_item or item_name == constants.nest_item then
    return true
  end
  return valid_entity(player.selected)
    and (player.selected.name == constants.depot_entity or player.selected.name == constants.nest_entity)
end

local function draw_visible_depot_ranges(player, data)
  if not should_draw_visible_depots(player) then return end
  for _, depot in ipairs(scoped_depots(player, data)) do
    draw_depot_range(player, depot)
  end
end

function range_visuals.refresh_player(player)
  if not player or not player.valid then return end
  clear_player_objects(player.index)

  local data = state.get()
  draw_visible_depot_ranges(player, data)
end

function range_visuals.refresh_player_index(player_index)
  local player = game.get_player(player_index)
  if not player then
    clear_player_objects(player_index)
    return
  end
  range_visuals.refresh_player(player)
end

function range_visuals.refresh_all_players()
  for _, player in pairs(game.connected_players) do
    range_visuals.refresh_player(player)
  end
end

function range_visuals.destroy_player(player_index)
  clear_player_objects(player_index)
end

function range_visuals.destroy_all()
  local data = state.get()
  for player_index in pairs(data.players) do
    clear_player_objects(player_index)
  end
end

return range_visuals

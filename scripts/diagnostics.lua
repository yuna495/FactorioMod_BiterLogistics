local constants = require("constants")
local state = require("scripts.state")

local diagnostics = {}

local function copy_position(position)
  if not position then return nil end
  return {x = position.x, y = position.y}
end

local function record_label(kind, record)
  if not record then return "-" end
  local prefix = kind == "depot" and "Depot" or "Nest"
  if record.display_name and record.display_name ~= "" then
    return record.display_name .. " #" .. record.id
  end
  return prefix .. " #" .. record.id
end

local function gps(record)
  if not record or not record.position then return "" end
  local surface = record.entity and record.entity.valid and record.entity.surface.name or nil
  surface = surface or (record.surface_index and game.get_surface(record.surface_index) and game.get_surface(record.surface_index).name)
  if not surface then return "" end
  return string.format("[gps=%.1f,%.1f,%s]", record.position.x, record.position.y, surface)
end

local function item_caption(item_name)
  if not item_name then return "-" end
  return "[item=" .. item_name .. "]"
end

local function alert_icon(kind)
  if kind == "food-shortage" then
    return {type = "item", name = constants.depot_item}
  end
  if kind == "pathfinding-failed" then
    return {type = "item", name = constants.carrier_item}
  end
  return {type = "item", name = constants.nest_item}
end

local function alert_to_force(force_name, surface_index, entity, icon, message)
  if not force_name or not entity or not entity.valid then return end
  for _, player in pairs(game.connected_players) do
    if player.force.name == force_name and (not surface_index or player.surface_index == surface_index) then
      player.add_custom_alert(entity, icon, message, true)
    end
  end
end

local function alert_filter(record)
  local filter = {
    type = defines.alert_type.custom,
    icon = record.icon,
    message = record.message
  }
  if record.entity and record.entity.valid then
    filter.entity = record.entity
  else
    filter.prototype = record.prototype
    filter.position = record.position
    filter.surface = record.surface_index
  end
  return filter
end

local function remove_alert_from_force(record)
  if not record or not record.force_name then return end
  for _, player in pairs(game.players) do
    if player.force.name == record.force_name
      and (not record.surface_index or player.surface_index == record.surface_index) then
      player.remove_alert(alert_filter(record))
    end
  end
end

local function clear_key(diagnostics_state, key)
  local record = diagnostics_state.active_alerts and diagnostics_state.active_alerts[key]
  if not record then return end
  remove_alert_from_force(record)
  diagnostics_state.active_alerts[key] = nil
  if diagnostics_state.last_messages then
    diagnostics_state.last_messages[key] = nil
  end
end

local function clear_matching(predicate)
  local data = state.get()
  local diagnostics_state = data.diagnostics
  diagnostics_state.active_alerts = diagnostics_state.active_alerts or {}
  for key, record in pairs(diagnostics_state.active_alerts) do
    if predicate(record) then
      clear_key(diagnostics_state, key)
    end
  end
end

local function key_for(kind, parts)
  local key = kind
  for _, part in ipairs(parts or {}) do
    key = key .. "|" .. tostring(part or "-")
  end
  return key
end

local function stable_value_key(value)
  if type(value) ~= "table" then return tostring(value) end
  local parts = {"{"}
  for index = 1, #value do
    parts[#parts + 1] = stable_value_key(value[index])
    parts[#parts + 1] = "|"
  end
  parts[#parts + 1] = "}"
  return table.concat(parts)
end

function diagnostics.notify(kind, scope, message, key_parts, metadata)
  if not scope then return end
  local data = state.get()
  local diagnostics_state = data.diagnostics
  diagnostics_state.last_messages = diagnostics_state.last_messages or {}
  diagnostics_state.active_alerts = diagnostics_state.active_alerts or {}

  local key = key_for(kind, key_parts)
  local message_key = stable_value_key(message)
  local previous = diagnostics_state.active_alerts[key]
  if previous and previous.message_key and previous.message_key ~= message_key then
    clear_key(diagnostics_state, key)
  end

  local entity = scope.entity
  local icon = alert_icon(kind)
  local active = metadata or {}
  active.kind = kind
  active.force_name = scope.force_name or (entity and entity.valid and entity.force.name) or active.force_name
  active.surface_index = scope.surface_index or (entity and entity.valid and entity.surface_index) or active.surface_index
  active.entity = entity
  active.prototype = entity and entity.valid and entity.name or active.prototype
  active.position = copy_position((entity and entity.valid and entity.position) or scope.position or active.position)
  active.icon = icon
  active.message = message
  active.message_key = message_key
  active.last_seen_tick = game.tick
  diagnostics_state.active_alerts[key] = active

  local last_tick = diagnostics_state.last_messages[key]
  local cooldown = constants.ticks.diagnostic_message_cooldown
  if last_tick and game.tick - last_tick < cooldown then return end

  diagnostics_state.last_messages[key] = game.tick
  alert_to_force(active.force_name, active.surface_index, active.entity, icon, message)
end

function diagnostics.request_full(request, item_name)
  diagnostics.notify(
    "request-full",
    request,
    {
      "diagnostic.biter-logistics-request-full",
      record_label("nest", request),
      gps(request),
      item_caption(item_name)
    },
    {request and request.id, item_name},
    {request_id = request and request.id, item_name = item_name}
  )
end

function diagnostics.no_supply(request, item_name)
  diagnostics.notify(
    "no-supply",
    request,
    {
      "diagnostic.biter-logistics-no-supply",
      item_caption(item_name),
      record_label("nest", request),
      gps(request)
    },
    {request and request.id, item_name},
    {request_id = request and request.id, item_name = item_name}
  )
end

function diagnostics.supply_out_of_depot_range(request, item_name)
  diagnostics.notify(
    "supply-out-of-range",
    request,
    {
      "diagnostic.biter-logistics-supply-out-of-depot-range",
      item_caption(item_name),
      record_label("nest", request),
      gps(request)
    },
    {request and request.id, item_name},
    {request_id = request and request.id, item_name = item_name}
  )
end

function diagnostics.all_carriers_busy(request, item_name)
  diagnostics.notify(
    "all-carriers-busy",
    request,
    {
      "diagnostic.biter-logistics-all-carriers-busy",
      item_caption(item_name),
      record_label("nest", request),
      gps(request)
    },
    {request and request.id, item_name},
    {request_id = request and request.id, item_name = item_name}
  )
end

function diagnostics.food_shortage(depot, request, item_name)
  diagnostics.notify(
    "food-shortage",
    depot or request,
    {
      "diagnostic.biter-logistics-food-shortage",
      record_label("depot", depot),
      gps(depot),
      item_caption(item_name),
      record_label("nest", request),
      gps(request)
    },
    {depot and depot.id, request and request.id, item_name},
    {depot_id = depot and depot.id, request_id = request and request.id, item_name = item_name}
  )
end

function diagnostics.pathfinding_failed(carrier, target_record, target_kind)
  local scope = carrier or target_record
  diagnostics.notify(
    "pathfinding-failed",
    scope,
    {
      "diagnostic.biter-logistics-pathfinding-failed",
      carrier and carrier.id or "-",
      target_kind or "-",
      record_label(target_kind == "depot" and "depot" or "nest", target_record),
      gps(target_record)
    },
    {carrier and carrier.id, target_kind, target_record and target_record.id},
    {carrier_id = carrier and carrier.id, target_kind = target_kind, target_id = target_record and target_record.id}
  )
end

function diagnostics.destination_waiting(carrier, destination, item_name)
  diagnostics.notify(
    "destination-waiting",
    destination or carrier,
    {
      "diagnostic.biter-logistics-destination-waiting",
      carrier and carrier.id or "-",
      item_caption(item_name),
      record_label("nest", destination),
      gps(destination)
    },
    {destination and destination.id, item_name},
    {carrier_id = carrier and carrier.id, destination_nest_id = destination and destination.id, item_name = item_name}
  )
end

function diagnostics.no_control_combinator(request)
  diagnostics.notify(
    "no-control-combinator",
    request,
    {
      "diagnostic.biter-logistics-no-control-combinator",
      record_label("nest", request),
      gps(request)
    },
    {request and request.id},
    {request_id = request and request.id}
  )
end

function diagnostics.circuit_target_overflow(request, item_name, target, max_capacity)
  diagnostics.notify(
    "circuit-target-overflow",
    request,
    {
      "diagnostic.biter-logistics-circuit-target-overflow",
      record_label("nest", request),
      gps(request),
      item_caption(item_name),
      target or 0,
      max_capacity or 0
    },
    {request and request.id, item_name},
    {
      request_id = request and request.id,
      item_name = item_name,
      target = target or 0,
      max_capacity = max_capacity or 0
    }
  )
end

function diagnostics.clear_for_request(request_id, item_name)
  if not request_id then return end
  clear_matching(function(record)
    return record.request_id == request_id and (not item_name or record.item_name == item_name)
  end)
end

function diagnostics.clear_item_alerts_for_request(request_id)
  if not request_id then return end
  clear_matching(function(record)
    return record.request_id == request_id and record.item_name ~= nil
  end)
end

function diagnostics.clear_no_control_combinator(request_id)
  if not request_id then return end
  clear_matching(function(record)
    return record.kind == "no-control-combinator" and record.request_id == request_id
  end)
end

function diagnostics.clear_circuit_target_overflow(request_id, item_name)
  if not request_id then return end
  clear_matching(function(record)
    return record.kind == "circuit-target-overflow"
      and record.request_id == request_id
      and (not item_name or record.item_name == item_name)
  end)
end

function diagnostics.clear_unseen_for_request(request_id, seen_tick, item_name)
  if not request_id then return end
  clear_matching(function(record)
    return record.request_id == request_id
      and record.last_seen_tick ~= seen_tick
      and (not item_name or record.item_name == item_name)
  end)
end

function diagnostics.clear_for_carrier(carrier_id)
  if not carrier_id then return end
  clear_matching(function(record)
    return record.carrier_id == carrier_id
  end)
end

function diagnostics.clear_destination_waiting(destination_nest_id, item_name)
  if not destination_nest_id then return end
  clear_matching(function(record)
    return record.kind == "destination-waiting"
      and record.destination_nest_id == destination_nest_id
      and (not item_name or record.item_name == item_name)
  end)
end

function diagnostics.process_alerts()
  local data = state.get()
  local diagnostics_state = data.diagnostics
  diagnostics_state.active_alerts = diagnostics_state.active_alerts or {}
  local stale_ticks = constants.ticks.diagnostic_alert_stale_ticks
  for key, record in pairs(diagnostics_state.active_alerts) do
    local stale = not record.last_seen_tick or game.tick - record.last_seen_tick >= stale_ticks
    local invalid_entity = record.entity and not record.entity.valid
    if stale or invalid_entity then
      clear_key(diagnostics_state, key)
    end
  end
end

return diagnostics

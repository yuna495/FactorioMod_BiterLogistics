local constants = require("constants")
local state = require("scripts.state")

local diagnostics = {}

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

local function key_for(kind, parts)
  local key = kind
  for _, part in ipairs(parts or {}) do
    key = key .. "|" .. tostring(part or "-")
  end
  return key
end

function diagnostics.notify(kind, scope, message, key_parts)
  if not scope then return end
  local data = state.get()
  local diagnostics_state = data.diagnostics
  diagnostics_state.last_messages = diagnostics_state.last_messages or {}

  local key = key_for(kind, key_parts)
  local last_tick = diagnostics_state.last_messages[key]
  local cooldown = constants.ticks.diagnostic_message_cooldown
  if last_tick and game.tick - last_tick < cooldown then return end

  diagnostics_state.last_messages[key] = game.tick
  alert_to_force(scope.force_name, scope.surface_index, scope.entity, alert_icon(kind), message)
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
    {request and request.id, item_name}
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
    {request and request.id, item_name}
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
    {request and request.id, item_name}
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
    {request and request.id, item_name}
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
    {depot and depot.id, request and request.id, item_name}
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
    {carrier and carrier.id, target_kind, target_record and target_record.id}
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
    {destination and destination.id, item_name}
  )
end

return diagnostics

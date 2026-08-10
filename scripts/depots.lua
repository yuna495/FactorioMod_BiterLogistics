local constants = require("constants")
local state = require("scripts.state")
local food = require("scripts.food")
local research = require("scripts.research")
local visuals = require("scripts.visuals")
local indexes = require("scripts.indexes")

local depots = {}

local function valid(entity)
  return entity and entity.valid
end

local function copy_position(position)
  return {x = position.x, y = position.y}
end

local function enqueue(data, id)
  if data.depot_queued[id] then return end
  data.depot_queue[#data.depot_queue + 1] = id
  data.depot_queued[id] = true
end

local function dequeue(data, id)
  if not data.depot_queued[id] then return end
  for index, queued_id in ipairs(data.depot_queue) do
    if queued_id == id then
      table.remove(data.depot_queue, index)
      if data.depot_cursor >= index then
        data.depot_cursor = math.max(data.depot_cursor - 1, 0)
      end
      break
    end
  end
  data.depot_queued[id] = nil
end

local function get_inventory(record)
  if not record or not valid(record.entity) then return nil end
  return record.entity.get_inventory(defines.inventory.chest)
end

local function stack_quality_name(stack)
  return stack.quality and stack.quality.name or "normal"
end

function depots.configure_inventory(entity)
  if not valid(entity) then return end
  local inventory = entity.get_inventory(defines.inventory.chest)
  if not inventory or not inventory.supports_filters() then return end

  inventory.set_filter(constants.depot_slots.carrier, {name = constants.carrier_item})
  for slot = constants.depot_slots.food_first, #inventory do
    inventory.set_filter(slot, nil)
  end
end

function depots.register(entity)
  if not valid(entity) or entity.name ~= constants.depot_entity or not entity.unit_number then
    return nil
  end

  local data = state.get()
  local id = data.depot_by_unit_number[entity.unit_number]
  local record = id and data.depots[id] or nil

  if not record then
    id = data.next_depot_id
    data.next_depot_id = id + 1
    record = {
      id = id,
      unit_number = entity.unit_number,
      carrier_ids = {}
    }
    data.depots[id] = record
    data.depot_by_unit_number[entity.unit_number] = id
  end

  record.entity = entity
  record.unit_number = entity.unit_number
  record.force_name = entity.force.name
  record.surface_index = entity.surface_index
  record.position = copy_position(entity.position)
  record.carrier_ids = record.carrier_ids or {}
  indexes.register_depot(record)

  depots.configure_inventory(entity)
  visuals.update_depot(record)

  if not record.destroy_registration_number then
    local registration_number = script.register_on_object_destroyed(entity)
    record.destroy_registration_number = registration_number
    data.destroy_registrations[registration_number] = {type = "depot", id = id}
  end

  enqueue(data, id)
  return record
end

function depots.get(id)
  return state.get().depots[id]
end

function depots.get_by_entity(entity)
  if not valid(entity) or not entity.unit_number then return nil end
  local data = state.get()
  local id = data.depot_by_unit_number[entity.unit_number]
  return id and data.depots[id] or nil
end

function depots.is_valid(record)
  return record and valid(record.entity)
end

function depots.set_display_name(id, display_name)
  local record = depots.get(id)
  if not record then return end
  if display_name == "" then
    record.display_name = nil
  else
    record.display_name = display_name
  end
end

function depots.count_carrier_items(record)
  if not depots.is_valid(record) then return 0 end
  local inventory = get_inventory(record)
  if not inventory then return 0 end
  local stack = inventory[constants.depot_slots.carrier]
  if stack and stack.valid and stack.valid_for_read and stack.name == constants.carrier_item then
    return stack.count
  end
  return 0
end

local function carrier_for_depot(data, record, id)
  local carrier = data.carriers[id]
  if carrier and carrier.home_depot_id == record.id and valid(carrier.entity) then
    return carrier
  end
  record.carrier_ids[id] = nil
  return nil
end

local function count_depot_carriers(record, predicate)
  if not record then return 0 end
  local data = state.get()
  local count = 0
  record.carrier_ids = record.carrier_ids or {}
  for id in pairs(record.carrier_ids) do
    local carrier = carrier_for_depot(data, record, id)
    if carrier and (not predicate or predicate(carrier)) then
      count = count + 1
    end
  end
  return count
end

function depots.assigned_carrier_count(record)
  return count_depot_carriers(record)
end

function depots.active_carrier_count(record)
  return count_depot_carriers(record, function(carrier)
    return carrier.state ~= "idle"
  end)
end

function depots.idle_carrier_count(record)
  return count_depot_carriers(record, function(carrier)
    return carrier.state == "idle" and not carrier.job_id
  end)
end

function depots.carrier_capacity(record)
  local force_name = record and record.force_name or nil
  if not force_name and record and valid(record.entity) then
    force_name = record.entity.force.name
  end
  return math.max(
    constants.research.default_depot_carrier_capacity,
    research.depot_carrier_capacity_for_force_name(force_name)
  )
end

function depots.carrier_capacity_reached(record)
  return depots.assigned_carrier_count(record) >= depots.carrier_capacity(record)
end

local function process_carrier_slot(record, spawn_callback)
  if not depots.is_valid(record) then return end
  local inventory = get_inventory(record)
  if not inventory then return end

  local stack = inventory[constants.depot_slots.carrier]
  if not stack or not stack.valid or not stack.valid_for_read or stack.name ~= constants.carrier_item then return end
  if depots.carrier_capacity_reached(record) then return end

  local quality = stack_quality_name(stack)
  if spawn_callback(record, quality) then
    if stack.count > 1 then
      stack.count = stack.count - 1
    else
      stack.clear()
    end
  end
end

local function best_food_slot(inventory, values, needed)
  local best_over_slot = nil
  local best_over_value = nil
  local best_under_slot = nil
  local best_under_value = nil

  for slot = constants.depot_slots.food_first, #inventory do
    local stack = inventory[slot]
    if stack and stack.valid and stack.valid_for_read then
      local value = values[stack.name] or 0
      if value > 0 then
        if value >= needed then
          if not best_over_value or value < best_over_value then
            best_over_slot = slot
            best_over_value = value
          end
        elseif not best_under_value or value > best_under_value then
          best_under_slot = slot
          best_under_value = value
        end
      end
    end
  end

  if best_over_slot then return best_over_slot, best_over_value end
  return best_under_slot, best_under_value
end

function depots.consume_food(record, carrier_record, target_energy)
  if not depots.is_valid(record) or not carrier_record then return false end
  food.ensure_carrier_fields(carrier_record)
  if carrier_record.food_energy >= target_energy then return true end
  if target_energy > carrier_record.food_capacity then return false end

  local inventory = get_inventory(record)
  if not inventory then return false end
  if carrier_record.food_energy + depots.available_food_energy(record) < target_energy then return false end

  local values = food.values_for_force_name(record.force_name)
  while carrier_record.food_energy < target_energy do
    local needed = target_energy - carrier_record.food_energy
    local slot, value = best_food_slot(inventory, values, needed)
    if not slot or not value then return false end

    local stack = inventory[slot]
    if not stack or not stack.valid or not stack.valid_for_read then return false end

    carrier_record.food_energy = math.min(carrier_record.food_capacity, carrier_record.food_energy + value)
    if stack.count > 1 then
      stack.count = stack.count - 1
    else
      stack.clear()
    end
  end

  return true
end

function depots.available_food_energy(record)
  if not depots.is_valid(record) then return 0 end
  local inventory = get_inventory(record)
  if not inventory then return 0 end
  local values = food.values_for_force_name(record.force_name)
  local total = 0
  for slot = constants.depot_slots.food_first, #inventory do
    local stack = inventory[slot]
    if stack and stack.valid and stack.valid_for_read then
      total = total + (values[stack.name] or 0) * stack.count
    end
  end
  return total
end

function depots.find_idle_carrier(record)
  if not depots.is_valid(record) then return nil end
  local data = state.get()
  record.carrier_ids = record.carrier_ids or {}
  for id in pairs(record.carrier_ids or {}) do
    local carrier = carrier_for_depot(data, record, id)
    if carrier and carrier.state == "idle" and not carrier.job_id then
      food.ensure_carrier_fields(carrier)
      return carrier
    end
  end
  return nil
end

function depots.remove(id)
  local data = state.get()
  local record = data.depots[id]
  if not record then return end

  if record.unit_number then
    data.depot_by_unit_number[record.unit_number] = nil
  end
  if record.destroy_registration_number then
    data.destroy_registrations[record.destroy_registration_number] = nil
  end

  indexes.unregister_depot(record)
  data.depots[id] = nil
  visuals.destroy(record)
  dequeue(data, id)
end

function depots.process_batch(spawn_callback, wake_callback)
  local data = state.get()
  local queue = data.depot_queue
  local length = #queue
  if length == 0 then return end

  local processed = 0
  local examined = 0
  while processed < constants.ticks.depots_per_update and examined < length do
    data.depot_cursor = (data.depot_cursor % length) + 1
    local id = queue[data.depot_cursor]
    local record = id and data.depots[id] or nil
    if record then
      if depots.is_valid(record) then
        depots.configure_inventory(record.entity)
        process_carrier_slot(record, spawn_callback)
        if wake_callback then wake_callback(record) end
      else
        depots.remove(id)
      end
      processed = processed + 1
    end
    examined = examined + 1
  end
end

function depots.rescan()
  local data = state.get()
  indexes.clear_depots()
  for _, surface in pairs(game.surfaces) do
    for _, entity in pairs(surface.find_entities_filtered{name = constants.depot_entity}) do
      depots.register(entity)
    end
  end

  for id, record in pairs(data.depots) do
    if depots.is_valid(record) then
      indexes.register_depot(record)
      depots.configure_inventory(record.entity)
      enqueue(data, id)
    else
      depots.remove(id)
    end
  end
end

return depots

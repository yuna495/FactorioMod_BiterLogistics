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

local function normalise_quality_name(quality)
  if not quality or quality == "" then return "normal" end
  return quality
end

local function stack_definition(name, count, quality)
  local stack = {name = name, count = count or 1}
  quality = normalise_quality_name(quality)
  if quality ~= "normal" then
    stack.quality = quality
  end
  return stack
end

local function carrier_item_stack(quality)
  return stack_definition(constants.carrier_item, 1, quality)
end

local function ensure_hatching(record)
  record.hatching = record.hatching or {}
  return record.hatching
end

local function valid_hatching_entry(entry)
  return type(entry) == "table"
end

local function normalise_hatching_entry(entry, now)
  if not valid_hatching_entry(entry) then return nil end
  entry.start_tick = entry.start_tick or now
  entry.finish_tick = entry.finish_tick or (entry.start_tick + constants.hatching.duration_ticks)
  entry.quality = normalise_quality_name(entry.quality)
  entry.ready = entry.ready or false
  return entry
end

local function hatching_reservation_count(record)
  local count = 0
  for _, entry in ipairs(ensure_hatching(record)) do
    if valid_hatching_entry(entry) then
      count = count + 1
    end
  end
  return count
end

local function stack_matches_quality(stack, quality)
  return stack_quality_name(stack) == normalise_quality_name(quality)
end

local function insert_carrier_item_into_slot(inventory, quality)
  local slot = inventory and inventory[constants.depot_slots.carrier]
  if not slot or not slot.valid then return false end

  if not slot.valid_for_read then
    return slot.set_stack(carrier_item_stack(quality))
  end

  return false
end

local function can_transfer_whole_stack(source, target)
  if not source or not source.valid or not source.valid_for_read then return false end
  if not target or not target.valid then return false end
  if not target.valid_for_read then return true end
  if target.name ~= source.name or not stack_matches_quality(target, stack_quality_name(source)) then
    return false
  end
  local stack_size = target.prototype and target.prototype.stack_size or target.count
  return target.count + source.count <= stack_size
end

local function transfer_whole_stack(source, target)
  if not can_transfer_whole_stack(source, target) then return false end
  local count = source.count
  if not target.transfer_stack(source, count) then return false end
  return not source.valid_for_read
end

local function spill_stack(entity, source)
  if not valid(entity) or not source or not source.valid or not source.valid_for_read then return end
  entity.surface.spill_item_stack{
    position = entity.position,
    stack = source,
    force = entity.force,
    allow_belts = false
  }
  if source.valid_for_read then
    source.clear()
  end
end

local function migrate_depot_inventory_layout(record)
  if not depots.is_valid(record) then return end
  if (record.inventory_layout_version or 1) >= constants.depot_slots.layout_version then return end

  local inventory = get_inventory(record)
  if inventory and #inventory >= constants.depot_slots.egg then
    local source = inventory[constants.depot_slots.egg]
    if source and source.valid and source.valid_for_read and source.name ~= constants.spawner_egg_loot.egg_item then
      local preferred_target = #inventory >= constants.depot_slots.total and inventory[constants.depot_slots.total] or nil
      local moved = transfer_whole_stack(source, preferred_target)

      if not moved then
        for slot = constants.depot_slots.food_first, #inventory do
          local target = inventory[slot]
          if transfer_whole_stack(source, target) then
            moved = true
            break
          end
        end
      end

      if not moved and source.valid_for_read then
        spill_stack(record.entity, source)
      end
    end
  end

  record.inventory_layout_version = constants.depot_slots.layout_version
end

function depots.configure_inventory(entity)
  if not valid(entity) then return end
  local inventory = entity.get_inventory(defines.inventory.chest)
  if not inventory or not inventory.supports_filters() then return end

  if #inventory >= constants.depot_slots.carrier then
    inventory.set_filter(constants.depot_slots.carrier, {name = constants.carrier_item})
  end
  if #inventory >= constants.depot_slots.egg then
    inventory.set_filter(constants.depot_slots.egg, {name = constants.spawner_egg_loot.egg_item})
  end
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
  record.hatching = record.hatching or {}
  indexes.register_depot(record)

  migrate_depot_inventory_layout(record)
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

function depots.hatching_reservation_count(record)
  if not record then return 0 end
  return hatching_reservation_count(record)
end

function depots.hatching_capacity_available(record)
  if not depots.is_valid(record) then return 0 end
  local capacity = depots.carrier_capacity(record)
  local assigned = depots.assigned_carrier_count(record)
  local waiting = depots.count_carrier_items(record)
  local hatching = hatching_reservation_count(record)
  return math.max(0, capacity - assigned - waiting - hatching)
end

function depots.hatching_status(record, now)
  local status = {
    hatching_count = 0,
    ready_count = 0,
    total_count = 0,
    progress = 0
  }
  if not record then return status end

  now = now or game.tick
  local next_entry = nil
  for _, raw_entry in ipairs(ensure_hatching(record)) do
    local entry = normalise_hatching_entry(raw_entry, now)
    if entry then
      status.total_count = status.total_count + 1
      if entry.ready then
        status.ready_count = status.ready_count + 1
      else
        status.hatching_count = status.hatching_count + 1
        if not next_entry or entry.finish_tick < next_entry.finish_tick then
          next_entry = entry
        end
      end
    end
  end

  if next_entry then
    local duration = math.max(1, next_entry.finish_tick - next_entry.start_tick)
    status.progress = math.max(0, math.min(1, (now - next_entry.start_tick) / duration))
  end

  return status
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
  return depots.assigned_carrier_count(record) + hatching_reservation_count(record) >= depots.carrier_capacity(record)
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

local function finish_hatching(record, inventory, now)
  local changed = false
  local remaining = {}

  for _, raw_entry in ipairs(ensure_hatching(record)) do
    local entry = normalise_hatching_entry(raw_entry, now)
    if entry then
      if not entry.ready and entry.finish_tick <= now then
        entry.ready = true
        changed = true
      end

      if entry.ready and insert_carrier_item_into_slot(inventory, entry.quality) then
        changed = true
      else
        remaining[#remaining + 1] = entry
      end
    end
  end

  record.hatching = remaining
  return changed
end

local function start_hatching(record, inventory, now)
  local capacity = depots.hatching_capacity_available(record)
  if capacity <= 0 then return false end
  if #inventory < constants.depot_slots.egg then return false end

  local egg_stack = inventory[constants.depot_slots.egg]
  if not egg_stack
    or not egg_stack.valid
    or not egg_stack.valid_for_read
    or egg_stack.name ~= constants.spawner_egg_loot.egg_item then
    return false
  end

  local count = math.min(capacity, egg_stack.count)
  if count <= 0 then return false end

  local quality = stack_quality_name(egg_stack)
  local finish_tick = now + constants.hatching.duration_ticks
  local hatching = ensure_hatching(record)
  for _ = 1, count do
    hatching[#hatching + 1] = {
      start_tick = now,
      finish_tick = finish_tick,
      quality = quality,
      ready = false
    }
  end

  if egg_stack.count > count then
    egg_stack.count = egg_stack.count - count
  else
    egg_stack.clear()
  end

  return true
end

local function process_hatching(record)
  if not depots.is_valid(record) then return false end
  local inventory = get_inventory(record)
  if not inventory then return false end

  local now = game.tick
  local changed = finish_hatching(record, inventory, now)
  if start_hatching(record, inventory, now) then
    changed = true
  end

  return changed
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
        migrate_depot_inventory_layout(record)
        depots.configure_inventory(record.entity)
        process_hatching(record)
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
      migrate_depot_inventory_layout(record)
      depots.configure_inventory(record.entity)
      enqueue(data, id)
    else
      depots.remove(id)
    end
  end
end

return depots

local constants = require("constants")
local state = require("scripts.state")
local research = require("scripts.research")
local jobs = require("scripts.jobs")
local visuals = require("scripts.visuals")
local indexes = require("scripts.indexes")

local nests = {}

local function valid(entity)
  return entity and entity.valid
end

local function copy_position(position)
  return {x = position.x, y = position.y}
end

local function enqueue(data, id)
  if data.nest_queued[id] then return end
  data.nest_queue[#data.nest_queue + 1] = id
  data.nest_queued[id] = true
end

local function dequeue(data, id)
  if not data.nest_queued[id] then return end
  for index, queued_id in ipairs(data.nest_queue) do
    if queued_id == id then
      table.remove(data.nest_queue, index)
      if data.nest_cursor >= index then
        data.nest_cursor = math.max(data.nest_cursor - 1, 0)
      end
      break
    end
  end
  data.nest_queued[id] = nil
end

local function get_chest_inventory(record)
  if not record or not valid(record.entity) then return nil end
  return record.entity.get_inventory(defines.inventory.chest)
end

local function cargo_slot_last(record, inventory)
  local force_name = record.force_name
  if not force_name and record.entity and record.entity.valid then
    force_name = record.entity.force.name
  end
  local cargo_count = research.nest_cargo_slots_for_force_name(force_name)
  local configured_last = constants.nest_slots.cargo_first + cargo_count - 1
  local bar = inventory.supports_bar() and inventory.get_bar() or (#inventory + 1)
  configured_last = math.min(configured_last, bar - 1)
  return math.min(configured_last, #inventory)
end

local function for_each_cargo_slot(record, callback)
  local inventory = get_chest_inventory(record)
  if not inventory then return nil end

  for slot = constants.nest_slots.cargo_first, cargo_slot_last(record, inventory) do
    local stack = inventory[slot]
    if stack and stack.valid then
      local result = callback(stack, slot, inventory)
      if result ~= nil then return result end
    end
  end

  return nil
end

local function stack_quality_name(stack)
  return stack.quality and stack.quality.name or "normal"
end

local function cargo_quality_name(cargo)
  return cargo.quality or "normal"
end

local function cargo_stack_definition(name, count, quality)
  local stack = {name = name, count = count}
  if quality and quality ~= "normal" then
    stack.quality = quality
  end
  return stack
end

local function stack_matches_cargo(stack, cargo)
  return stack.valid_for_read
    and stack.name == cargo.name
    and stack_quality_name(stack) == cargo_quality_name(cargo)
end

local function item_stack_size(name)
  local prototype = prototypes.item[name]
  return prototype and prototype.stack_size or 0
end

local function insert_into_cargo_slot(stack, cargo)
  if not stack or not stack.valid or not cargo or cargo.count <= 0 then return 0 end

  local inserted = 0
  if stack.valid_for_read then
    if not stack_matches_cargo(stack, cargo) then return 0 end
    inserted = math.min(stack.prototype.stack_size - stack.count, cargo.count)
    if inserted <= 0 then return 0 end
    stack.count = stack.count + inserted
  else
    inserted = math.min(item_stack_size(cargo.name), cargo.count)
    if inserted <= 0 then return 0 end
    if not stack.set_stack(cargo_stack_definition(cargo.name, inserted, cargo_quality_name(cargo))) then
      return 0
    end
  end

  cargo.count = cargo.count - inserted
  if cargo.count <= 0 then
    cargo.count = 0
  end
  return inserted
end

function nests.configure_inventory(entity)
  if not valid(entity) then return end
  research.apply_to_nest_entity(entity)

  local inventory = entity.get_inventory(defines.inventory.chest)
  if not inventory or not inventory.supports_filters() then return end

  for slot = 1, #inventory do
    inventory.set_filter(slot, nil)
  end
end

function nests.register(entity)
  if not valid(entity) or entity.name ~= constants.nest_entity or not entity.unit_number then
    return nil
  end

  local data = state.get()
  local id = data.nest_by_unit_number[entity.unit_number]
  local record = id and data.nests[id] or nil

  if not record then
    id = data.next_nest_id
    data.next_nest_id = id + 1
    record = {
      id = id,
      unit_number = entity.unit_number,
      mode = constants.nest_modes.supply,
      request_quality = "normal"
    }
    data.nests[id] = record
    data.nest_by_unit_number[entity.unit_number] = id
  end

  record.entity = entity
  record.unit_number = entity.unit_number
  record.force_name = entity.force.name
  record.surface_index = entity.surface_index
  record.position = copy_position(entity.position)
  record.mode = record.mode or constants.nest_modes.supply
  record.request_quality = record.request_quality or "normal"
  indexes.register_nest(record)

  nests.configure_inventory(entity)
  visuals.update_nest(record)

  if not record.destroy_registration_number then
    local registration_number = script.register_on_object_destroyed(entity)
    record.destroy_registration_number = registration_number
    data.destroy_registrations[registration_number] = {type = "nest", id = id}
  end

  enqueue(data, id)
  return record
end

function nests.get(id)
  return state.get().nests[id]
end

function nests.get_by_entity(entity)
  if not valid(entity) or not entity.unit_number then return nil end
  local data = state.get()
  local id = data.nest_by_unit_number[entity.unit_number]
  return id and data.nests[id] or nil
end

function nests.is_valid(record)
  return record and valid(record.entity)
end

local function scoped_records_for(record)
  local data = state.get()
  local scoped_records = {}
  if not nests.is_valid(record) then return scoped_records end

  for _, other in pairs(data.nests) do
    if nests.is_valid(other)
      and other.force_name == record.force_name
      and other.surface_index == record.surface_index then
      scoped_records[#scoped_records + 1] = other
    end
  end

  table.sort(scoped_records, function(a, b)
    local a_name = a.display_name or ""
    local b_name = b.display_name or ""
    if a_name ~= b_name then return a_name < b_name end
    return a.id < b.id
  end)

  return scoped_records
end

local function duplicate_indices_for(scoped_records)
  local name_counts = {}
  for _, record in ipairs(scoped_records) do
    if record.display_name and record.display_name ~= "" then
      name_counts[record.display_name] = (name_counts[record.display_name] or 0) + 1
    end
  end

  local index_records = {}
  for index, record in ipairs(scoped_records) do
    index_records[index] = record
  end
  table.sort(index_records, function(a, b)
    return a.id < b.id
  end)

  local duplicate_indices = {}
  local name_indices = {}
  for _, record in ipairs(index_records) do
    if record.display_name and record.display_name ~= "" and name_counts[record.display_name] > 1 then
      local duplicate_index = (name_indices[record.display_name] or 0) + 1
      name_indices[record.display_name] = duplicate_index
      duplicate_indices[record.id] = duplicate_index
    end
  end

  return duplicate_indices
end

function nests.display_caption(record, duplicate_index)
  if record.display_name and record.display_name ~= "" then
    if duplicate_index then
      return {"gui.biter-logistics-nest-option-duplicate", record.display_name, duplicate_index}
    end
    return {"gui.biter-logistics-nest-option-named", record.display_name}
  end
  return {"gui.biter-logistics-nest-option-unnamed", record.id}
end

function nests.duplicate_index(record)
  local duplicate_indices = duplicate_indices_for(scoped_records_for(record))
  return record and duplicate_indices[record.id] or nil
end

function nests.duplicate_suffix_caption(record)
  local duplicate_index = nests.duplicate_index(record)
  if not duplicate_index then return "" end
  return {"gui.biter-logistics-name-duplicate-suffix", duplicate_index}
end

function nests.set_display_name(id, display_name)
  local record = nests.get(id)
  if not record then return end
  if display_name == "" then
    record.display_name = nil
  else
    record.display_name = display_name
  end
end

function nests.set_mode(id, mode)
  local record = nests.get(id)
  if not nests.is_valid(record) then return false end
  if mode ~= constants.nest_modes.supply and mode ~= constants.nest_modes.request then
    return false
  end
  record.mode = mode
  visuals.update_nest(record)
  return true
end

function nests.set_request_item(id, item_name)
  local record = nests.get(id)
  if not nests.is_valid(record) then return false end
  if item_name and not prototypes.item[item_name] then return false end
  record.request_item = item_name
  record.request_quality = "normal"
  return true
end

function nests.cargo_slot_count(record)
  local force_name = record and record.force_name
  if not force_name and record and record.entity and record.entity.valid then
    force_name = record.entity.force.name
  end
  return research.nest_cargo_slots_for_force_name(force_name)
end

function nests.has_cargo(record)
  return for_each_cargo_slot(record, function(stack)
    if stack.valid_for_read then
      return true
    end
  end) or false
end

function nests.count_item(record, item_name)
  if not item_name then return 0 end
  local total = 0
  for_each_cargo_slot(record, function(stack)
    if stack.valid_for_read and stack.name == item_name then
      total = total + stack.count
    end
  end)
  return total
end

function nests.available_supply_count(record, item_name)
  if not nests.is_valid(record) or record.mode ~= constants.nest_modes.supply then return 0 end
  return math.max(0, nests.count_item(record, item_name) - jobs.supply_reserved_count(record.id, item_name))
end

function nests.free_space_for_item(record, item_name)
  if not item_name or not nests.is_valid(record) then return 0 end
  local stack_size = item_stack_size(item_name)
  if stack_size <= 0 then return 0 end

  local free = 0
  for_each_cargo_slot(record, function(stack)
    if not stack.valid_for_read then
      free = free + stack_size
    elseif stack.name == item_name then
      free = free + math.max(0, stack.prototype.stack_size - stack.count)
    end
  end)

  return math.max(0, free - jobs.request_reserved_count(record.id, item_name))
end

function nests.take_stacks(record, item_name, max_count, max_stacks)
  if not item_name or not max_count or max_count <= 0 then return {} end
  local cargo_slots = {}
  local remaining = max_count

  for_each_cargo_slot(record, function(stack)
    if remaining <= 0 or (max_stacks and #cargo_slots >= max_stacks) then return true end
    if stack.valid_for_read and stack.name == item_name then
      local name = stack.name
      local quality = stack_quality_name(stack)
      local count = math.min(stack.count, stack.prototype.stack_size, remaining)
      if count > 0 then
        cargo_slots[#cargo_slots + 1] = {name = name, count = count, quality = quality}
        remaining = remaining - count
        if count >= stack.count then
          stack.clear()
        else
          stack.count = stack.count - count
        end
      end
    end
  end)

  return cargo_slots
end

function nests.insert_cargo(record, cargo)
  if not cargo or cargo.count <= 0 then return 0 end

  local inserted_total = 0
  for_each_cargo_slot(record, function(stack)
    inserted_total = inserted_total + insert_into_cargo_slot(stack, cargo)
    if cargo.count <= 0 then return true end
  end)

  return inserted_total
end

function nests.remove(id)
  local data = state.get()
  local record = data.nests[id]
  if not record then return end

  if record.unit_number then
    data.nest_by_unit_number[record.unit_number] = nil
  end
  if record.destroy_registration_number then
    data.destroy_registrations[record.destroy_registration_number] = nil
  end

  data.request_queued[id] = nil
  indexes.unregister_nest(record)
  visuals.destroy(record)
  data.nests[id] = nil
  dequeue(data, id)
end

function nests.process_batch(request_callback)
  local data = state.get()
  local queue = data.nest_queue
  local length = #queue
  if length == 0 then return end

  local processed = 0
  local examined = 0
  while processed < constants.ticks.nests_per_update and examined < length do
    data.nest_cursor = (data.nest_cursor % length) + 1
    local id = queue[data.nest_cursor]
    local record = id and data.nests[id] or nil
    if record then
      if nests.is_valid(record) then
        nests.configure_inventory(record.entity)
        if request_callback and record.mode == constants.nest_modes.request and record.request_item then
          request_callback(record.id)
        end
      else
        nests.remove(id)
      end
      processed = processed + 1
    end
    examined = examined + 1
  end
end

function nests.rescan()
  local data = state.get()
  indexes.clear_nests()
  for _, surface in pairs(game.surfaces) do
    for _, entity in pairs(surface.find_entities_filtered{name = constants.nest_entity}) do
      nests.register(entity)
    end
  end

  for id, record in pairs(data.nests) do
    if nests.is_valid(record) then
      indexes.register_nest(record)
      nests.configure_inventory(record.entity)
      enqueue(data, id)
    else
      nests.remove(id)
    end
  end
end

return nests

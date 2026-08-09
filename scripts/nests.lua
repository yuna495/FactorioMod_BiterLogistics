local constants = require("constants")
local state = require("scripts.state")

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

function nests.configure_inventory(entity)
  if not valid(entity) then return end
  local inventory = entity.get_inventory(defines.inventory.chest)
  if not inventory or not inventory.supports_filters() then return end

  inventory.set_filter(constants.slots.carrier, {
    name = constants.carrier_item,
    quality = "normal",
    comparator = ">="
  })

  for slot = constants.slots.cargo_first, math.min(constants.slots.cargo_last, #inventory) do
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
      entity = entity,
      carrier_ids = {}
    }
    data.nests[id] = record
    data.nest_by_unit_number[entity.unit_number] = id
  end

  record.entity = entity
  record.unit_number = entity.unit_number
  record.force_name = entity.force.name
  record.surface_index = entity.surface_index
  record.position = copy_position(entity.position)
  record.carrier_ids = record.carrier_ids or {}

  nests.configure_inventory(entity)

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

function nests.display_caption(record)
  if record.display_name and record.display_name ~= "" then
    return {"gui.biter-logistics-nest-option-named", record.display_name, record.id}
  end
  return {"gui.biter-logistics-nest-option-unnamed", record.id}
end

function nests.destination_options(source_id)
  local data = state.get()
  local source = data.nests[source_id]
  local options = {
    {nest_id = nil, caption = {"gui.biter-logistics-no-destination"}}
  }
  if not nests.is_valid(source) then return options end

  local candidates = {}
  for id, record in pairs(data.nests) do
    if id ~= source_id
      and nests.is_valid(record)
      and record.force_name == source.force_name
      and record.surface_index == source.surface_index then
      candidates[#candidates + 1] = record
    end
  end

  table.sort(candidates, function(a, b)
    local a_name = a.display_name or ""
    local b_name = b.display_name or ""
    if a_name ~= b_name then return a_name < b_name end
    return a.id < b.id
  end)

  for _, record in ipairs(candidates) do
    options[#options + 1] = {nest_id = record.id, caption = nests.display_caption(record)}
  end

  return options
end

function nests.set_destination(source_id, destination_id)
  local data = state.get()
  local source = data.nests[source_id]
  if not nests.is_valid(source) then return false end

  if not destination_id then
    source.destination_nest_id = nil
    return true
  end

  local destination = data.nests[destination_id]
  if not nests.is_valid(destination) or source_id == destination_id then return false end
  if source.force_name ~= destination.force_name or source.surface_index ~= destination.surface_index then return false end

  source.destination_nest_id = destination_id
  return true
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

function nests.count_carrier_items(record)
  if not nests.is_valid(record) then return 0 end
  local inventory = record.entity.get_inventory(defines.inventory.chest)
  if not inventory then return 0 end
  local stack = inventory[constants.slots.carrier]
  if stack.valid_for_read and stack.name == constants.carrier_item then
    return stack.count
  end
  return 0
end

function nests.take_one_stack(record)
  if not nests.is_valid(record) then return nil end
  local inventory = record.entity.get_inventory(defines.inventory.chest)
  if not inventory then return nil end

  for slot = constants.slots.cargo_first, math.min(constants.slots.cargo_last, #inventory) do
    local stack = inventory[slot]
    if stack.valid_for_read and stack.name ~= constants.carrier_item then
      local quality = stack.quality and stack.quality.name or "normal"
      local count = math.min(stack.count, stack.prototype.stack_size)
      local request = {name = stack.name, count = count, quality = quality}
      local removed = inventory.remove(request)
      if removed > 0 then
        return {name = stack.name, count = removed, quality = quality}
      end
    end
  end

  return nil
end

function nests.insert_cargo(record, cargo)
  if not cargo or cargo.count <= 0 or not nests.is_valid(record) then return 0 end
  local inventory = record.entity.get_inventory(defines.inventory.chest)
  if not inventory then return 0 end

  local stack = {name = cargo.name, count = cargo.count}
  if cargo.quality and cargo.quality ~= "normal" then
    stack.quality = cargo.quality
  end

  local inserted = inventory.insert(stack)
  cargo.count = cargo.count - inserted
  if cargo.count <= 0 then
    cargo.count = 0
  end
  return inserted
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

  data.nests[id] = nil
  dequeue(data, id)

  for _, other in pairs(data.nests) do
    if other.destination_nest_id == id then
      other.destination_nest_id = nil
    end
  end
end

local function process_carrier_slot(record, spawn_callback)
  if not nests.is_valid(record) then return end
  local inventory = record.entity.get_inventory(defines.inventory.chest)
  if not inventory then return end

  local stack = inventory[constants.slots.carrier]
  if not stack.valid_for_read or stack.name ~= constants.carrier_item then return end

  local quality = stack.quality and stack.quality.name or "normal"
  if spawn_callback(record, quality) then
    if stack.count > 1 then
      stack.count = stack.count - 1
    else
      stack.clear()
    end
  end
end

function nests.process_batch(spawn_callback)
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
        process_carrier_slot(record, spawn_callback)
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
  for _, surface in pairs(game.surfaces) do
    for _, entity in pairs(surface.find_entities_filtered{name = constants.nest_entity}) do
      nests.register(entity)
    end
  end

  for id, record in pairs(data.nests) do
    if nests.is_valid(record) then
      nests.configure_inventory(record.entity)
      enqueue(data, id)
    else
      nests.remove(id)
    end
  end
end

return nests

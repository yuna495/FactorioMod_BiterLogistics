local constants = require("constants")
local state = require("scripts.state")
local nests = require("scripts.nests")
local depots = require("scripts.depots")
local jobs = require("scripts.jobs")
local research = require("scripts.research")
local food = require("scripts.food")

local carriers = {}

local function valid(entity)
  return entity and entity.valid
end

local function copy_position(position)
  return {x = position.x, y = position.y}
end

local function enqueue(data, id)
  if data.carrier_queued[id] then return end
  data.carrier_queue[#data.carrier_queue + 1] = id
  data.carrier_queued[id] = true
end

local function dequeue(data, id)
  if not data.carrier_queued[id] then return end
  for index, queued_id in ipairs(data.carrier_queue) do
    if queued_id == id then
      table.remove(data.carrier_queue, index)
      if data.carrier_cursor >= index then
        data.carrier_cursor = math.max(data.carrier_cursor - 1, 0)
      end
      break
    end
  end
  data.carrier_queued[id] = nil
end

local function stack_definition(cargo)
  local stack = {name = cargo.name, count = cargo.count}
  if cargo.quality and cargo.quality ~= "normal" then
    stack.quality = cargo.quality
  end
  return stack
end

local function normalise_cargo_slots(record)
  record.cargo_slots = record.cargo_slots or {}
  if record.cargo and record.cargo.name and record.cargo.count and record.cargo.count > 0 then
    record.cargo_slots[#record.cargo_slots + 1] = record.cargo
  end
  record.cargo = nil

  local next_slot = 1
  for index = 1, #record.cargo_slots do
    local cargo = record.cargo_slots[index]
    if cargo and cargo.name and cargo.count and cargo.count > 0 then
      record.cargo_slots[next_slot] = cargo
      next_slot = next_slot + 1
    end
  end
  for index = next_slot, #record.cargo_slots do
    record.cargo_slots[index] = nil
  end

  return record.cargo_slots
end

local function has_carried_cargo(record)
  for _, cargo in ipairs(normalise_cargo_slots(record)) do
    if cargo.count > 0 then return true end
  end
  return false
end

local function carrier_capacity(record)
  local force_name = record.force_name
  if not force_name and valid(record.entity) then
    force_name = record.entity.force.name
  end
  return math.max(1, research.carrier_capacity_for_force_name(force_name))
end

local function load_cargo_from_source(record, source, job)
  local cargo_slots = normalise_cargo_slots(record)
  local capacity_left = carrier_capacity(record) - #cargo_slots
  if capacity_left <= 0 or not job or not job.item_name then return 0 end

  local loaded_count = 0
  local taken = nests.take_stacks(source, job.item_name, job.requested_count or 0, capacity_left)
  for _, cargo in ipairs(taken) do
    cargo_slots[#cargo_slots + 1] = cargo
    loaded_count = loaded_count + cargo.count
  end

  jobs.set_picked_count(job.id, loaded_count)
  return loaded_count
end

local function insert_all_cargo(record, nest_record)
  local inserted = 0
  for _, cargo in ipairs(normalise_cargo_slots(record)) do
    if cargo.count > 0 then
      inserted = inserted + nests.insert_cargo(nest_record, cargo)
    end
  end
  normalise_cargo_slots(record)
  return inserted
end

local function spill_cargo(record)
  if not has_carried_cargo(record) then return end

  local surface = valid(record.entity) and record.entity.surface or game.get_surface(record.surface_index)
  if not surface then return end

  local position = valid(record.entity) and record.entity.position or record.last_position
  if not position then return end

  for _, cargo in ipairs(normalise_cargo_slots(record)) do
    local spill = {
      position = position,
      stack = stack_definition(cargo),
      allow_belts = false
    }
    if valid(record.entity) then
      spill.force = record.entity.force
    elseif record.force_name and game.forces[record.force_name] then
      spill.force = game.forces[record.force_name]
    end
    surface.spill_item_stack(spill)
  end

  record.cargo_slots = {}
  record.cargo = nil
end

local function spill_carrier_item(record, options)
  options = options or {}
  local stack = {name = constants.carrier_item, count = 1}
  if record.quality and record.quality ~= "normal" then
    stack.quality = record.quality
  end

  if options.player_index then
    local player = game.get_player(options.player_index)
    local inventory = player and player.get_main_inventory()
    if inventory then
      local inserted = inventory.insert(stack)
      if inserted >= stack.count then return end
      stack.count = stack.count - inserted
    end
  end

  local surface = valid(record.entity) and record.entity.surface or game.get_surface(record.surface_index)
  if not surface then return end

  local spill_position = options.item_position or record.last_position or (valid(record.entity) and record.entity.position)
  if not spill_position then return end

  local spill = {
    position = spill_position,
    stack = stack,
    allow_belts = false
  }
  if valid(record.entity) then
    spill.force = record.entity.force
  elseif record.force_name and game.forces[record.force_name] then
    spill.force = game.forces[record.force_name]
  end

  surface.spill_item_stack(spill)
end

local function clear_job(record, result)
  if record.job_id then
    jobs.complete(record.job_id, result)
    record.job_id = nil
  end
end

function carriers.register(entity, home_depot_id, quality)
  if not valid(entity) or entity.name ~= constants.carrier_unit or not entity.unit_number then
    return nil
  end

  local data = state.get()
  local id = data.carrier_by_unit_number[entity.unit_number]
  local record = id and data.carriers[id] or nil

  if not record then
    id = data.next_carrier_id
    data.next_carrier_id = id + 1
    record = {
      id = id,
      unit_number = entity.unit_number,
      state = "idle",
      home_depot_id = home_depot_id,
      quality = quality or "normal"
    }
    data.carriers[id] = record
    data.carrier_by_unit_number[entity.unit_number] = id
  end

  record.entity = entity
  record.unit_number = entity.unit_number
  record.home_depot_id = home_depot_id or record.home_depot_id
  record.home_nest_id = nil
  record.quality = quality or record.quality or "normal"
  record.force_name = entity.force.name
  record.surface_index = entity.surface_index
  record.last_position = copy_position(entity.position)
  record.next_update_tick = game.tick
  food.ensure_carrier_fields(record)
  normalise_cargo_slots(record)
  research.apply_to_carrier(record)

  if record.home_depot_id then
    local home = depots.get(record.home_depot_id)
    if home then
      home.carrier_ids = home.carrier_ids or {}
      home.carrier_ids[id] = true
    end
  end

  if not record.destroy_registration_number then
    local registration_number = script.register_on_object_destroyed(entity)
    record.destroy_registration_number = registration_number
    data.destroy_registrations[registration_number] = {type = "carrier", id = id}
  end

  enqueue(data, id)
  return record
end

function carriers.spawn_from_depot(depot_record, quality)
  if not depots.is_valid(depot_record) then return false end

  local entity = depot_record.entity
  local position = entity.surface.find_non_colliding_position(
    constants.carrier_unit,
    entity.position,
    6,
    0.5
  )
  if not position then return false end

  local create = {
    name = constants.carrier_unit,
    position = position,
    force = entity.force
  }
  if quality and quality ~= "normal" then
    create.quality = quality
  end

  local carrier_entity = entity.surface.create_entity(create)
  if not carrier_entity then return false end

  if not carriers.register(carrier_entity, depot_record.id, quality) then
    carrier_entity.destroy()
    return false
  end

  return true
end

local function is_near_record(record, target_record)
  if not valid(record.entity) or not target_record or not valid(target_record.entity) then return false end
  local dx = record.entity.position.x - target_record.entity.position.x
  local dy = record.entity.position.y - target_record.entity.position.y
  return dx * dx + dy * dy <= constants.command.interaction_radius * constants.command.interaction_radius
end

local function is_near_position(record, position, radius)
  if not valid(record.entity) or not position then return false end
  local dx = record.entity.position.x - position.x
  local dy = record.entity.position.y - position.y
  return dx * dx + dy * dy <= radius * radius
end

local function destination_position(record, target_record)
  if not valid(record.entity) or not target_record or not valid(target_record.entity) then return nil end
  return target_record.entity.surface.find_non_colliding_position(
    constants.carrier_unit,
    target_record.entity.position,
    constants.command.destination_search_radius,
    constants.command.destination_precision
  )
end

local moving_states = {
  to_source = true,
  to_destination = true,
  returning = true
}

local function is_moving_state(record)
  return record and moving_states[record.state] or false
end

local function target_for_state(record)
  local job = jobs.get(record.job_id)
  if record.state == "returning" and not job then
    return depots.get(record.home_depot_id), "depot", record.home_depot_id
  end
  if not job then return nil end
  if record.state == "to_source" then return nests.get(job.source_nest_id), "nest", job.source_nest_id end
  if record.state == "to_destination" then return nests.get(job.destination_nest_id), "nest", job.destination_nest_id end
  if record.state == "returning" then return depots.get(job.home_depot_id or record.home_depot_id), "depot", job.home_depot_id or record.home_depot_id end
  return nil
end

local function issue_command(record, target_record, target_type, target_id, next_state)
  if not target_record or not valid(target_record.entity) or not valid(record.entity) or not record.entity.commandable then
    return false
  end

  local destination = destination_position(record, target_record)
  if not destination then return false end

  record.entity.commandable.set_command{
    type = defines.command.compound,
    distraction = defines.distraction.none,
    structure_type = defines.compound_command.return_last,
    commands = {
      {
        type = defines.command.go_to_location,
        destination = copy_position(destination),
        radius = constants.command.radius,
        distraction = defines.distraction.none,
        pathfind_flags = constants.command.pathfind_flags
      },
      {
        type = defines.command.stop,
        ticks_to_wait = constants.command.stop_ticks,
        distraction = defines.distraction.none
      }
    }
  }

  record.state = next_state
  record.command_target_type = target_type
  record.command_target_id = target_id
  record.command_position = copy_position(destination)
  record.command_failed = nil
  record.command_tick = game.tick
  record.next_update_tick = game.tick + constants.ticks.command_check_interval
  return true
end

local update_record

local function set_idle(record, delay)
  clear_job(record, "complete")
  record.state = "idle"
  record.command_target_type = nil
  record.command_target_id = nil
  record.command_position = nil
  record.command_failed = nil
  record.next_update_tick = game.tick + (delay or constants.ticks.idle_delay)
end

local function return_home(record)
  local job = jobs.get(record.job_id)
  local home_depot_id = job and job.home_depot_id or record.home_depot_id
  local home = depots.get(home_depot_id)
  jobs.set_state(record.job_id, "returning")
  record.state = "returning"
  record.command_target_type = nil
  record.command_target_id = nil
  record.command_position = nil
  record.command_failed = nil
  if not issue_command(record, home, "depot", home_depot_id, "returning") then
    record.next_update_tick = game.tick + constants.ticks.retry_delay
  end
end

local function destination_space_delay(record)
  local jitter = constants.ticks.destination_space_check_jitter or 0
  if jitter <= 0 then return constants.ticks.destination_space_check_interval end
  return constants.ticks.destination_space_check_interval + (record.id % jitter)
end

local function wait_for_destination_space(record)
  jobs.set_state(record.job_id, "waiting_for_destination_space")
  record.state = "waiting_for_destination_space"
  record.command_target_type = nil
  record.command_target_id = nil
  record.command_position = nil
  record.command_failed = nil
  record.next_update_tick = game.tick + destination_space_delay(record)
end

local function complete_command_success(record)
  record.command_failed = nil
  record.command_target_type = nil
  record.command_target_id = nil
  record.command_position = nil

  if record.state == "to_source" then
    record.state = "loading"
    jobs.set_state(record.job_id, "loading")
    record.next_update_tick = game.tick
    return true
  end

  if record.state == "to_destination" then
    record.state = "unloading"
    jobs.set_state(record.job_id, "unloading")
    record.next_update_tick = game.tick
    return true
  end

  if record.state == "returning" then
    set_idle(record, constants.ticks.idle_delay)
    return false
  end

  return false
end

update_record = function(record)
  if not valid(record.entity) then
    carriers.remove(record.id, {spill_cargo = true})
    return
  end

  record.last_position = copy_position(record.entity.position)
  record.surface_index = record.entity.surface_index
  record.force_name = record.entity.force.name
  food.ensure_carrier_fields(record)

  if is_moving_state(record) then
    local target_record, target_type, target_id = target_for_state(record)
    local commandable = record.entity.commandable
    local command_ended = commandable and not commandable.has_command
    local command_timed_out = record.command_tick
      and game.tick - record.command_tick >= constants.ticks.command_timeout

    if (record.command_position
        and is_near_position(record, record.command_position, constants.command.interaction_radius))
      or is_near_record(record, target_record) then
      if complete_command_success(record) then
        update_record(record)
      end
      return
    end

    if record.command_failed or command_ended or command_timed_out then
      if target_record then
        if not issue_command(record, target_record, target_type, target_id, record.state) then
          record.next_update_tick = game.tick + constants.ticks.retry_delay
        end
      else
        if has_carried_cargo(record) then spill_cargo(record) end
        set_idle(record)
      end
    else
      record.next_update_tick = game.tick + constants.ticks.command_check_interval
    end
    return
  end

  if record.state == "idle" then
    local home = depots.get(record.home_depot_id)
    if not depots.is_valid(home) then
      carriers.remove(record.id, {spill_cargo = true, return_carrier_item = true, destroy_entity = true})
      return
    end

    if has_carried_cargo(record) then
      spill_cargo(record)
    end

    if is_near_record(record, home) then
      record.next_update_tick = game.tick + constants.ticks.idle_delay
    elseif not issue_command(record, home, "depot", home.id, "returning") then
      record.next_update_tick = game.tick + constants.ticks.retry_delay
    end
    return
  end

  if record.state == "loading" then
    local job = jobs.get(record.job_id)
    local source = job and nests.get(job.source_nest_id)
    local destination = job and nests.get(job.destination_nest_id)
    if not job or not nests.is_valid(source) then
      jobs.set_failure(record.job_id, "source_invalid")
      return_home(record)
      return
    end
    if not nests.is_valid(destination) then
      jobs.set_failure(record.job_id, "destination_invalid")
      return_home(record)
      return
    end

    local loaded = load_cargo_from_source(record, source, job)
    if loaded <= 0 or not has_carried_cargo(record) then
      jobs.set_failure(record.job_id, "no_supply")
      return_home(record)
      return
    end

    jobs.set_state(record.job_id, "to_destination")
    if not issue_command(record, destination, "nest", destination.id, "to_destination") then
      jobs.set_failure(record.job_id, "destination_command_failed")
      spill_cargo(record)
      return_home(record)
    end
    return
  end

  if record.state == "unloading" then
    local job = jobs.get(record.job_id)
    local destination = job and nests.get(job.destination_nest_id)
    if not has_carried_cargo(record) then
      return_home(record)
      return
    end

    if not nests.is_valid(destination) then
      jobs.set_failure(record.job_id, "destination_invalid")
      spill_cargo(record)
      return_home(record)
      return
    end

    insert_all_cargo(record, destination)
    if has_carried_cargo(record) then
      wait_for_destination_space(record)
      return
    end

    return_home(record)
    return
  end

  if record.state == "waiting_for_destination_space" then
    local job = jobs.get(record.job_id)
    local destination = job and nests.get(job.destination_nest_id)

    if not has_carried_cargo(record) then
      return_home(record)
      return
    end

    if not job or not nests.is_valid(destination) then
      jobs.set_failure(record.job_id, "destination_invalid")
      spill_cargo(record)
      return_home(record)
      return
    end

    if not is_near_record(record, destination) then
      jobs.set_state(record.job_id, "to_destination")
      if not issue_command(record, destination, "nest", destination.id, "to_destination") then
        wait_for_destination_space(record)
      end
      return
    end

    insert_all_cargo(record, destination)
    if has_carried_cargo(record) then
      wait_for_destination_space(record)
      return
    end

    return_home(record)
    return
  end

  set_idle(record)
end

local function should_update(record)
  if not record.next_update_tick or record.next_update_tick <= game.tick then
    return true
  end

  if not is_moving_state(record) then return false end

  local target_record = target_for_state(record)
  return (record.command_position
      and is_near_position(record, record.command_position, constants.command.interaction_radius))
    or is_near_record(record, target_record)
end

function carriers.assign_job(record, job)
  if not record or not job or record.job_id or record.state ~= "idle" then return false end
  local source = nests.get(job.source_nest_id)
  if not nests.is_valid(source) then return false end

  record.job_id = job.id
  jobs.set_state(job.id, "to_source")
  if is_near_record(record, source) then
    record.state = "loading"
    record.next_update_tick = game.tick
    update_record(record)
    return true
  end

  if not issue_command(record, source, "nest", source.id, "to_source") then
    record.job_id = nil
    record.state = "idle"
    record.next_update_tick = game.tick + constants.ticks.retry_delay
    return false
  end
  return true
end

function carriers.process_batch()
  local data = state.get()
  local queue = data.carrier_queue
  local length = #queue
  if length == 0 then return end

  local processed = 0
  local examined = 0
  while processed < constants.ticks.carriers_per_update and examined < length do
    data.carrier_cursor = (data.carrier_cursor % length) + 1
    local id = queue[data.carrier_cursor]
    local record = id and data.carriers[id] or nil
    if record then
      if should_update(record) then
        update_record(record)
        processed = processed + 1
      end
    end
    examined = examined + 1
  end
end

function carriers.on_ai_command_completed(event)
  local data = state.get()
  local id = data.carrier_by_unit_number[event.unit_number]
  local record = id and data.carriers[id] or nil
  if not record then return end

  record.next_update_tick = game.tick
  if event.result ~= defines.behavior_result.success then
    record.command_failed = true
    record.next_update_tick = game.tick + constants.ticks.retry_delay
    return
  end

  record.command_failed = nil
  if complete_command_success(record) then
    update_record(record)
  end
end

function carriers.remove(id, options)
  options = options or {}
  local data = state.get()
  local record = data.carriers[id]
  if not record then return end

  if options.spill_cargo then
    spill_cargo(record)
  end
  if options.return_carrier_item then
    spill_carrier_item(record, options)
  end

  if record.home_depot_id then
    local home = data.depots[record.home_depot_id]
    if home and home.carrier_ids then
      home.carrier_ids[id] = nil
    end
  end

  clear_job(record, "removed")

  if record.unit_number then
    data.carrier_by_unit_number[record.unit_number] = nil
  end
  if record.destroy_registration_number then
    data.destroy_registrations[record.destroy_registration_number] = nil
  end

  local entity = record.entity
  data.carriers[id] = nil
  dequeue(data, id)

  if options.destroy_entity and valid(entity) then
    entity.destroy()
  end
end

function carriers.remove_by_unit_number(unit_number, options)
  local data = state.get()
  local id = data.carrier_by_unit_number[unit_number]
  if id then carriers.remove(id, options) end
end

function carriers.handle_nest_removed(nest_id)
  local data = state.get()
  local carrier_ids = {}
  for id in pairs(data.carriers) do
    carrier_ids[#carrier_ids + 1] = id
  end

  for _, id in ipairs(carrier_ids) do
    local record = data.carriers[id]
    if record and record.job_id then
      local job = jobs.get(record.job_id)
      if job and (job.source_nest_id == nest_id or job.destination_nest_id == nest_id) then
        jobs.set_failure(job.id, "nest_removed")
        if has_carried_cargo(record) then spill_cargo(record) end
        return_home(record)
      end
    end
  end
end

function carriers.handle_depot_removed(depot_id, position, options)
  options = options or {}
  local data = state.get()
  local carrier_ids = {}
  for id in pairs(data.carriers) do
    carrier_ids[#carrier_ids + 1] = id
  end

  for _, id in ipairs(carrier_ids) do
    local record = data.carriers[id]
    if record and record.home_depot_id == depot_id then
      carriers.remove(id, {
        spill_cargo = true,
        return_carrier_item = true,
        item_position = position,
        player_index = options.player_index,
        destroy_entity = true
      })
    elseif record and record.job_id then
      local job = jobs.get(record.job_id)
      if job and job.home_depot_id == depot_id then
        jobs.set_failure(job.id, "depot_removed")
        if has_carried_cargo(record) then spill_cargo(record) end
        carriers.remove(id, {return_carrier_item = true, item_position = position, destroy_entity = true})
      end
    end
  end
end

function carriers.validate()
  local data = state.get()
  local carrier_ids = {}
  for id in pairs(data.carriers) do
    carrier_ids[#carrier_ids + 1] = id
  end

  for _, id in ipairs(carrier_ids) do
    local record = data.carriers[id]
    if record and valid(record.entity) and record.home_depot_id and depots.is_valid(depots.get(record.home_depot_id)) then
      data.carrier_by_unit_number[record.unit_number] = id
      record.next_update_tick = game.tick
      record.home_nest_id = nil
      food.ensure_carrier_fields(record)
      normalise_cargo_slots(record)
      research.apply_to_carrier(record)
      enqueue(data, id)
    elseif record then
      carriers.remove(id, {spill_cargo = true, return_carrier_item = true, destroy_entity = valid(record.entity)})
    end
  end
end

function carriers.count_for_depot(depot_id)
  local count = 0
  for _, record in pairs(state.get().carriers) do
    if record.home_depot_id == depot_id then
      count = count + 1
    end
  end
  return count
end

function carriers.active_for_depot(depot_id)
  local count = 0
  for _, record in pairs(state.get().carriers) do
    if record.home_depot_id == depot_id and record.state ~= "idle" then
      count = count + 1
    end
  end
  return count
end

return carriers

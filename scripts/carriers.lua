local constants = require("constants")
local state = require("scripts.state")
local nests = require("scripts.nests")
local depots = require("scripts.depots")
local jobs = require("scripts.jobs")
local research = require("scripts.research")
local food = require("scripts.food")
local diagnostics = require("scripts.diagnostics")
local logistics = require("scripts.logistics")

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

local function carried_count(record)
  local total = 0
  for _, cargo in ipairs(normalise_cargo_slots(record)) do
    total = total + (cargo.count or 0)
  end
  return total
end

local function adjust_job_reservation_to_cargo(record)
  if record.job_id then
    jobs.adjust_reservation_to_count(record.job_id, carried_count(record))
  end
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
  jobs.adjust_reservation_to_picked_count(job.id)
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

local function ensure_failure_fields(record)
  if not record then return end
  record.starvation_failures = math.max(0, tonumber(record.starvation_failures) or 0)
  record.route_failures = math.max(0, tonumber(record.route_failures) or 0)
end

local function reset_starvation_failures(record)
  if not record then return end
  record.starvation_failures = 0
  record.last_starvation_failure_tick = nil
end

local function reset_route_failures(record)
  if not record then return end
  record.route_failures = 0
  record.last_route_failure_tick = nil
  record.route_failure_target_type = nil
  record.route_failure_target_id = nil
  record.route_failure_state = nil
end

local function reset_route_progress(record)
  if not record then return end
  record.route_progress_target_type = nil
  record.route_progress_target_id = nil
  record.route_progress_state = nil
  record.route_best_distance = nil
  record.route_last_progress_tick = nil
end

local function feral_job_result(reason)
  return "feralized_" .. tostring(reason or "unknown")
end

local function feral_cargo_behavior()
  local setting = settings
    and settings.global
    and settings.global[constants.settings.feral_cargo_behavior]
  local value = setting and setting.value or constants.feral.cargo_behavior.drop
  if value == constants.feral.cargo_behavior.destroy then
    return value
  end
  return constants.feral.cargo_behavior.drop
end

local function feral_scope(record, entity)
  local carrier_entity = valid(entity) and entity or (valid(record.entity) and record.entity or nil)
  local surface = carrier_entity and carrier_entity.surface
    or (record.surface_index and game.get_surface(record.surface_index))
  local position = carrier_entity and copy_position(carrier_entity.position)
    or (record.last_position and copy_position(record.last_position))
  return {
    carrier_id = record.id,
    unit_number = record.unit_number,
    force_name = record.force_name or (carrier_entity and carrier_entity.force.name),
    surface_index = surface and surface.index or record.surface_index,
    surface_name = surface and surface.name or nil,
    surface = surface,
    position = position
  }
end

local function spawn_point_value(point, key, index, default)
  if type(point) ~= "table" then return default end
  local value = point[key]
  if value == nil then value = point[index] end
  if value == nil then return default end
  return value
end

local function spawn_points_for_unit(definition)
  if type(definition) ~= "table" then return nil, nil end
  local unit_name = definition.unit or definition[1]
  local spawn_points = definition.spawn_points or definition[2]
  return unit_name, spawn_points
end

local function interpolated_spawn_weight(spawn_points, evolution_factor)
  if type(spawn_points) ~= "table" then return 0 end
  local points = {}
  for _, point in pairs(spawn_points) do
    points[#points + 1] = {
      evolution_factor = tonumber(spawn_point_value(point, "evolution_factor", 1, 0)) or 0,
      weight = tonumber(spawn_point_value(point, "weight", 2, 0)) or 0
    }
  end
  if #points == 0 then return 0 end

  table.sort(points, function(left, right)
    return left.evolution_factor < right.evolution_factor
  end)

  if evolution_factor <= points[1].evolution_factor then
    return points[1].weight
  end

  for index = 2, #points do
    local previous = points[index - 1]
    local current = points[index]
    if evolution_factor <= current.evolution_factor then
      local span = current.evolution_factor - previous.evolution_factor
      if span <= 0 then return current.weight end
      local ratio = (evolution_factor - previous.evolution_factor) / span
      return previous.weight + (current.weight - previous.weight) * ratio
    end
  end

  return points[#points].weight
end

local function enemy_force_and_evolution(surface)
  local enemy_force = game.forces.enemy
  if not enemy_force or not enemy_force.valid then
    log("Biter Logistics: cannot feralize carrier because force 'enemy' is unavailable.")
    return nil, 0
  end

  local ok, evolution_factor = pcall(function()
    return enemy_force.get_evolution_factor(surface)
  end)
  if not ok then
    log("Biter Logistics: failed to read enemy evolution factor for feral carrier; using 0.")
    evolution_factor = 0
  end
  return enemy_force, evolution_factor or 0
end

local function strongest_available_biter(surface)
  local enemy_force, evolution_factor = enemy_force_and_evolution(surface)
  if not enemy_force then return nil, nil end

  local best_name = nil
  local best_rank = 0
  local spawner = prototypes.entity["biter-spawner"]
  if spawner and spawner.result_units then
    for _, definition in pairs(spawner.result_units) do
      local unit_name, spawn_points = spawn_points_for_unit(definition)
      local rank = constants.feral.biter_rank[unit_name]
      if rank
        and rank > best_rank
        and prototypes.entity[unit_name]
        and interpolated_spawn_weight(spawn_points, evolution_factor) > 0 then
        best_name = unit_name
        best_rank = rank
      end
    end
  end

  if best_name then return best_name, enemy_force end

  local fallback = constants.feral.fallback_biter
  if prototypes.entity[fallback] then
    return fallback, enemy_force
  end

  for _, unit_name in ipairs(constants.feral.biter_order) do
    if prototypes.entity[unit_name] then
      return unit_name, enemy_force
    end
  end

  log("Biter Logistics: cannot feralize carrier because no biter unit prototype is available.")
  return nil, enemy_force
end

local function create_wild_biter(surface, unit_name, enemy_force, position)
  if not surface or not surface.valid or not position then return nil end

  local ok, entity = pcall(function()
    return surface.create_entity{
      name = unit_name,
      position = position,
      force = enemy_force
    }
  end)
  if ok and entity then return entity end
  return nil
end

local function command_wild_biter(wild, origin)
  if not valid(wild) or not wild.commandable or not origin then return end
  local ok, err = pcall(function()
    wild.commandable.set_command{
      type = defines.command.attack_area,
      destination = origin,
      radius = constants.feral.attack_radius,
      distraction = defines.distraction.by_enemy
    }
  end)
  if not ok then
    log("Biter Logistics: failed to command feral biter: " .. tostring(err))
  end
end

local function spawn_wild_biter(scope)
  if not scope or not scope.surface or not scope.surface.valid or not scope.position then
    log("Biter Logistics: cannot spawn feral biter because carrier location is unavailable.")
    return nil
  end

  local unit_name, enemy_force = strongest_available_biter(scope.surface)
  if not unit_name or not enemy_force then return nil end

  local wild = create_wild_biter(scope.surface, unit_name, enemy_force, scope.position)
  if not wild then
    local position = scope.surface.find_non_colliding_position(
      unit_name,
      scope.position,
      constants.feral.spawn_search_radius,
      constants.feral.spawn_search_precision
    )
    if position then
      wild = create_wild_biter(scope.surface, unit_name, enemy_force, position)
    end
  end

  if not wild then
    log("Biter Logistics: failed to create feral biter '" .. unit_name .. "' near carrier #" .. tostring(scope.carrier_id) .. ".")
    return nil
  end

  command_wild_biter(wild, scope.position)
  return wild
end

function carriers.feralize(record_or_id, reason, options)
  options = options or {}
  local data = state.get()
  local record = type(record_or_id) == "table" and record_or_id or data.carriers[record_or_id]
  if not record or record.feralizing then return false end

  record.feralizing = true
  local entity = options.entity or record.entity
  local scope = feral_scope(record, entity)
  local id = record.id

  diagnostics.clear_for_carrier(id)

  if feral_cargo_behavior() == constants.feral.cargo_behavior.drop then
    spill_cargo(record)
  else
    record.cargo_slots = {}
    record.cargo = nil
  end

  if record.home_depot_id then
    local home = data.depots[record.home_depot_id]
    if home and home.carrier_ids then
      home.carrier_ids[id] = nil
    end
  end

  clear_job(record, feral_job_result(reason))

  if record.unit_number then
    data.carrier_by_unit_number[record.unit_number] = nil
  end
  if record.destroy_registration_number then
    data.destroy_registrations[record.destroy_registration_number] = nil
  end

  local alert_entity = valid(entity) and entity or nil
  data.carriers[id] = nil
  dequeue(data, id)

  local wild = spawn_wild_biter(scope)
  diagnostics.carrier_feralized(scope, reason, wild or alert_entity)

  if not options.entity_already_dead and valid(entity) then
    entity.destroy()
  end

  return true
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
  ensure_failure_fields(record)
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

local function route_distance(record, target_record)
  if not valid(record.entity) or not target_record or not valid(target_record.entity) then return nil end
  local dx = record.entity.position.x - target_record.entity.position.x
  local dy = record.entity.position.y - target_record.entity.position.y
  return math.sqrt(dx * dx + dy * dy)
end

local function route_failure_identity_changed(record, target_type, target_id, route_state)
  return record.route_failure_target_type ~= target_type
    or record.route_failure_target_id ~= target_id
    or record.route_failure_state ~= route_state
end

local function route_progress_identity_changed(record, target_type, target_id, route_state)
  return record.route_progress_target_type ~= target_type
    or record.route_progress_target_id ~= target_id
    or record.route_progress_state ~= route_state
end

local function update_route_progress(record, target_record, target_type, target_id, route_state)
  local distance = route_distance(record, target_record)
  if not distance then return end

  if route_progress_identity_changed(record, target_type, target_id, route_state) then
    record.route_progress_target_type = target_type
    record.route_progress_target_id = target_id
    record.route_progress_state = route_state
    record.route_best_distance = distance
    record.route_last_progress_tick = game.tick
    return
  end

  if not record.route_best_distance then
    record.route_best_distance = distance
    record.route_last_progress_tick = game.tick
    return
  end

  if distance < record.route_best_distance - constants.feral.route_progress_min_delta then
    record.route_best_distance = distance
    record.route_last_progress_tick = game.tick
  end
end

local function route_has_stalled(record)
  local last_progress_tick = record.route_last_progress_tick or record.command_tick
  return last_progress_tick
    and game.tick - last_progress_tick >= constants.ticks.command_timeout
end

local function record_route_failure(record, target_record, target_type, target_id, route_state)
  if not valid(record.entity) or not target_record or not valid(target_record.entity) then
    return false
  end

  ensure_failure_fields(record)
  if route_failure_identity_changed(record, target_type, target_id, route_state) then
    record.route_failures = 0
    record.last_route_failure_tick = nil
    record.route_failure_target_type = target_type
    record.route_failure_target_id = target_id
    record.route_failure_state = route_state
  end

  if record.last_route_failure_tick
    and game.tick - record.last_route_failure_tick < constants.feral.failure_interval then
    return false
  end

  record.route_failures = record.route_failures + 1
  record.last_route_failure_tick = game.tick
  diagnostics.carrier_route_failure(record, target_record, target_type, record.route_failures)

  if record.route_failures >= constants.feral.failure_threshold then
    return carriers.feralize(record, "route_failure")
  end

  return false
end

local function schedule_route_retry(record)
  record.command_failed = nil
  record.command_result = nil
  record.awaiting_route_retry = true
  record.next_update_tick = game.tick + constants.ticks.retry_delay
end

local function issue_command(record, target_record, target_type, target_id, next_state)
  if not target_record or not valid(target_record.entity) or not valid(record.entity) or not record.entity.commandable then
    return false
  end

  local destination = destination_position(record, target_record)
  if not destination then return false end

  local commandable = record.entity.commandable
  local ok, err = pcall(function()
    commandable.set_command{
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
  end)
  if not ok then
    log("Biter Logistics: failed to issue carrier command: " .. tostring(err))
    return false
  end

  record.state = next_state
  record.command_target_type = target_type
  record.command_target_id = target_id
  record.command_position = copy_position(destination)
  record.command_failed = nil
  record.command_result = nil
  record.awaiting_route_retry = nil
  record.command_tick = game.tick
  update_route_progress(record, target_record, target_type, target_id, next_state)
  record.next_update_tick = game.tick + constants.ticks.command_check_interval
  return true
end

local update_record

local function set_idle(record, delay)
  clear_job(record, "complete")
  record.state = "idle"
  reset_route_failures(record)
  reset_route_progress(record)
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
  reset_route_progress(record)
  record.command_target_type = nil
  record.command_target_id = nil
  record.command_position = nil
  record.command_failed = nil
  if not depots.is_valid(home) then
    carriers.remove(record.id, {spill_cargo = true, return_carrier_item = true, destroy_entity = true})
    return
  end
  if not issue_command(record, home, "depot", home_depot_id, "returning") then
    if not record_route_failure(record, home, "depot", home_depot_id, "returning") then
      schedule_route_retry(record)
    end
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
  reset_route_progress(record)
  record.command_target_type = nil
  record.command_target_id = nil
  record.command_position = nil
  record.command_failed = nil
  record.next_update_tick = game.tick + destination_space_delay(record)
end

local function clear_command_tracking(record)
  record.command_target_type = nil
  record.command_target_id = nil
  record.command_position = nil
  record.command_failed = nil
  record.command_tick = nil
  record.command_result = nil
  record.awaiting_route_retry = nil
  reset_route_progress(record)
end

local function try_next_job(record, options)
  options = options or {}
  if has_carried_cargo(record) then return false end
  if record.job_id then return false end
  record.state = "idle"
  clear_command_tracking(record)
  record.next_update_tick = game.tick
  options.failure_callback = options.failure_callback or carriers.on_dispatch_failure
  local assigned = logistics.find_next_job_for_carrier(record, carriers.assign_job, options)
  return assigned == true
end

local function complete_delivery_and_continue(record, job)
  local destination_nest_id = job and job.destination_nest_id
  local item_name = job and job.item_name
  adjust_job_reservation_to_cargo(record)
  if job then
    jobs.complete(job.id, "complete")
  end
  record.job_id = nil
  if destination_nest_id then
    diagnostics.clear_destination_waiting(destination_nest_id, item_name)
  end

  if not try_next_job(record) then
    return_home(record)
  end
end

local function complete_command_success(record)
  diagnostics.clear_route_for_carrier(record.id)
  reset_route_failures(record)
  clear_command_tracking(record)

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
    if not try_next_job(record, {allow_depot_food = true}) then
      record.next_update_tick = game.tick + constants.ticks.idle_delay
    end
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
  ensure_failure_fields(record)

  if is_moving_state(record) then
    local target_record, target_type, target_id = target_for_state(record)
    local commandable = record.entity.commandable
    local command_ended = not commandable or not commandable.has_command
    local route_state = record.state
    local command_timed_out = record.command_tick
      and game.tick - record.command_tick >= constants.ticks.command_timeout

    if target_record and valid(target_record.entity) then
      update_route_progress(record, target_record, target_type, target_id, route_state)
    end

    if (record.command_position
        and is_near_position(record, record.command_position, constants.command.interaction_radius))
      or is_near_record(record, target_record) then
      if complete_command_success(record) then
        update_record(record)
      end
      return
    end

    if not target_record or not valid(target_record.entity) then
      if has_carried_cargo(record) then spill_cargo(record) end
      clear_job(record, "target_invalid")
      return_home(record)
      return
    end

    if record.awaiting_route_retry then
      if not issue_command(record, target_record, target_type, target_id, route_state) then
        if not record_route_failure(record, target_record, target_type, target_id, route_state) then
          schedule_route_retry(record)
        end
      end
      return
    end

    if record.command_failed or record.command_result == "fail" then
      if not record_route_failure(record, target_record, target_type, target_id, route_state) then
        schedule_route_retry(record)
      end
      return
    end

    if command_ended then
      if record.command_result == "deleted" or record.command_result == "other" then
        schedule_route_retry(record)
      elseif not record_route_failure(record, target_record, target_type, target_id, route_state) then
        schedule_route_retry(record)
      end
      return
    end

    if command_timed_out then
      if route_has_stalled(record) then
        if not record_route_failure(record, target_record, target_type, target_id, route_state) then
          schedule_route_retry(record)
        end
      elseif not issue_command(record, target_record, target_type, target_id, route_state) then
        if not record_route_failure(record, target_record, target_type, target_id, route_state) then
          schedule_route_retry(record)
        end
      end
      return
    end

    record.next_update_tick = game.tick + constants.ticks.command_check_interval
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
      record.state = "returning"
      if not record_route_failure(record, home, "depot", home.id, "returning") then
        schedule_route_retry(record)
      end
    end
    return
  end

  if record.state == "loading" then
    local job = jobs.get(record.job_id)
    local source = job and nests.get(job.source_nest_id)
    local destination = job and nests.get(job.destination_nest_id)
    if not job or not nests.is_valid(source) then
      clear_job(record, "source_invalid")
      return_home(record)
      return
    end
    if not nests.is_valid(destination) then
      clear_job(record, "destination_invalid")
      return_home(record)
      return
    end

    local loaded = load_cargo_from_source(record, source, job)
    if loaded <= 0 or not has_carried_cargo(record) then
      clear_job(record, "no_supply")
      return_home(record)
      return
    end

    jobs.set_state(record.job_id, "to_destination")
    if not issue_command(record, destination, "nest", destination.id, "to_destination") then
      record.state = "to_destination"
      if not record_route_failure(record, destination, "nest", destination.id, "to_destination") then
        schedule_route_retry(record)
      end
    end
    return
  end

  if record.state == "unloading" then
    local job = jobs.get(record.job_id)
    local destination = job and nests.get(job.destination_nest_id)
    if not has_carried_cargo(record) then
      if job then
        complete_delivery_and_continue(record, job)
      else
        return_home(record)
      end
      return
    end

    if not nests.is_valid(destination) then
      spill_cargo(record)
      clear_job(record, "destination_invalid")
      return_home(record)
      return
    end

    insert_all_cargo(record, destination)
    adjust_job_reservation_to_cargo(record)
    if has_carried_cargo(record) then
      diagnostics.destination_waiting(record, destination, job.item_name)
      wait_for_destination_space(record)
      return
    end

    diagnostics.clear_destination_waiting(job.destination_nest_id, job.item_name)
    complete_delivery_and_continue(record, job)
    return
  end

  if record.state == "waiting_for_destination_space" then
    local job = jobs.get(record.job_id)
    local destination = job and nests.get(job.destination_nest_id)

    if not has_carried_cargo(record) then
      if job then
        complete_delivery_and_continue(record, job)
      else
        return_home(record)
      end
      return
    end

    if not job or not nests.is_valid(destination) then
      spill_cargo(record)
      clear_job(record, "destination_invalid")
      return_home(record)
      return
    end

    if not is_near_record(record, destination) then
      jobs.set_state(record.job_id, "to_destination")
      if not issue_command(record, destination, "nest", destination.id, "to_destination") then
        record.state = "to_destination"
        if not record_route_failure(record, destination, "nest", destination.id, "to_destination") then
          schedule_route_retry(record)
        end
      end
      return
    end

    insert_all_cargo(record, destination)
    adjust_job_reservation_to_cargo(record)
    if has_carried_cargo(record) then
      diagnostics.destination_waiting(record, destination, job.item_name)
      wait_for_destination_space(record)
      return
    end

    diagnostics.clear_destination_waiting(job.destination_nest_id, job.item_name)
    complete_delivery_and_continue(record, job)
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
  reset_starvation_failures(record)
  reset_route_failures(record)
  if is_near_record(record, source) then
    record.state = "loading"
    record.next_update_tick = game.tick
    update_record(record)
    return true
  end

  if not issue_command(record, source, "nest", source.id, "to_source") then
    record.state = "to_source"
    if record_route_failure(record, source, "nest", source.id, "to_source") then
      return false
    end
    schedule_route_retry(record)
    return true
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

local function record_starvation_failure(record, context)
  if not record or record.job_id or record.state ~= "idle" or not valid(record.entity) then
    return false
  end

  ensure_failure_fields(record)
  if record.last_starvation_failure_tick
    and game.tick - record.last_starvation_failure_tick < constants.feral.failure_interval then
    return false
  end

  record.starvation_failures = record.starvation_failures + 1
  record.last_starvation_failure_tick = game.tick
  diagnostics.carrier_starvation(
    record,
    context and context.depot or nil,
    context and context.request or nil,
    context and context.item_name or nil,
    record.starvation_failures
  )

  if record.starvation_failures >= constants.feral.failure_threshold then
    return carriers.feralize(record, "starvation")
  end

  return false
end

function carriers.on_dispatch_failure(reason, record, context)
  if reason ~= "food_shortage" then return false end
  return record_starvation_failure(record, context)
end

function carriers.on_ai_command_completed(event)
  local data = state.get()
  local id = data.carrier_by_unit_number[event.unit_number]
  local record = id and data.carriers[id] or nil
  if not record then return end

  record.next_update_tick = game.tick
  if event.result == defines.behavior_result.success then
    record.command_failed = nil
    record.command_result = "success"
  elseif event.result == defines.behavior_result.fail then
    record.command_failed = true
    record.command_result = "fail"
  elseif event.result == defines.behavior_result.deleted then
    record.command_failed = nil
    record.command_result = "deleted"
  else
    record.command_failed = nil
    record.command_result = "other"
  end

  update_record(record)
end

function carriers.on_entity_damaged(event)
  local entity = event.entity
  if not valid(entity) or entity.name ~= constants.carrier_unit then return end
  if not event.final_damage_amount or event.final_damage_amount <= 0 then return end

  local data = state.get()
  local id = data.carrier_by_unit_number[entity.unit_number]
  local record = id and data.carriers[id] or nil
  if record then
    carriers.feralize(record, "damage", {entity = entity})
  end
end

function carriers.on_entity_died(event)
  local entity = event.entity
  if not valid(entity) or entity.name ~= constants.carrier_unit then return end

  local data = state.get()
  local id = data.carrier_by_unit_number[entity.unit_number]
  local record = id and data.carriers[id] or nil
  if record then
    carriers.feralize(record, "damage", {entity = entity, entity_already_dead = true})
  end
end

function carriers.remove(id, options)
  options = options or {}
  local data = state.get()
  local record = data.carriers[id]
  if not record then return end
  diagnostics.clear_for_carrier(id)

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
        if has_carried_cargo(record) then spill_cargo(record) end
        clear_job(record, "nest_removed")
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
        if has_carried_cargo(record) then spill_cargo(record) end
        clear_job(record, "depot_removed")
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
      ensure_failure_fields(record)
      normalise_cargo_slots(record)
      research.apply_to_carrier(record)
      local home = depots.get(record.home_depot_id)
      if home then
        home.carrier_ids = home.carrier_ids or {}
        home.carrier_ids[id] = true
      end

      local job = record.job_id and jobs.get(record.job_id)
      if record.job_id and not job then
        record.job_id = nil
      elseif job and not nests.is_valid(nests.get(job.source_nest_id)) then
        if has_carried_cargo(record) then spill_cargo(record) end
        clear_job(record, "source_invalid")
        return_home(record)
      elseif job and not nests.is_valid(nests.get(job.destination_nest_id)) then
        if has_carried_cargo(record) then spill_cargo(record) end
        clear_job(record, "destination_invalid")
        return_home(record)
      end

      enqueue(data, id)
    elseif record then
      carriers.remove(id, {spill_cargo = true, return_carrier_item = true, destroy_entity = valid(record.entity)})
    end
  end
end

return carriers

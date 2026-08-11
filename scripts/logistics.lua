local constants = require("constants")
local state = require("scripts.state")
local nests = require("scripts.nests")
local depots = require("scripts.depots")
local jobs = require("scripts.jobs")
local research = require("scripts.research")
local food = require("scripts.food")
local networks = require("scripts.networks")
local diagnostics = require("scripts.diagnostics")
local indexes = require("scripts.indexes")

local logistics = {}

local function request_key(nest_id, item_name)
  return tostring(nest_id or "-") .. "|" .. tostring(item_name or "-")
end

local function copy_position(position)
  if not position then return nil end
  return {x = position.x, y = position.y}
end

local function entry_key(entry)
  if type(entry) == "table" then
    return entry.key or request_key(entry.nest_id, entry.item_name)
  end
  return tostring(entry)
end

local function enqueue_request_entry(data, nest_id, item_name, generator)
  if not nest_id or not item_name then return end
  local key = request_key(nest_id, item_name)
  if data.request_queued[key] then return end
  data.request_queue[#data.request_queue + 1] = {
    key = key,
    nest_id = nest_id,
    item_name = item_name,
    generator = generator
  }
  data.request_queued[key] = true
end

local function dequeue_current(data, index)
  local entry = table.remove(data.request_queue, index)
  if entry then data.request_queued[entry_key(entry)] = nil end
  if data.request_cursor >= index then
    data.request_cursor = math.max(data.request_cursor - 1, 0)
  end
  return entry
end

local function remove_request_entry(data, key)
  if not key then return end
  for index = #data.request_queue, 1, -1 do
    if entry_key(data.request_queue[index]) == key then
      table.remove(data.request_queue, index)
      if data.request_cursor >= index then
        data.request_cursor = math.max(data.request_cursor - 1, 0)
      end
      break
    end
  end
  data.request_queued[key] = nil
end

local function stack_size(item_name)
  local prototype = prototypes.item[item_name]
  return prototype and prototype.stack_size or 0
end

function logistics.enqueue_request(nest_id, item_name, generator)
  local data = state.get()
  if item_name then
    enqueue_request_entry(data, nest_id, item_name, generator)
    return
  end

  local record = nests.get(nest_id)
  if nests.is_valid(record) then
    nests.enqueue_request_entries(record, function(id, queued_item_name, queued_generator)
      enqueue_request_entry(data, id, queued_item_name, queued_generator)
    end)
  end
end

function logistics.enqueue_all_requests()
  local data = state.get()
  for id, record in pairs(data.nests) do
    if nests.is_valid(record) and record.mode == constants.nest_modes.request then
      nests.enqueue_request_entries(record, function(_, item_name, generator)
        enqueue_request_entry(data, id, item_name, generator)
      end)
    end
  end
end

local function better_candidate(score, source, depot, best_score, best_source, best_depot)
  if not best_score or score < best_score then return true end
  if score ~= best_score then return false end
  if not best_depot or depot.id < best_depot.id then return true end
  if depot.id ~= best_depot.id then return false end
  return best_source and source.id < best_source.id
end

local function origin_for_depot(depot, options)
  if options and options.origin_position then
    return {
      position = copy_position(options.origin_position),
      force_name = depot.force_name,
      surface_index = depot.surface_index
    }
  end
  return depot
end

local function candidate_carrier_for_depot(depot, options)
  if options and options.carrier then
    local carrier = options.carrier
    if not carrier.entity or not carrier.entity.valid then return nil end
    if carrier.job_id then return nil end
    if carrier.state ~= "idle" then return nil end
    if carrier.home_depot_id ~= depot.id then return nil end
    if carrier.force_name ~= depot.force_name or carrier.surface_index ~= depot.surface_index then return nil end
    food.ensure_carrier_fields(carrier)
    return carrier
  end

  return depots.find_idle_carrier(depot)
end

local function depot_food_can_cover(depot, carrier, required_food, allow_depot_food, depot_food_energy)
  if carrier.food_energy >= required_food then return true, depot_food_energy end
  if not allow_depot_food then return false, depot_food_energy end
  depot_food_energy = depot_food_energy or depots.available_food_energy(depot)
  return depot_food_energy + carrier.food_energy >= required_food, depot_food_energy
end

local function reset_carrier_starvation_failures(carrier)
  if not carrier then return end
  carrier.starvation_failures = 0
  carrier.last_starvation_failure_tick = nil
end

local function notify_dispatch_failure(callback, reason, carrier, context)
  if callback and carrier then
    callback(reason, carrier, context or {})
  end
end

local function find_delivery_candidate(request, item_name, options)
  options = options or {}
  local data = state.get()
  local scoped_nest_ids = indexes.nest_ids(request.force_name, request.surface_index)
  local scoped_depot_ids = indexes.depot_ids(request.force_name, request.surface_index)
  local available_cache = {}
  local best_source = nil
  local best_depot = nil
  local best_carrier = nil
  local best_food_plan = nil
  local best_score = nil
  local has_supply = false
  local has_ranged_supply = false
  local has_idle_carrier = false
  local food_shortage_depot = nil
  local food_shortage_context = nil
  local allow_depot_food = options.allow_depot_food ~= false

  local function available_supply(source)
    if available_cache[source.id] == nil then
      available_cache[source.id] = nests.available_supply_count(source, item_name)
    end
    return available_cache[source.id]
  end

  for source_id in pairs(scoped_nest_ids) do
    local source = data.nests[source_id]
    if source
      and source.id ~= request.id
      and source.mode == constants.nest_modes.supply
      and nests.is_valid(source)
      and available_supply(source) > 0 then
      has_supply = true
      break
    end
  end

  local function evaluate_depot(depot)
    if depots.is_valid(depot) and networks.depot_covers_nest(depot, request) then
      local carrier = candidate_carrier_for_depot(depot, options)
      local depot_food_energy = nil
      local origin = origin_for_depot(depot, options)
      for source_id in pairs(scoped_nest_ids) do
        local source = data.nests[source_id]
        if source
          and source.id ~= request.id
          and source.mode == constants.nest_modes.supply
          and nests.is_valid(source)
          and networks.depot_covers_nest(depot, source)
          and available_supply(source) > 0 then
          has_ranged_supply = true
          local food_plan = food.estimate_delivery_plan(origin, source, request, depot)
          if carrier then
            has_idle_carrier = true
            if food_plan.required_food <= carrier.food_capacity then
              local can_cover
              can_cover, depot_food_energy = depot_food_can_cover(
                depot,
                carrier,
                food_plan.required_food,
                allow_depot_food,
                depot_food_energy
              )
              if can_cover then
                local score = networks.delivery_distance(origin, source, request)
                if better_candidate(score, source, depot, best_score, best_source, best_depot) then
                  best_source = source
                  best_depot = depot
                  best_carrier = carrier
                  best_food_plan = food_plan
                  best_score = score
                end
              else
                food_shortage_depot = food_shortage_depot or depot
                food_shortage_context = food_shortage_context or {
                  carrier = carrier,
                  depot = depot,
                  request = request,
                  source = source,
                  item_name = item_name,
                  food_plan = food_plan
                }
              end
            else
              food_shortage_depot = food_shortage_depot or depot
            end
          end
        end
      end
    end
  end

  if options.home_depot then
    evaluate_depot(options.home_depot)
  else
    for depot_id in pairs(scoped_depot_ids) do
      evaluate_depot(data.depots[depot_id])
    end
  end

  local failure = nil
  if not best_source then
    if not has_supply then
      failure = "no_supply"
    elseif not has_ranged_supply then
      failure = "supply_out_of_depot_range"
    elseif not has_idle_carrier then
      failure = "all_carriers_busy"
    else
      failure = "food_shortage"
    end
  end

  return best_source,
    best_depot,
    best_carrier,
    best_food_plan,
    failure,
    food_shortage_depot,
    best_score,
    food_shortage_context
end

local function normalise_request_entry(entry)
  if type(entry) == "table" then
    return entry.nest_id, entry.item_name, entry.generator
  end

  local request = nests.get(entry)
  return entry, request and request.request_item or nil, "simple-request"
end

local function process_request(entry, assign_callback, failure_callback)
  local request_id, item_name, generator = normalise_request_entry(entry)
  local request = nests.get(request_id)
  local check_tick = game.tick
  if not nests.is_valid(request) then
    diagnostics.clear_for_request(request_id)
    return
  end
  if not nests.request_item_is_current(request, item_name) then
    if nests.request_blocking_reason(request, item_name) then
      diagnostics.clear_unseen_for_request(request_id, check_tick, item_name)
    else
      diagnostics.clear_for_request(request_id, item_name)
    end
    return
  end

  local item_stack_size = stack_size(item_name)
  if item_stack_size <= 0 then
    diagnostics.clear_for_request(request.id, item_name)
    return
  end

  local free = nests.free_space_for_item(request, item_name)
  if free <= 0 then
    diagnostics.request_full(request, item_name)
    diagnostics.clear_unseen_for_request(request.id, check_tick, item_name)
    return
  end

  local demand = nests.request_demand(request, item_name)
  if demand <= 0 then
    diagnostics.clear_for_request(request.id, item_name)
    return
  end

  local source, depot, carrier, food_plan, failure, failure_depot, _, failure_context = find_delivery_candidate(request, item_name)
  if not source or not depot or not carrier then
    if failure == "no_supply" then
      diagnostics.no_supply(request, item_name)
    elseif failure == "supply_out_of_depot_range" then
      diagnostics.supply_out_of_depot_range(request, item_name)
    elseif failure == "all_carriers_busy" then
      diagnostics.all_carriers_busy(request, item_name)
    elseif failure == "food_shortage" then
      diagnostics.food_shortage(failure_depot, request, item_name)
      notify_dispatch_failure(
        failure_callback,
        "food_shortage",
        failure_context and failure_context.carrier,
        failure_context
      )
    end
    diagnostics.clear_unseen_for_request(request.id, check_tick, item_name)
    return
  end

  local available = nests.available_supply_count(source, item_name)
  if available <= 0 then
    diagnostics.clear_unseen_for_request(request.id, check_tick, item_name)
    return
  end

  if carrier.food_energy < food_plan.required_food and not depots.consume_food(depot, carrier, food_plan.required_food) then
    diagnostics.food_shortage(depot, request, item_name)
    notify_dispatch_failure(failure_callback, "food_shortage", carrier, {
      depot = depot,
      request = request,
      source = source,
      item_name = item_name,
      food_plan = food_plan
    })
    diagnostics.clear_unseen_for_request(request.id, check_tick, item_name)
    return
  end
  reset_carrier_starvation_failures(carrier)

  local capacity = research.carrier_capacity_for_force_name(request.force_name) * item_stack_size
  local requested_count = math.min(demand, available, capacity)
  if requested_count <= 0 then
    diagnostics.clear_unseen_for_request(request.id, check_tick, item_name)
    return
  end

  local job = jobs.create{
    source_nest_id = source.id,
    destination_nest_id = request.id,
    carrier_id = carrier.id,
    home_depot_id = depot.id,
    item_name = item_name,
    requested_count = requested_count,
    generator = generator or nests.request_generator(request)
  }

  if assign_callback(carrier, job) then
    carrier.food_energy = math.max(0, carrier.food_energy - food_plan.delivery_cost)
    reset_carrier_starvation_failures(carrier)
  else
    jobs.complete(job.id, "assign_failed")
  end
  diagnostics.clear_unseen_for_request(request.id, check_tick, item_name)
end

local function enqueue_requests_for_depot(depot)
  if not depots.is_valid(depot) then return end
  local data = state.get()
  local scoped_nest_ids = indexes.nest_ids(depot.force_name, depot.surface_index)
  for nest_id in pairs(scoped_nest_ids) do
    local request = data.nests[nest_id]
    if nests.is_valid(request)
      and request.mode == constants.nest_modes.request
      and networks.depot_covers_nest(depot, request) then
      nests.enqueue_request_entries(request, function(id, item_name, generator)
        enqueue_request_entry(data, id, item_name, generator)
      end)
    end
  end
end

local function continuous_candidate(entry, carrier, home, origin_position, allow_depot_food)
  local request_id, item_name, generator = normalise_request_entry(entry)
  local request = nests.get(request_id)
  if not nests.is_valid(request) then return nil, "request_invalid" end
  if not networks.depot_covers_nest(home, request) then return nil, "request_out_of_depot_range" end
  if not nests.request_item_is_current(request, item_name) then return nil, "request_not_current" end

  local item_stack_size = stack_size(item_name)
  if item_stack_size <= 0 then return nil, "invalid_item" end
  if nests.free_space_for_item(request, item_name) <= 0 then return nil, "request_full" end

  local demand = nests.request_demand(request, item_name)
  if demand <= 0 then return nil, "no_demand" end

  local source, depot, candidate_carrier, food_plan, failure, _, score, failure_context = find_delivery_candidate(request, item_name, {
    carrier = carrier,
    home_depot = home,
    origin_position = origin_position,
    allow_depot_food = allow_depot_food
  })
  if not source or not depot or not candidate_carrier then return nil, failure or "no_candidate", failure_context end

  local available = nests.available_supply_count(source, item_name)
  if available <= 0 then return nil, "no_supply" end

  local capacity = research.carrier_capacity_for_force_name(carrier.force_name or request.force_name) * item_stack_size
  local requested_count = math.min(demand, available, capacity)
  if requested_count <= 0 then return nil, "no_demand" end

  return {
    key = entry_key(entry),
    source = source,
    destination = request,
    depot = depot,
    carrier = candidate_carrier,
    item_name = item_name,
    requested_count = requested_count,
    generator = generator or nests.request_generator(request),
    food_plan = food_plan,
    score = score or math.huge
  }
end

local function better_continuous_candidate(candidate, best)
  if not best then return true end
  if candidate.score ~= best.score then return candidate.score < best.score end
  if candidate.destination.id ~= best.destination.id then
    return candidate.destination.id < best.destination.id
  end
  return candidate.source.id < best.source.id
end

function logistics.find_next_job_for_carrier(carrier, assign_callback, options)
  options = options or {}
  if not carrier or not carrier.entity or not carrier.entity.valid then
    return false, "carrier_invalid"
  end
  if carrier.job_id then return false, "carrier_busy" end
  if not assign_callback then return false, "assign_callback_missing" end

  food.ensure_carrier_fields(carrier)
  local home = depots.get(carrier.home_depot_id)
  if not depots.is_valid(home) then return false, "home_depot_invalid" end
  if carrier.force_name ~= home.force_name or carrier.surface_index ~= home.surface_index then
    return false, "carrier_scope_mismatch"
  end

  enqueue_requests_for_depot(home)

  local data = state.get()
  local origin_position = copy_position(carrier.entity.position)
  local allow_depot_food = options.allow_depot_food == true
  local best = nil
  local last_failure = "no_request"
  local food_shortage_context = nil

  for _, entry in ipairs(data.request_queue) do
    local candidate, failure, failure_context = continuous_candidate(entry, carrier, home, origin_position, allow_depot_food)
    if candidate then
      if better_continuous_candidate(candidate, best) then
        best = candidate
      end
    else
      last_failure = failure or last_failure
      if failure == "food_shortage" and failure_context then
        food_shortage_context = food_shortage_context or failure_context
      end
    end
  end

  if not best then
    if food_shortage_context then
      notify_dispatch_failure(
        options.failure_callback,
        "food_shortage",
        food_shortage_context.carrier,
        food_shortage_context
      )
    end
    return false, last_failure
  end

  if allow_depot_food
    and carrier.food_energy < best.food_plan.required_food
    and not depots.consume_food(home, carrier, best.food_plan.required_food) then
    notify_dispatch_failure(options.failure_callback, "food_shortage", carrier, {
      depot = home,
      request = best.destination,
      source = best.source,
      item_name = best.item_name,
      food_plan = best.food_plan
    })
    return false, "food_shortage"
  end
  reset_carrier_starvation_failures(carrier)

  remove_request_entry(data, best.key)
  local job = jobs.create{
    source_nest_id = best.source.id,
    destination_nest_id = best.destination.id,
    carrier_id = carrier.id,
    home_depot_id = best.depot.id,
    item_name = best.item_name,
    requested_count = best.requested_count,
    generator = best.generator
  }

  if assign_callback(carrier, job) then
    carrier.food_energy = math.max(0, carrier.food_energy - best.food_plan.delivery_cost)
    reset_carrier_starvation_failures(carrier)
    return true, "assigned", job
  end

  jobs.complete(job.id, "assign_failed")
  return false, "assign_failed"
end

function logistics.process_batch(assign_callback, failure_callback)
  local data = state.get()
  local queue = data.request_queue
  local length = #queue
  if length == 0 then return end

  local processed = 0
  local examined = 0
  while processed < constants.ticks.requests_per_update and examined < length do
    data.request_cursor = (data.request_cursor % #queue) + 1
    local index = data.request_cursor
    local entry = dequeue_current(data, index)
    if entry then
      process_request(entry, assign_callback, failure_callback)
      processed = processed + 1
    end
    if #queue == 0 then break end
    examined = examined + 1
  end
end

return logistics

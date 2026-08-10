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

local function find_delivery_candidate(request, item_name)
  local data = state.get()
  local scoped_nest_ids = indexes.nest_ids(request.force_name, request.surface_index)
  local scoped_depot_ids = indexes.depot_ids(request.force_name, request.surface_index)
  local available_cache = {}
  local best_source = nil
  local best_depot = nil
  local best_carrier = nil
  local best_required_food = nil
  local best_score = nil
  local has_supply = false
  local has_ranged_supply = false
  local has_idle_carrier = false
  local food_shortage_depot = nil

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

  for depot_id in pairs(scoped_depot_ids) do
    local depot = data.depots[depot_id]
    if depots.is_valid(depot) and networks.depot_covers_nest(depot, request) then
      local carrier = depots.find_idle_carrier(depot)
      local depot_food_energy = nil
      for source_id in pairs(scoped_nest_ids) do
        local source = data.nests[source_id]
        if source
          and source.id ~= request.id
          and source.mode == constants.nest_modes.supply
          and nests.is_valid(source)
          and networks.depot_covers_nest(depot, source)
          and available_supply(source) > 0 then
          has_ranged_supply = true
          local required_food = food.estimate_job_cost(depot, source, request)
          if carrier then
            has_idle_carrier = true
            if required_food <= carrier.food_capacity then
              depot_food_energy = depot_food_energy or depots.available_food_energy(depot)
              if carrier.food_energy >= required_food or depot_food_energy + carrier.food_energy >= required_food then
                local score = networks.route_distance(depot, source, request)
                if better_candidate(score, source, depot, best_score, best_source, best_depot) then
                  best_source = source
                  best_depot = depot
                  best_carrier = carrier
                  best_required_food = required_food
                  best_score = score
                end
              else
                food_shortage_depot = food_shortage_depot or depot
              end
            else
              food_shortage_depot = food_shortage_depot or depot
            end
          end
        end
      end
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

  return best_source, best_depot, best_carrier, best_required_food, failure, food_shortage_depot
end

local function normalise_request_entry(entry)
  if type(entry) == "table" then
    return entry.nest_id, entry.item_name, entry.generator
  end

  local request = nests.get(entry)
  return entry, request and request.request_item or nil, "simple-request"
end

local function process_request(entry, assign_callback)
  local request_id, item_name, generator = normalise_request_entry(entry)
  local request = nests.get(request_id)
  if not nests.is_valid(request) then
    diagnostics.clear_for_request(request_id)
    return
  end
  if not nests.request_item_is_current(request, item_name) then
    diagnostics.clear_for_request(request_id, item_name)
    return
  end

  local check_tick = game.tick
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

  local source, depot, carrier, required_food, failure, failure_depot = find_delivery_candidate(request, item_name)
  if not source or not depot or not carrier then
    if failure == "no_supply" then
      diagnostics.no_supply(request, item_name)
    elseif failure == "supply_out_of_depot_range" then
      diagnostics.supply_out_of_depot_range(request, item_name)
    elseif failure == "all_carriers_busy" then
      diagnostics.all_carriers_busy(request, item_name)
    elseif failure == "food_shortage" then
      diagnostics.food_shortage(failure_depot, request, item_name)
    end
    diagnostics.clear_unseen_for_request(request.id, check_tick, item_name)
    return
  end

  local available = nests.available_supply_count(source, item_name)
  if available <= 0 then
    diagnostics.clear_unseen_for_request(request.id, check_tick, item_name)
    return
  end

  if carrier.food_energy < required_food and not depots.consume_food(depot, carrier, required_food) then
    diagnostics.food_shortage(depot, request, item_name)
    diagnostics.clear_unseen_for_request(request.id, check_tick, item_name)
    return
  end

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
    carrier.food_energy = math.max(0, carrier.food_energy - required_food)
  else
    jobs.complete(job.id, "assign_failed")
  end
  diagnostics.clear_unseen_for_request(request.id, check_tick, item_name)
end

function logistics.process_batch(assign_callback)
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
      process_request(entry, assign_callback)
      processed = processed + 1
    end
    if #queue == 0 then break end
    examined = examined + 1
  end
end

return logistics

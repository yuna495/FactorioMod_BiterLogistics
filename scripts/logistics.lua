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

local function enqueue_request_id(data, nest_id)
  if not nest_id or data.request_queued[nest_id] then return end
  data.request_queue[#data.request_queue + 1] = nest_id
  data.request_queued[nest_id] = true
end

local function dequeue_current(data, index)
  local id = table.remove(data.request_queue, index)
  if id then data.request_queued[id] = nil end
  if data.request_cursor >= index then
    data.request_cursor = math.max(data.request_cursor - 1, 0)
  end
  return id
end

local function stack_size(item_name)
  local prototype = prototypes.item[item_name]
  return prototype and prototype.stack_size or 0
end

function logistics.enqueue_request(nest_id)
  enqueue_request_id(state.get(), nest_id)
end

function logistics.enqueue_all_requests()
  local data = state.get()
  for id, record in pairs(data.nests) do
    if nests.is_valid(record)
      and record.mode == constants.nest_modes.request
      and record.request_item then
      enqueue_request_id(data, id)
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

local function process_request(request_id, assign_callback)
  local request = nests.get(request_id)
  if not nests.is_valid(request) then return end
  if request.mode ~= constants.nest_modes.request or not request.request_item then return end

  local item_name = request.request_item
  local item_stack_size = stack_size(item_name)
  if item_stack_size <= 0 then return end

  local free = nests.free_space_for_item(request, item_name)
  if free <= 0 then
    diagnostics.request_full(request, item_name)
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
    return
  end

  local available = nests.available_supply_count(source, item_name)
  if available <= 0 then return end

  if carrier.food_energy < required_food and not depots.consume_food(depot, carrier, required_food) then
    diagnostics.food_shortage(depot, request, item_name)
    return
  end

  local capacity = research.carrier_capacity_for_force_name(request.force_name) * item_stack_size
  local requested_count = math.min(free, available, capacity)
  if requested_count <= 0 then return end

  local job = jobs.create{
    source_nest_id = source.id,
    destination_nest_id = request.id,
    carrier_id = carrier.id,
    home_depot_id = depot.id,
    item_name = item_name,
    requested_count = requested_count,
    generator = "logistics-network"
  }

  if assign_callback(carrier, job) then
    carrier.food_energy = math.max(0, carrier.food_energy - required_food)
  else
    jobs.complete(job.id, "assign_failed")
  end
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
    local id = queue[index]
    dequeue_current(data, index)
    if id then
      process_request(id, assign_callback)
      processed = processed + 1
    end
    if #queue == 0 then break end
    examined = examined + 1
  end
end

return logistics

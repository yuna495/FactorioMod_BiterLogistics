local constants = require("constants")
local state = require("scripts.state")
local nests = require("scripts.nests")
local depots = require("scripts.depots")
local jobs = require("scripts.jobs")
local research = require("scripts.research")
local food = require("scripts.food")

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

local function same_network(a, b)
  return a and b
    and a.force_name == b.force_name
    and a.surface_index == b.surface_index
end

local function distance_squared(a, b)
  local dx = a.position.x - b.position.x
  local dy = a.position.y - b.position.y
  return dx * dx + dy * dy
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

local function find_supply(request, item_name)
  local data = state.get()
  local best = nil
  local best_score = nil

  for _, candidate in pairs(data.nests) do
    if candidate.id ~= request.id
      and candidate.mode == constants.nest_modes.supply
      and nests.is_valid(candidate)
      and same_network(request, candidate) then
      local available = nests.available_supply_count(candidate, item_name)
      if available > 0 then
        local score = distance_squared(request, candidate)
        if not best_score or score < best_score then
          best = candidate
          best_score = score
        end
      end
    end
  end

  return best
end

local function find_depot_and_carrier(source, request)
  local data = state.get()
  local best_depot = nil
  local best_carrier = nil
  local best_required_food = nil
  local best_score = nil

  for _, depot in pairs(data.depots) do
    if depots.is_valid(depot) and same_network(request, depot) then
      local carrier = depots.find_idle_carrier(depot)
      local required_food = food.estimate_job_cost(depot, source, request)
      if carrier
        and required_food <= carrier.food_capacity
        and (carrier.food_energy >= required_food or depots.available_food_energy(depot) + carrier.food_energy >= required_food) then
        local score = distance_squared(depot, source) + distance_squared(depot, request)
        if not best_score or score < best_score then
          best_depot = depot
          best_carrier = carrier
          best_required_food = required_food
          best_score = score
        end
      end
    end
  end

  return best_depot, best_carrier, best_required_food
end

local function process_request(request_id, assign_callback)
  local request = nests.get(request_id)
  if not nests.is_valid(request) then return end
  if request.mode ~= constants.nest_modes.request or not request.request_item then return end

  local item_name = request.request_item
  local item_stack_size = stack_size(item_name)
  if item_stack_size <= 0 then return end

  local free = nests.free_space_for_item(request, item_name)
  if free <= 0 then return end

  local source = find_supply(request, item_name)
  if not source then return end

  local available = nests.available_supply_count(source, item_name)
  if available <= 0 then return end

  local depot, carrier, required_food = find_depot_and_carrier(source, request)
  if not depot or not carrier then return end

  if carrier.food_energy < required_food and not depots.consume_food(depot, carrier, required_food) then
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

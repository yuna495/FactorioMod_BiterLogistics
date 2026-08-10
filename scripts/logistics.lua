local constants = require("constants")
local state = require("scripts.state")
local nests = require("scripts.nests")
local depots = require("scripts.depots")
local jobs = require("scripts.jobs")
local research = require("scripts.research")
local food = require("scripts.food")
local networks = require("scripts.networks")

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
  local best_source = nil
  local best_depot = nil
  local best_carrier = nil
  local best_required_food = nil
  local best_score = nil

  for _, source in pairs(data.nests) do
    if source.id ~= request.id
      and source.mode == constants.nest_modes.supply
      and nests.is_valid(source)
      and networks.same_force_surface(request, source) then
      local available = nests.available_supply_count(source, item_name)
      if available > 0 then
        for _, depot in pairs(data.depots) do
          if depots.is_valid(depot)
            and networks.same_force_surface(request, depot)
            and networks.depot_covers_nest(depot, source)
            and networks.depot_covers_nest(depot, request) then
            local carrier = depots.find_idle_carrier(depot)
            local required_food = food.estimate_job_cost(depot, source, request)
            if carrier
              and required_food <= carrier.food_capacity
              and (carrier.food_energy >= required_food or depots.available_food_energy(depot) + carrier.food_energy >= required_food) then
              local score = networks.route_distance(depot, source, request)
              if better_candidate(score, source, depot, best_score, best_source, best_depot) then
                best_source = source
                best_depot = depot
                best_carrier = carrier
                best_required_food = required_food
                best_score = score
              end
            end
          end
        end
      end
    end
  end

  return best_source, best_depot, best_carrier, best_required_food
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

  local source, depot, carrier, required_food = find_delivery_candidate(request, item_name)
  if not source or not depot or not carrier then return end

  local available = nests.available_supply_count(source, item_name)
  if available <= 0 then return end

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

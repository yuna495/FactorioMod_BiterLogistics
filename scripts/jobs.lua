local state = require("scripts.state")

local jobs = {}

local function normalise_count(count)
  count = math.floor(tonumber(count) or 0)
  if count < 0 then return 0 end
  return count
end

local function change_reservation(parent, nest_id, item_name, count)
  if not nest_id or not item_name or not count or count == 0 then return end
  local reservations = parent[nest_id]
  if not reservations then
    if count <= 0 then return end
    reservations = {}
    parent[nest_id] = reservations
  end

  local new_count = normalise_count((reservations[item_name] or 0) + count)
  if new_count > 0 then
    reservations[item_name] = new_count
  else
    reservations[item_name] = nil
  end

  if not next(reservations) then
    parent[nest_id] = nil
  end
end

local function reserved_count(parent, nest_id, item_name)
  local reservations = nest_id and parent[nest_id]
  return reservations and reservations[item_name] or 0
end

local function job_reserved_count(job)
  if not job then return 0 end
  return normalise_count(job.reserved_count ~= nil and job.reserved_count or job.requested_count)
end

local function reserve_job(job)
  if not job.item_name then return end
  local data = state.get()
  local count = job_reserved_count(job)
  if count <= 0 then return end
  change_reservation(data.supply_reservations, job.source_nest_id, job.item_name, count)
  change_reservation(data.request_reservations, job.destination_nest_id, job.item_name, count)
end

local function release_job(job)
  if not job.item_name then return end
  local data = state.get()
  local count = job_reserved_count(job)
  if count <= 0 then return end
  change_reservation(data.supply_reservations, job.source_nest_id, job.item_name, -count)
  change_reservation(data.request_reservations, job.destination_nest_id, job.item_name, -count)
  job.reserved_count = 0
end

local function set_reserved_count(job, count)
  if not job or not job.item_name then return false end

  local next_count = normalise_count(count)
  local current_count = job_reserved_count(job)
  if next_count == current_count then
    job.reserved_count = next_count
    return true
  end

  local diff = next_count - current_count
  local data = state.get()
  change_reservation(data.supply_reservations, job.source_nest_id, job.item_name, diff)
  change_reservation(data.request_reservations, job.destination_nest_id, job.item_name, diff)
  job.reserved_count = next_count
  job.updated_tick = game.tick
  return true
end

local function add_expected(parent, nest_id, item_name, count)
  count = normalise_count(count)
  if not nest_id or not item_name or count <= 0 then return end
  parent[nest_id] = parent[nest_id] or {}
  parent[nest_id][item_name] = (parent[nest_id][item_name] or 0) + count
end

local function compare_reservations(label, actual, expected, issues)
  for nest_id, items in pairs(expected) do
    for item_name, count in pairs(items) do
      local actual_count = reserved_count(actual, nest_id, item_name)
      if actual_count ~= count then
        issues[#issues + 1] = label .. " nest #" .. nest_id .. " " .. item_name .. " expected " .. count .. " actual " .. actual_count
      end
    end
  end

  for nest_id, items in pairs(actual) do
    for item_name, count in pairs(items) do
      local expected_count = reserved_count(expected, nest_id, item_name)
      if count < 0 then
        issues[#issues + 1] = label .. " nest #" .. nest_id .. " " .. item_name .. " is negative: " .. count
      elseif count > 0 and expected_count ~= count then
        issues[#issues + 1] = label .. " nest #" .. nest_id .. " " .. item_name .. " unexpected " .. count .. " expected " .. expected_count
      end
    end
  end
end

function jobs.create(params)
  local data = state.get()
  local id = data.next_job_id
  data.next_job_id = id + 1

  local job = {
    id = id,
    source_nest_id = params.source_nest_id,
    destination_nest_id = params.destination_nest_id,
    carrier_id = params.carrier_id,
    home_depot_id = params.home_depot_id,
    item_name = params.item_name,
    requested_count = params.requested_count or 0,
    reserved_count = params.reserved_count or params.requested_count or 0,
    picked_count = 0,
    generator = params.generator or "logistics-network",
    state = "created",
    retry_count = 0,
    failure_reason = false,
    created_tick = game.tick,
    updated_tick = game.tick
  }

  data.jobs[id] = job
  reserve_job(job)
  return job
end

function jobs.get(id)
  return id and state.get().jobs[id] or nil
end

function jobs.set_state(id, job_state)
  local job = jobs.get(id)
  if not job then return end
  job.state = job_state
  job.updated_tick = game.tick
end

function jobs.set_failure(id, reason)
  local job = jobs.get(id)
  if not job then return end
  job.failure_reason = reason or false
  job.updated_tick = game.tick
end

function jobs.set_picked_count(id, count)
  local job = jobs.get(id)
  if not job then return end
  job.picked_count = normalise_count(count)
  job.updated_tick = game.tick
end

function jobs.adjust_reservation_to_count(id, count)
  local job = jobs.get(id)
  if not job then return false end
  return set_reserved_count(job, count)
end

function jobs.adjust_reservation_to_picked_count(id)
  local job = jobs.get(id)
  if not job then return false end
  return set_reserved_count(job, job.picked_count or 0)
end

function jobs.supply_reserved_count(nest_id, item_name)
  return reserved_count(state.get().supply_reservations, nest_id, item_name)
end

function jobs.request_reserved_count(nest_id, item_name)
  return reserved_count(state.get().request_reservations, nest_id, item_name)
end

function jobs.complete(id, result)
  local data = state.get()
  local job = data.jobs[id]
  if not job then return end
  job.state = result or "complete"
  if result and result ~= "complete" then
    job.failure_reason = result
  end
  job.updated_tick = game.tick
  release_job(job)
  data.jobs[id] = nil
end

function jobs.cleanup_orphaned()
  local data = state.get()
  local orphaned = {}
  for id, job in pairs(data.jobs) do
    local carrier = job.carrier_id and data.carriers[job.carrier_id]
    if not carrier or carrier.job_id ~= id then
      orphaned[#orphaned + 1] = id
    end
  end

  for _, id in ipairs(orphaned) do
    jobs.complete(id, "orphaned")
  end
end

function jobs.rebuild_reservations()
  local data = state.get()
  data.supply_reservations = {}
  data.request_reservations = {}

  for _, job in pairs(data.jobs) do
    job.reserved_count = job_reserved_count(job)
    reserve_job(job)
  end
end

function jobs.validate_reservations()
  local data = state.get()
  local expected_supply = {}
  local expected_request = {}
  local issues = {}

  for _, job in pairs(data.jobs) do
    local count = job_reserved_count(job)
    if count > 0 then
      add_expected(expected_supply, job.source_nest_id, job.item_name, count)
      add_expected(expected_request, job.destination_nest_id, job.item_name, count)
    end
  end

  compare_reservations("supply", data.supply_reservations, expected_supply, issues)
  compare_reservations("request", data.request_reservations, expected_request, issues)
  return #issues == 0, issues
end

return jobs

local state = require("scripts.state")

local jobs = {}

local function reservation_table(parent, nest_id)
  if not nest_id then return nil end
  parent[nest_id] = parent[nest_id] or {}
  return parent[nest_id]
end

local function add_reservation(parent, nest_id, item_name, count)
  if not nest_id or not item_name or not count or count == 0 then return end
  local reservations = reservation_table(parent, nest_id)
  reservations[item_name] = math.max(0, (reservations[item_name] or 0) + count)
  if reservations[item_name] == 0 then
    reservations[item_name] = nil
  end
end

local function reserved_count(parent, nest_id, item_name)
  local reservations = nest_id and parent[nest_id]
  return reservations and reservations[item_name] or 0
end

local function reserve_job(job)
  if not job.item_name or not job.requested_count or job.requested_count <= 0 then return end
  local data = state.get()
  add_reservation(data.supply_reservations, job.source_nest_id, job.item_name, job.requested_count)
  add_reservation(data.request_reservations, job.destination_nest_id, job.item_name, job.requested_count)
end

local function release_job(job)
  if not job.item_name or not job.requested_count or job.requested_count <= 0 then return end
  local data = state.get()
  add_reservation(data.supply_reservations, job.source_nest_id, job.item_name, -job.requested_count)
  add_reservation(data.request_reservations, job.destination_nest_id, job.item_name, -job.requested_count)
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
  job.picked_count = count or 0
  job.updated_tick = game.tick
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

return jobs

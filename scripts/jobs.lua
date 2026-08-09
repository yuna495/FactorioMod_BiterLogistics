local state = require("scripts.state")

local jobs = {}

function jobs.create(source_nest_id, destination_nest_id, carrier_id, home_nest_id, generator)
  local data = state.get()
  local id = data.next_job_id
  data.next_job_id = id + 1

  local job = {
    id = id,
    source_nest_id = source_nest_id,
    destination_nest_id = destination_nest_id,
    carrier_id = carrier_id,
    home_nest_id = home_nest_id,
    generator = generator or "fixed-route",
    state = "created",
    created_tick = game.tick,
    updated_tick = game.tick
  }

  data.jobs[id] = job
  return job
end

function jobs.create_fixed_route(carrier_record, home_record)
  if not home_record or not home_record.destination_nest_id then return nil end
  return jobs.create(
    home_record.id,
    home_record.destination_nest_id,
    carrier_record.id,
    home_record.id,
    "fixed-route"
  )
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

function jobs.complete(id, result)
  local data = state.get()
  local job = data.jobs[id]
  if not job then return end
  job.state = result or "complete"
  job.updated_tick = game.tick
  data.jobs[id] = nil
end

return jobs

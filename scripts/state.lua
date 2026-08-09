local state = {}

local function ensure_table(parent, key)
  parent[key] = parent[key] or {}
  return parent[key]
end

function state.get()
  storage.biter_logistics = storage.biter_logistics or {}
  local data = storage.biter_logistics

  data.schema_version = data.schema_version or 1
  data.next_nest_id = data.next_nest_id or 1
  data.next_carrier_id = data.next_carrier_id or 1
  data.next_job_id = data.next_job_id or 1

  ensure_table(data, "nests")
  ensure_table(data, "nest_by_unit_number")
  ensure_table(data, "nest_queue")
  ensure_table(data, "nest_queued")

  ensure_table(data, "carriers")
  ensure_table(data, "carrier_by_unit_number")
  ensure_table(data, "carrier_queue")
  ensure_table(data, "carrier_queued")

  ensure_table(data, "jobs")
  ensure_table(data, "players")
  ensure_table(data, "destroy_registrations")

  data.nest_cursor = data.nest_cursor or 0
  data.carrier_cursor = data.carrier_cursor or 0

  return data
end

return state

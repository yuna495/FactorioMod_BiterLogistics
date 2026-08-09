local state = {}

local function ensure_table(parent, key)
  parent[key] = parent[key] or {}
  return parent[key]
end

local function migrate(data)
  if data.schema_version < 2 then
    for _, job in pairs(data.jobs or {}) do
      if job.retry_count == nil then
        job.retry_count = 0
      end
      if job.failure_reason == nil then
        job.failure_reason = false
      end
    end
    data.schema_version = 2
  end

  if data.schema_version < 3 then
    for _, record in pairs(data.carriers or {}) do
      record.cargo_slots = record.cargo_slots or {}
      if record.cargo and record.cargo.name and record.cargo.count and record.cargo.count > 0 then
        record.cargo_slots[#record.cargo_slots + 1] = record.cargo
      end
      record.cargo = nil
    end
    data.schema_version = 3
  end

  if data.schema_version < 4 then
    for _, nest in pairs(data.nests or {}) do
      nest.destination_nest_id = nil
      nest.carrier_ids = nil
      nest.mode = nest.mode or "supply"
      nest.request_item = nest.request_item or nil
      nest.request_quality = nest.request_quality or "normal"
    end

    for _, carrier in pairs(data.carriers or {}) do
      carrier.legacy_home_nest_id = carrier.home_nest_id
      carrier.home_nest_id = nil
      carrier.home_depot_id = carrier.home_depot_id or nil
      carrier.food_energy = carrier.food_energy or 0
      carrier.food_capacity = carrier.food_capacity or 1000
    end

    data.jobs = {}
    data.supply_reservations = {}
    data.request_reservations = {}
    data.request_queue = {}
    data.request_queued = {}
    data.request_cursor = 0

    data.schema_version = 4
  end
end

function state.get()
  storage.biter_logistics = storage.biter_logistics or {}
  local data = storage.biter_logistics

  data.schema_version = data.schema_version or 1
  data.next_nest_id = data.next_nest_id or 1
  data.next_depot_id = data.next_depot_id or 1
  data.next_carrier_id = data.next_carrier_id or 1
  data.next_job_id = data.next_job_id or 1

  ensure_table(data, "nests")
  ensure_table(data, "nest_by_unit_number")
  ensure_table(data, "nest_queue")
  ensure_table(data, "nest_queued")

  ensure_table(data, "depots")
  ensure_table(data, "depot_by_unit_number")
  ensure_table(data, "depot_queue")
  ensure_table(data, "depot_queued")

  ensure_table(data, "carriers")
  ensure_table(data, "carrier_by_unit_number")
  ensure_table(data, "carrier_queue")
  ensure_table(data, "carrier_queued")

  ensure_table(data, "jobs")
  ensure_table(data, "request_queue")
  ensure_table(data, "request_queued")
  ensure_table(data, "supply_reservations")
  ensure_table(data, "request_reservations")
  ensure_table(data, "players")
  ensure_table(data, "destroy_registrations")
  ensure_table(data, "force_effects")

  data.nest_cursor = data.nest_cursor or 0
  data.depot_cursor = data.depot_cursor or 0
  data.carrier_cursor = data.carrier_cursor or 0
  data.request_cursor = data.request_cursor or 0

  migrate(data)

  return data
end

return state

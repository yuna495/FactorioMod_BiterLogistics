local constants = require("constants")
local state = require("scripts.state")
local nests = require("scripts.nests")
local depots = require("scripts.depots")
local jobs = require("scripts.jobs")
local research = require("scripts.research")
local carriers = require("scripts.carriers")

local debug = {}

local function count_pairs(values)
  local count = 0
  for _ in pairs(values) do
    count = count + 1
  end
  return count
end

local function position_text(position)
  if not position then return "-" end
  return string.format("%.1f,%.1f", position.x, position.y)
end

local function number_text(value)
  if value == nil then return "-" end
  return string.format("%.2f", value)
end

local function valid(entity)
  return entity and entity.valid
end

local function record_position(record)
  if not record then return nil end
  if valid(record.entity) then return record.entity.position end
  return record.position
end

local function distance_between(a, b)
  if not a or not b then return nil end
  local dx = a.x - b.x
  local dy = a.y - b.y
  return math.sqrt(dx * dx + dy * dy)
end

local function test_move_text(record)
  if not record or not record.test_move_position then return "-" end
  return position_text(record.test_move_position)
    .. "/"
    .. tostring(record.test_move_result or "pending")
    .. "@"
    .. tostring(record.test_move_tick or "-")
end

local function destination_candidate_text(record)
  if not record or (not record.destination_candidate_index and not record.destination_candidate_name) then
    return "-"
  end
  return tostring(record.destination_candidate_index or "-")
    .. "/"
    .. tostring(record.destination_candidate_count or "-")
    .. ":"
    .. tostring(record.destination_candidate_name or "-")
end

local function carrier_target_record(data, record, job)
  if not record then return nil end
  if record.state == "to_source" and job then
    return data.nests[job.source_nest_id]
  end
  if record.state == "to_destination" and job then
    return data.nests[job.destination_nest_id]
  end
  if record.state == "returning" then
    local depot_id = (job and job.home_depot_id) or record.home_depot_id
    return data.depots[depot_id]
  end
  return nil
end

local function cargo_stack_text(cargo)
  if not cargo or not cargo.name or not cargo.count or cargo.count <= 0 then return nil end
  if cargo.quality and cargo.quality ~= "normal" then
    return cargo.name .. "/" .. cargo.quality .. " x" .. cargo.count
  end
  return cargo.name .. " x" .. cargo.count
end

local function cargo_text(record)
  local slots = {}
  if record.cargo_slots then
    for _, cargo in ipairs(record.cargo_slots) do
      local text = cargo_stack_text(cargo)
      if text then slots[#slots + 1] = text end
    end
  end

  local legacy_text = cargo_stack_text(record.cargo)
  if legacy_text then slots[#slots + 1] = legacy_text end

  if #slots == 0 then return "-" end
  return table.concat(slots, ", ")
end

local function job_scope_matches_player(job, player)
  if not player then return true end
  local data = state.get()
  local source = job.source_nest_id and data.nests[job.source_nest_id]
  local destination = job.destination_nest_id and data.nests[job.destination_nest_id]
  return (source and source.surface_index == player.surface_index)
    or (destination and destination.surface_index == player.surface_index)
end

local function reservation_scope_matches_player(nest_id, player)
  if not player then return true end
  local record = state.get().nests[nest_id]
  return record and record.surface_index == player.surface_index
end

local function print_reservations(print, player, caption, reservations)
  for nest_id, items in pairs(reservations) do
    if reservation_scope_matches_player(nest_id, player) then
      for item_name, count in pairs(items) do
        if count and count > 0 then
          print({caption, nest_id, item_name, count})
        end
      end
    end
  end
end

local function output_for(command)
  if command.player_index then
    local player = game.get_player(command.player_index)
    if player then
      return function(message) player.print(message) end, player
    end
  end

  return function(message) game.print(message) end, nil
end

function debug.enable_logging(player_index)
  local debug_state = state.get().debug
  debug_state.enabled_until_tick = game.tick + constants.ticks.debug_log_window
  debug_state.player_index = player_index
end

function debug.print_status(command)
  local data = state.get()
  local print, player = output_for(command)
  debug.enable_logging(command.player_index)
  research.rebuild_all(false)

  print({"debug.biter-logistics-header", count_pairs(data.nests), count_pairs(data.depots), count_pairs(data.carriers), game.tick})
  if player then
    local effects = research.effects_for_force_name(player.force.name)
    print({
      "debug.biter-logistics-force-effects",
      player.force.name,
      effects.carrier_capacity_stacks,
      string.format("%.2f", effects.carrier_speed_multiplier),
      effects.nest_cargo_slots,
      effects.depot_range,
      effects.depot_carrier_capacity
    })
  end

  for id, job in pairs(data.jobs) do
    if job_scope_matches_player(job, player) then
      print({
        "debug.biter-logistics-job",
        id,
        job.state or "-",
        job.source_nest_id or "-",
        job.destination_nest_id or "-",
        job.carrier_id or "-",
        job.item_name or "-",
        job.requested_count or 0,
        job.reserved_count or job.requested_count or 0,
        job.picked_count or 0,
        job.generator or "-",
        job.failure_reason or "-"
      })
    end
  end

  print_reservations(print, player, "debug.biter-logistics-supply-reservation", data.supply_reservations)
  print_reservations(print, player, "debug.biter-logistics-request-reservation", data.request_reservations)
  local ok, reservation_issues = jobs.validate_reservations()
  print({"debug.biter-logistics-reservation-validation", ok and "ok" or "failed"})
  if not ok then
    for _, issue in ipairs(reservation_issues) do
      print({"debug.biter-logistics-reservation-issue", issue})
    end
  end

  for id, record in pairs(data.nests) do
    if nests.is_valid(record)
      and (not player or record.surface_index == player.surface_index) then
      print({
        "debug.biter-logistics-nest",
        id,
        record.display_name or "-",
        record.mode or "-",
        record.request_item or "-",
        tostring(nests.has_cargo(record)),
        nests.cargo_slot_count(record)
      })
    end
  end

  for id, record in pairs(data.depots) do
    if depots.is_valid(record)
      and (not player or record.surface_index == player.surface_index) then
      local carrier_count = depots.assigned_carrier_count(record)
      print({
        "debug.biter-logistics-depot",
        id,
        record.display_name or "-",
        depots.count_carrier_items(record),
        carrier_count,
        depots.carrier_capacity(record),
        depots.available_food_energy(record)
      })
    end
  end

  for id, record in pairs(data.carriers) do
    local entity = record.entity
    if entity and entity.valid
      and (not player or entity.surface_index == player.surface_index) then
      local job = jobs.get(record.job_id)
      local has_command = entity.commandable and entity.commandable.has_command or false
      print({
        "debug.biter-logistics-carrier",
        id,
        record.state or "-",
        record.home_depot_id or "-",
        job and (job.id .. "/" .. job.state) or "-",
        cargo_text(record),
        tostring(has_command),
        record.command_kind or "-",
        record.command_result or "-",
        record.command_tick or "-",
        tostring(record.awaiting_route_retry or false),
        record.next_update_tick or "-",
        position_text(entity.position),
        record.food_energy or 0
      })

      local target_record = carrier_target_record(data, record, job)
      local target_position = record_position(target_record)
      local command_target_position = record.command_target_position or target_position
      print({
        "debug.biter-logistics-carrier-route",
        id,
        record.command_target_type or "-",
        record.command_target_id or "-",
        position_text(command_target_position),
        position_text(record.destination_position),
        position_text(record.command_passed_position or record.command_position),
        tostring(record.destination_position_failed or false),
        number_text(distance_between(entity.position, command_target_position)),
        number_text(record.route_best_distance),
        record.route_last_progress_tick or "-",
        position_text(record.route_last_progress_position),
        record.route_failures or 0,
        test_move_text(record),
        destination_candidate_text(record),
        record.destination_candidate_summary or "-"
      })
    end
  end
end

local function parse_test_move_parameter(parameter)
  local carrier_id_text, x_text, y_text =
    string.match(parameter or "", "^%s*(%S+)%s+(%S+)%s+(%S+)%s*$")
  local carrier_id = carrier_id_text and tonumber(carrier_id_text) or nil
  local x = x_text and tonumber(x_text) or nil
  local y = y_text and tonumber(y_text) or nil
  if not carrier_id or carrier_id ~= math.floor(carrier_id) or not x or not y then
    return nil
  end
  return carrier_id, x, y
end

function debug.test_move(command)
  local print = output_for(command)
  debug.enable_logging(command.player_index)
  local carrier_id, x, y = parse_test_move_parameter(command.parameter)
  if not carrier_id then
    print({"debug.biter-logistics-test-move-usage"})
    return
  end

  local position = {x = x, y = y}
  local ok, reason, err = carriers.test_move(carrier_id, position)
  if ok then
    print({"debug.biter-logistics-test-move-issued", carrier_id, position_text(position)})
  elseif reason == "not_found" then
    print({"debug.biter-logistics-test-move-not-found", carrier_id})
  elseif reason == "invalid" then
    print({"debug.biter-logistics-test-move-invalid", carrier_id})
  else
    print({"debug.biter-logistics-test-move-failed", carrier_id, tostring(err or reason or "-")})
  end
end

function debug.register_commands()
  commands.add_command(
    constants.commands.debug,
    {"command-help.biter-logistics-debug"},
    debug.print_status
  )
  commands.add_command(
    constants.commands.test_move,
    {"command-help.biter-logistics-test-move"},
    debug.test_move
  )
end

return debug

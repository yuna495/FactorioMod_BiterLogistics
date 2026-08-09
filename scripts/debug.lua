local constants = require("constants")
local state = require("scripts.state")
local nests = require("scripts.nests")
local jobs = require("scripts.jobs")

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

local function cargo_text(cargo)
  local count = cargo and cargo.count or 0
  if not cargo or not cargo.name or count <= 0 then return "-" end
  if cargo.quality and cargo.quality ~= "normal" then
    return cargo.name .. "/" .. cargo.quality .. " x" .. count
  end
  return cargo.name .. " x" .. count
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

function debug.print_status(command)
  local data = state.get()
  local print, player = output_for(command)
  print({"debug.biter-logistics-header", count_pairs(data.nests), count_pairs(data.carriers), game.tick})

  for id, record in pairs(data.nests) do
    if nests.is_valid(record)
      and (not player or record.surface_index == player.surface_index) then
      local carriers = record.carrier_ids and count_pairs(record.carrier_ids) or 0
      print({
        "debug.biter-logistics-nest",
        id,
        record.display_name or "-",
        record.destination_nest_id or "-",
        tostring(nests.has_cargo(record)),
        nests.count_carrier_items(record),
        carriers
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
        record.home_nest_id or "-",
        job and (job.id .. "/" .. job.state) or "-",
        cargo_text(record.cargo),
        tostring(has_command),
        record.next_update_tick or "-",
        position_text(entity.position),
        record.command_target_nest_id or "-",
        position_text(record.command_position)
      })
    end
  end
end

function debug.register_commands()
  commands.add_command(
    constants.commands.debug,
    {"command-help.biter-logistics-debug"},
    debug.print_status
  )
end

return debug

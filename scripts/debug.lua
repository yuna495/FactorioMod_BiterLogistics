local constants = require("constants")
local state = require("scripts.state")
local nests = require("scripts.nests")
local jobs = require("scripts.jobs")
local research = require("scripts.research")

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
  research.rebuild_all(false)

  print({"debug.biter-logistics-header", count_pairs(data.nests), count_pairs(data.carriers), game.tick})
  if player then
    local effects = research.effects_for_force_name(player.force.name)
    print({
      "debug.biter-logistics-force-effects",
      player.force.name,
      effects.carrier_capacity_stacks,
      string.format("%.2f", effects.carrier_speed_multiplier),
      effects.nest_cargo_slots
    })
  end

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
        cargo_text(record),
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

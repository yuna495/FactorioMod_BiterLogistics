local constants = require("constants")
local state = require("scripts.state")
local nests = require("scripts.nests")
local depots = require("scripts.depots")
local carriers = require("scripts.carriers")
local jobs = require("scripts.jobs")
local gui = require("scripts.gui")

local cleanup = {}

local function valid(entity)
  return entity and entity.valid
end

local function event_entity(event)
  return event.created_entity or event.entity or event.destination
end

function cleanup.on_built(event)
  local entity = event_entity(event)
  if valid(entity) and entity.name == constants.nest_entity then
    nests.register(entity)
  elseif valid(entity) and entity.name == constants.depot_entity then
    depots.register(entity)
  end
end

function cleanup.on_removed(event)
  local entity = event_entity(event)
  if not entity then return end

  if entity.name == constants.nest_entity then
    local record = nests.get_by_entity(entity)
    if not record then return end
    local position = valid(entity) and entity.position or record.position
    carriers.handle_nest_removed(record.id, position, {player_index = event.player_index})
    jobs.cancel_for_nest(record.id, "nest_removed")
    gui.close_nest(record.id)
    nests.remove(record.id)
    return
  end

  if entity.name == constants.depot_entity then
    local record = depots.get_by_entity(entity)
    if not record then return end
    local position = valid(entity) and entity.position or record.position
    carriers.handle_depot_removed(record.id, position, {player_index = event.player_index})
    gui.close_depot(record.id)
    depots.remove(record.id)
    return
  end

  if entity.name == constants.carrier_unit and entity.unit_number then
    carriers.remove_by_unit_number(entity.unit_number, {spill_cargo = true})
  end
end

function cleanup.on_entity_cloned(event)
  if valid(event.destination) and event.destination.name == constants.nest_entity then
    nests.register(event.destination)
  elseif valid(event.destination) and event.destination.name == constants.depot_entity then
    depots.register(event.destination)
  end
end

function cleanup.on_object_destroyed(event)
  local data = state.get()
  local registration = data.destroy_registrations[event.registration_number]
  if not registration then return end
  data.destroy_registrations[event.registration_number] = nil

  if registration.type == "nest" then
    local record = nests.get(registration.id)
    if not record then return end
    carriers.handle_nest_removed(record.id, record.position)
    jobs.cancel_for_nest(record.id, "nest_removed")
    gui.close_nest(record.id)
    nests.remove(record.id)
    return
  end

  if registration.type == "depot" then
    local record = depots.get(registration.id)
    if not record then return end
    carriers.handle_depot_removed(record.id, record.position)
    gui.close_depot(record.id)
    depots.remove(record.id)
    return
  end

  if registration.type == "carrier" then
    carriers.remove(registration.id, {spill_cargo = true})
  end
end

return cleanup

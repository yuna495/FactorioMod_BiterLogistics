local constants = require("constants")
local state = require("scripts.state")

local spawner_egg_loot = {}

local offsets = {
  {x = 1, y = 0},
  {x = -1, y = 0},
  {x = 0, y = 1},
  {x = 0, y = -1},
  {x = 0.7, y = 0.7},
  {x = -0.7, y = 0.7},
  {x = 0.7, y = -0.7},
  {x = -0.7, y = -0.7}
}

local function drop_position(entity)
  local seed = entity.unit_number or game.tick
  local offset = offsets[(seed % #offsets) + 1]
  local radius = constants.spawner_egg_loot.drop_radius
  return {
    x = entity.position.x + offset.x * radius,
    y = entity.position.y + offset.y * radius
  }
end

local function is_eligible_killing_force(force, killed_entity)
  if not force or not force.valid then return false end
  if constants.spawner_egg_loot.ignored_forces[force.name] then return false end
  if killed_entity.force and killed_entity.force.valid and force.name == killed_entity.force.name then return false end
  return true
end

local function killing_force(event, killed_entity)
  if is_eligible_killing_force(event.force, killed_entity) then
    return event.force
  end

  local cause = event.cause
  if cause and cause.valid and is_eligible_killing_force(cause.force, killed_entity) then
    return cause.force
  end

  return nil
end

local function should_drop_for_force(data, force_name)
  local completed = data.spawner_egg_drop.first_drop_completed_by_force
  if not completed[force_name] then
    completed[force_name] = true
    return true
  end

  return math.random() < constants.spawner_egg_loot.drop_chance
end

local function create_flying_text(entity, position, force)
  for _, player in pairs(game.connected_players) do
    if player.force
      and player.force.valid
      and player.force.name == force.name
      and player.surface
      and player.surface.index == entity.surface.index
    then
      player.create_local_flying_text{
        position = position,
        surface = entity.surface,
        text = {"item-name." .. constants.spawner_egg_loot.egg_item},
        color = constants.spawner_egg_loot.flying_text_color
      }
    end
  end
end

local function spill_egg(entity, force)
  local position = drop_position(entity)
  entity.surface.spill_item_stack{
    position = position,
    stack = {name = constants.spawner_egg_loot.egg_item, count = 1},
    allow_belts = false,
    max_radius = constants.spawner_egg_loot.spill_radius,
    use_start_position_on_failure = true,
    drop_full_stack = true
  }
  create_flying_text(entity, position, force)
end

function spawner_egg_loot.on_entity_died(event)
  local entity = event.entity
  if not entity or not entity.valid then return end
  if not constants.spawner_egg_loot.source_spawners[entity.name] then return end
  if not entity.force or not entity.force.valid or entity.force.name ~= "enemy" then return end

  local force = killing_force(event, entity)
  if not force then return end

  local data = state.get()
  if should_drop_for_force(data, force.name) then
    spill_egg(entity, force)
  end
end

return spawner_egg_loot

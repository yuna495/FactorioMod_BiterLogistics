local constants = require("constants")

local biomass_loot = {}

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
  local radius = constants.biomass_loot.drop_radius
  return {
    x = entity.position.x + offset.x * radius,
    y = entity.position.y + offset.y * radius
  }
end

function biomass_loot.on_entity_died(event)
  local entity = event.entity
  if not entity or not entity.valid then return end
  if not constants.biomass_loot.source_spawners[entity.name] then return end

  local count = math.random(constants.biomass_loot.count_min, constants.biomass_loot.count_max)
  entity.surface.spill_item_stack{
    position = drop_position(entity),
    stack = {name = constants.biomass_item, count = count},
    allow_belts = false,
    max_radius = constants.biomass_loot.spill_radius,
    drop_full_stack = true
  }
end

return biomass_loot

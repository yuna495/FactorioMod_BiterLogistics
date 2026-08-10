local constants = require("constants")
local state = require("scripts.state")
local networks = require("scripts.networks")

local food = {}

local function force_effects(force_name)
  return state.get().force_effects[force_name] or {}
end

function food.values_for_force_name(force_name)
  local values = {}
  for name, value in pairs(constants.food.values) do
    if prototypes.item[name] then
      values[name] = value
    end
  end

  if force_effects(force_name).herbivorous_biters then
    for name, value in pairs(constants.food.herbivorous_values) do
      if prototypes.item[name] then
        values[name] = value
      end
    end
    for name, value in pairs(constants.food.space_age_values) do
      if prototypes.item[name] then
        values[name] = value
      end
    end
  end

  return values
end

function food.value_for_item(force_name, item_name)
  return food.values_for_force_name(force_name)[item_name] or 0
end

function food.estimate_job_cost(depot, source, destination)
  local trip = networks.route_distance(depot, source, destination)
  return math.ceil(constants.food.base_job_cost + trip * constants.food.cost_per_tile)
end

function food.ensure_carrier_fields(record)
  record.food_capacity = record.food_capacity or constants.food.carrier_capacity
  record.food_energy = math.min(record.food_energy or 0, record.food_capacity)
end

return food

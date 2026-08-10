local constants = require("constants")
local state = require("scripts.state")
local networks = require("scripts.networks")

local food = {}

local base_food_order = {
  constants.biomass_item,
  "raw-fish"
}

local herbivorous_food_order = {
  "wood"
}

local space_age_food_order = {
  "yumako",
  "jellynut",
  "nutrients"
}

local function force_effects(force_name)
  return state.get().force_effects[force_name] or {}
end

local function append_valid_food(result, values, order)
  for _, name in ipairs(order) do
    local value = values[name]
    if prototypes.item[name] then
      result[#result + 1] = {name = name, value = value}
    end
  end
end

function food.accepted_for_force_name(force_name)
  local result = {}
  append_valid_food(result, constants.food.values, base_food_order)

  if force_effects(force_name).herbivorous_biters then
    append_valid_food(result, constants.food.herbivorous_values, herbivorous_food_order)
    append_valid_food(result, constants.food.space_age_values, space_age_food_order)
  end

  return result
end

function food.values_for_force_name(force_name)
  local values = {}
  for _, entry in ipairs(food.accepted_for_force_name(force_name)) do
    values[entry.name] = entry.value
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

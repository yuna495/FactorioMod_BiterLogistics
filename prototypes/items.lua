local constants = require("constants")

local nest_item = table.deepcopy(data.raw["item"]["steel-chest"])
nest_item.name = constants.nest_item
nest_item.localised_name = {"item-name.biter-logistics-nest"}
nest_item.localised_description = {"item-description.biter-logistics-nest"}
nest_item.icon = "__base__/graphics/icons/biter-spawner.png"
nest_item.place_result = constants.nest_entity
nest_item.subgroup = "storage"
nest_item.order = "z[biter-logistics]-a[nest]"

local carrier_item = {
  type = "item",
  name = constants.carrier_item,
  localised_name = {"item-name.biter-logistics-carrier-biter"},
  localised_description = {"item-description.biter-logistics-carrier-biter"},
  icon = "__base__/graphics/icons/small-biter.png",
  subgroup = "storage",
  order = "z[biter-logistics]-b[carrier-biter]",
  stack_size = 50
}

data:extend({nest_item, carrier_item})

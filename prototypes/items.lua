local constants = require("constants")

local nest_item = table.deepcopy(data.raw["item"]["steel-chest"])
nest_item.name = constants.nest_item
nest_item.localised_name = {"item-name.biter-logistics-nest"}
nest_item.localised_description = {"item-description.biter-logistics-nest"}
nest_item.icon = "__base__/graphics/icons/biter-spawner.png"
nest_item.place_result = constants.nest_entity
nest_item.subgroup = "storage"
nest_item.order = "z[biter-logistics]-a[nest]"

local depot_item = table.deepcopy(data.raw["item"]["steel-chest"])
depot_item.name = constants.depot_item
depot_item.localised_name = {"item-name.biter-logistics-fuel-depot"}
depot_item.localised_description = {"item-description.biter-logistics-fuel-depot"}
depot_item.icon = "__base__/graphics/icons/spitter-spawner.png"
depot_item.place_result = constants.depot_entity
depot_item.subgroup = "storage"
depot_item.order = "z[biter-logistics]-b[fuel-depot]"

local carrier_item = {
  type = "item",
  name = constants.carrier_item,
  localised_name = {"item-name.biter-logistics-carrier-biter"},
  localised_description = {"item-description.biter-logistics-carrier-biter"},
  icon = "__base__/graphics/icons/small-biter.png",
  subgroup = "storage",
  order = "z[biter-logistics]-c[carrier-biter]",
  stack_size = 50
}

local biomass_icon = "__BiterLogistics__/data/entities/Biter-Biomass/Biter-Biomass.png"

local biomass_item = {
  type = "item",
  name = constants.biomass_item,
  localised_name = {"item-name.biter-logistics-biter-biomass"},
  localised_description = {"item-description.biter-logistics-biter-biomass"},
  icon = biomass_icon,
  icon_size = 128,
  pictures = {
    {filename = biomass_icon, width = 130, height = 128, scale = 0.7}
  },
  subgroup = "raw-material",
  order = "z[biter-logistics]-a[biter-biomass]",
  stack_size = 100
}

data:extend({nest_item, depot_item, carrier_item, biomass_item})

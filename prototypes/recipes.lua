local constants = require("constants")

data:extend({
  {
    type = "recipe",
    name = constants.biomass_item,
    category = "chemistry",
    enabled = false,
    energy_required = 5,
    ingredients = {
      {type = "item", name = "wood", amount = 10},
      {type = "fluid", name = "petroleum-gas", amount = 20},
      {type = "item", name = "sulfur", amount = 1}
    },
    results = {{type = "item", name = constants.biomass_item, amount = 1}}
  },
  {
    type = "recipe",
    name = constants.nest_item,
    enabled = false,
    energy_required = 4,
    ingredients = {
      {type = "item", name = constants.biomass_item, amount = 4},
      {type = "item", name = "stone-brick", amount = 10},
      {type = "item", name = "steel-plate", amount = 4},
      {type = "item", name = "electronic-circuit", amount = 2}
    },
    results = {{type = "item", name = constants.nest_item, amount = 1}}
  },
  {
    type = "recipe",
    name = constants.depot_item,
    enabled = false,
    energy_required = 4,
    ingredients = {
      {type = "item", name = constants.biomass_item, amount = 6},
      {type = "item", name = "stone-brick", amount = 10},
      {type = "item", name = "steel-plate", amount = 6},
      {type = "item", name = "electronic-circuit", amount = 4}
    },
    results = {{type = "item", name = constants.depot_item, amount = 1}}
  },
  {
    type = "recipe",
    name = constants.carrier_item,
    enabled = false,
    energy_required = 2,
    ingredients = {
      {type = "item", name = constants.biomass_item, amount = 1},
      {type = "item", name = "raw-fish", amount = 1},
      {type = "item", name = "electronic-circuit", amount = 1}
    },
    results = {{type = "item", name = constants.carrier_item, amount = 1}}
  }
})

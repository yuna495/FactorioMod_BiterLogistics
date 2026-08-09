local constants = require("constants")

data:extend({
  {
    type = "recipe",
    name = constants.nest_item,
    enabled = false,
    energy_required = 4,
    ingredients = {
      {type = "item", name = "stone-brick", amount = 10},
      {type = "item", name = "steel-plate", amount = 4},
      {type = "item", name = "electronic-circuit", amount = 2}
    },
    results = {{type = "item", name = constants.nest_item, amount = 1}}
  },
  {
    type = "recipe",
    name = constants.carrier_item,
    enabled = false,
    energy_required = 2,
    ingredients = {
      {type = "item", name = "raw-fish", amount = 1},
      {type = "item", name = "iron-plate", amount = 5},
      {type = "item", name = "electronic-circuit", amount = 1}
    },
    results = {{type = "item", name = constants.carrier_item, amount = 1}}
  }
})

local constants = require("constants")

local function add_biomass_loot(name)
  local spawner = data.raw["unit-spawner"] and data.raw["unit-spawner"][name]
  if not spawner then return end

  spawner.loot = spawner.loot or {}
  spawner.loot[#spawner.loot + 1] = {
    item = constants.biomass_item,
    probability = 1,
    count_min = 2,
    count_max = 4
  }
end

add_biomass_loot("biter-spawner")
add_biomass_loot("spitter-spawner")

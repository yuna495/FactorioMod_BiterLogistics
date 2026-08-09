local constants = require("constants")

local nest_picture_scale = 0.4

local nest = table.deepcopy(data.raw["container"]["steel-chest"])
nest.name = constants.nest_entity
nest.localised_name = {"entity-name.biter-logistics-nest"}
nest.localised_description = {"entity-description.biter-logistics-nest"}
nest.icon = "__base__/graphics/icons/biter-spawner.png"
nest.minable = {mining_time = 0.3, result = constants.nest_item}
nest.collision_box = {{-1.2, -1.2}, {1.2, 1.2}}
nest.selection_box = {{-1.5, -1.5}, {1.5, 1.5}}
nest.inventory_size = constants.nest_slots.max_total
nest.inventory_type = "with_filters_and_bar"
nest.quality_affects_inventory_size = false
nest.corpse = "biter-spawner-corpse"
nest.dying_explosion = "biter-spawner-die"
nest.picture = {
  layers = {
    {
      filename = "__base__/graphics/entity/spawner/spawner-idle.png",
      width = 520,
      height = 376,
      scale = nest_picture_scale,
      shift = util.by_pixel(4, -3),
      surface = "nauvis",
      usage = "enemy"
    },
    {
      filename = "__base__/graphics/entity/spawner/spawner-idle-mask.png",
      width = 270,
      height = 230,
      scale = nest_picture_scale,
      shift = util.by_pixel(0, -12.5),
      tint = {r = 0.45, g = 0.85, b = 0.38, a = 1},
      flags = {"mask"},
      surface = "nauvis",
      usage = "enemy"
    },
    {
      filename = "__base__/graphics/entity/spawner/spawner-idle-shadow.png",
      width = 496,
      height = 358,
      scale = nest_picture_scale,
      shift = util.by_pixel(3.5, -0.5),
      draw_as_shadow = true,
      surface = "nauvis",
      usage = "enemy"
    }
  }
}

local depot = table.deepcopy(data.raw["container"]["steel-chest"])
depot.name = constants.depot_entity
depot.localised_name = {"entity-name.biter-logistics-fuel-depot"}
depot.localised_description = {"entity-description.biter-logistics-fuel-depot"}
depot.icon = "__base__/graphics/icons/spitter-spawner.png"
depot.minable = {mining_time = 0.3, result = constants.depot_item}
depot.collision_box = {{-1.2, -1.2}, {1.2, 1.2}}
depot.selection_box = {{-1.5, -1.5}, {1.5, 1.5}}
depot.inventory_size = constants.depot_slots.total
depot.inventory_type = "with_filters_and_bar"
depot.quality_affects_inventory_size = false
depot.corpse = "spitter-spawner-corpse"
depot.dying_explosion = "spitter-spawner-die"
depot.picture = {
  layers = {
    {
      filename = "__base__/graphics/entity/spawner/spawner-idle.png",
      width = 520,
      height = 376,
      scale = nest_picture_scale,
      shift = util.by_pixel(4, -3),
      surface = "nauvis",
      usage = "enemy"
    },
    {
      filename = "__base__/graphics/entity/spawner/spawner-idle-mask.png",
      width = 270,
      height = 230,
      scale = nest_picture_scale,
      shift = util.by_pixel(0, -12.5),
      tint = {r = 0.95, g = 0.62, b = 0.18, a = 1},
      flags = {"mask"},
      surface = "nauvis",
      usage = "enemy"
    },
    {
      filename = "__base__/graphics/entity/spawner/spawner-idle-shadow.png",
      width = 496,
      height = 358,
      scale = nest_picture_scale,
      shift = util.by_pixel(3.5, -0.5),
      draw_as_shadow = true,
      surface = "nauvis",
      usage = "enemy"
    }
  }
}

local carrier = table.deepcopy(data.raw["unit"]["small-biter"])
carrier.name = constants.carrier_unit
carrier.localised_name = {"entity-name.biter-logistics-carrier-biter-unit"}
carrier.localised_description = {"entity-description.biter-logistics-carrier-biter-unit"}
carrier.flags = {"placeable-player", "placeable-off-grid", "not-repairable", "breaths-air"}
carrier.autoplace = nil
carrier.minable = {mining_time = 0.2, result = constants.carrier_item}
carrier.absorptions_to_join_attack = nil
carrier.has_belt_immunity = true
carrier.min_pursue_time = 0
carrier.max_pursue_distance = 0
carrier.attack_parameters.damage_modifier = 0

data:extend({nest, depot, carrier})

local constants = require("constants")

local nest_picture_scale = 0.4
local control_combinator_picture_scale = 0.3
local neutral_mask_tint = {r = 0.72, g = 0.72, b = 0.72, a = 0.45}
local control_combinator_mask_tint = {r = 0.7, g = 1, b = 0.3, a = 0.5}

local function control_combinator_worm_sprite()
  return {
    layers = {
      {
        filename = "__base__/graphics/entity/worm/worm-folded.png",
        width = 130,
        height = 120,
        scale = control_combinator_picture_scale,
        shift = util.by_pixel(0, 4),
        surface = "nauvis",
        usage = "enemy"
      },
      {
        filename = "__base__/graphics/entity/worm/worm-folded-mask.png",
        width = 130,
        height = 108,
        scale = control_combinator_picture_scale,
        shift = util.by_pixel(0, 7),
        tint = control_combinator_mask_tint,
        flags = {"mask"},
        surface = "nauvis",
        usage = "enemy"
      },
      {
        filename = "__base__/graphics/entity/worm/worm-folded-shadow.png",
        width = 116,
        height = 68,
        scale = control_combinator_picture_scale,
        shift = util.by_pixel(5, -4),
        draw_as_shadow = true,
        surface = "nauvis",
        usage = "enemy"
      }
    }
  }
end

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
      tint = neutral_mask_tint,
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
      tint = neutral_mask_tint,
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

local control_combinator = table.deepcopy(data.raw["constant-combinator"]["constant-combinator"])
control_combinator.name = constants.control_combinator_entity
control_combinator.localised_name = {"entity-name.biter-logistics-control-combinator"}
control_combinator.localised_description = {"entity-description.biter-logistics-control-combinator"}
control_combinator.icon = "__base__/graphics/icons/small-worm.png"
control_combinator.minable = {mining_time = 0.1, result = constants.control_combinator_item}
control_combinator.fast_replaceable_group = nil
control_combinator.next_upgrade = nil
control_combinator.corpse = "small-worm-corpse-burrowed"
control_combinator.dying_explosion = "small-worm-die"
local worm_sprite = control_combinator_worm_sprite()
control_combinator.sprites = {
  north = worm_sprite,
  east = worm_sprite,
  south = worm_sprite,
  west = worm_sprite
}
control_combinator.icon_draw_specification = {scale = 0.7}

data:extend({nest, depot, carrier, control_combinator})

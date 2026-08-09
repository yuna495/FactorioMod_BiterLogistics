local constants = require("constants")

data:extend({
  {
    type = "sprite",
    name = constants.visuals.spawner_mask_sprite,
    filename = "__base__/graphics/entity/spawner/spawner-idle-mask.png",
    width = 270,
    height = 230,
    scale = 0.4,
    shift = util.by_pixel(0, -12.5),
    apply_runtime_tint = true,
    tint_as_overlay = true,
    surface = "nauvis",
    usage = "enemy"
  }
})

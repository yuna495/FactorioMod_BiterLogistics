local constants = require("constants")

local science = {
  red_green = {
    {"automation-science-pack", 1},
    {"logistic-science-pack", 1}
  },
  chemical = {
    {"automation-science-pack", 1},
    {"logistic-science-pack", 1},
    {"chemical-science-pack", 1}
  },
  production = {
    {"automation-science-pack", 1},
    {"logistic-science-pack", 1},
    {"chemical-science-pack", 1},
    {"production-science-pack", 1}
  },
  utility = {
    {"automation-science-pack", 1},
    {"logistic-science-pack", 1},
    {"chemical-science-pack", 1},
    {"production-science-pack", 1},
    {"utility-science-pack", 1}
  },
  space = {
    {"automation-science-pack", 1},
    {"logistic-science-pack", 1},
    {"chemical-science-pack", 1},
    {"production-science-pack", 1},
    {"utility-science-pack", 1},
    {"space-science-pack", 1}
  }
}

local has_space_age = mods and mods["space-age"]
local biter_icon = "__base__/graphics/icons/medium-biter.png"
local biomass_icon = "__base__/graphics/icons/medium-biter.png"
local nest_icon = has_space_age
  and "__space-age__/graphics/technology/captive-biter-spawner.png"
  or "__base__/graphics/icons/biter-spawner.png"
local nest_icon_size = has_space_age and 256 or 64
local nest_icon_scale = has_space_age and nil or 1.45
local biter_icon_size = 64
local biter_icon_scale = 1.25

local function icon_layer(icon, icon_size, scale, shift)
  local layer = {
    icon = icon,
    icon_size = icon_size
  }
  if scale then layer.scale = scale end
  if shift then layer.shift = shift end
  return layer
end

local function logistics_icons()
  return {
    icon_layer(nest_icon, nest_icon_size, nest_icon_scale, {-10, -2}),
    icon_layer(biter_icon, biter_icon_size, 0.95, {28, 28})
  }
end

local function single_icon(icon, icon_size, scale)
  return {
    icon_layer(icon, icon_size, scale)
  }
end

local function nothing_effect(description, icon, icon_size)
  return {
    type = "nothing",
    icon = icon,
    icon_size = icon_size or 64,
    use_icon_overlay_constant = false,
    effect_description = description
  }
end

local function technology(name, icons, prerequisites, count, ingredients, time, effect_description, effect_icon, effect_icon_size)
  return {
    type = "technology",
    name = name,
    icons = icons,
    effects = {
      nothing_effect(effect_description, effect_icon, effect_icon_size)
    },
    prerequisites = prerequisites,
    unit = {
      count = count,
      ingredients = ingredients,
      time = time
    },
    upgrade = true,
    order = "c-k-b[" .. name .. "]"
  }
end

local logistics_tech = {
  type = "technology",
  name = constants.research.base,
  icons = logistics_icons(),
  effects = {
    {
      type = "unlock-recipe",
      recipe = constants.nest_item
    },
    {
      type = "unlock-recipe",
      recipe = constants.depot_item
    },
    {
      type = "unlock-recipe",
      recipe = constants.carrier_item
    }
  },
  prerequisites = {"automated-rail-transportation"},
  unit = {
    count = 200,
    ingredients = science.red_green,
    time = 30
  },
  order = "c-k-a[biter-logistics]"
}

local capacity_icons = single_icon(biter_icon, biter_icon_size, biter_icon_scale)
local speed_icons = single_icon(biter_icon, biter_icon_size, biter_icon_scale)
local nest_capacity_icons = single_icon(nest_icon, nest_icon_size, nest_icon_scale)
local biomass_icons = single_icon(biomass_icon, biter_icon_size, biter_icon_scale)

local technologies = {logistics_tech}

technologies[#technologies + 1] = {
  type = "technology",
  name = constants.research.biomass_cultivation,
  icons = biomass_icons,
  effects = {
    {
      type = "unlock-recipe",
      recipe = constants.biomass_item
    }
  },
  prerequisites = {constants.research.base, "chemical-science-pack"},
  unit = {
    count = 300,
    ingredients = science.chemical,
    time = 30
  },
  order = "c-k-a-b[biter-logistics-biomass-cultivation]"
}

technologies[#technologies + 1] = {
  type = "technology",
  name = constants.research.herbivorous_biters,
  icons = speed_icons,
  effects = {
    nothing_effect("Carrier Biter food: wood", "__base__/graphics/icons/wood.png", 64)
  },
  prerequisites = {constants.research.base, "chemical-science-pack"},
  unit = {
    count = 250,
    ingredients = science.chemical,
    time = 30
  },
  order = "c-k-a-c[biter-logistics-herbivorous-biters]"
}

for level, spec in ipairs({
  {count = 150, time = 30, ingredients = science.red_green, prerequisites = {constants.research.base}},
  {count = 300, time = 30, ingredients = science.chemical, prerequisites = {constants.research.carrier_capacity_prefix .. "1", "chemical-science-pack"}},
  {count = 600, time = 30, ingredients = science.production, prerequisites = {constants.research.carrier_capacity_prefix .. "2", "production-science-pack"}},
  {count = 1000, time = 60, ingredients = science.utility, prerequisites = {constants.research.carrier_capacity_prefix .. "3", "utility-science-pack"}}
}) do
  technologies[#technologies + 1] = technology(
    constants.research.carrier_capacity_prefix .. level,
    capacity_icons,
    spec.prerequisites,
    spec.count,
    spec.ingredients,
    spec.time,
    "Carrier Biter cargo capacity: +1 stack",
    biter_icon,
    biter_icon_size
  )
end

for level, spec in ipairs({
  {count = 100, time = 30, ingredients = science.red_green, prerequisites = {constants.research.base}},
  {count = 250, time = 30, ingredients = science.chemical, prerequisites = {constants.research.carrier_speed_prefix .. "1", "chemical-science-pack"}},
  {count = 500, time = 30, ingredients = science.production, prerequisites = {constants.research.carrier_speed_prefix .. "2", "production-science-pack"}}
}) do
  technologies[#technologies + 1] = technology(
    constants.research.carrier_speed_prefix .. level,
    speed_icons,
    spec.prerequisites,
    spec.count,
    spec.ingredients,
    spec.time,
    "Carrier Biter speed: +20%",
    biter_icon,
    biter_icon_size
  )
end

technologies[#technologies + 1] = {
  type = "technology",
  name = constants.research.carrier_speed_leveled,
  icons = speed_icons,
  effects = {
    nothing_effect("Carrier Biter speed: +10%", biter_icon, biter_icon_size)
  },
  prerequisites = {constants.research.carrier_speed_prefix .. "3", "space-science-pack"},
  unit = {
    count_formula = "750 * (L - 3)",
    ingredients = science.space,
    time = 60
  },
  max_level = constants.research.carrier_speed_max_level,
  upgrade = true,
  order = "c-k-c[" .. constants.research.carrier_speed_leveled .. "]"
}

for level, spec in ipairs({
  {count = 150, time = 30, slots = 20, ingredients = science.red_green, prerequisites = {constants.research.base}},
  {count = 300, time = 30, slots = 30, ingredients = science.chemical, prerequisites = {constants.research.nest_capacity_prefix .. "1", "chemical-science-pack"}},
  {count = 600, time = 30, slots = 40, ingredients = science.production, prerequisites = {constants.research.nest_capacity_prefix .. "2", "production-science-pack"}}
}) do
  technologies[#technologies + 1] = technology(
    constants.research.nest_capacity_prefix .. level,
    nest_capacity_icons,
    spec.prerequisites,
    spec.count,
    spec.ingredients,
    spec.time,
    "Logistics Nest cargo slots: " .. spec.slots,
    nest_icon,
    nest_icon_size
  )
end

data:extend(technologies)

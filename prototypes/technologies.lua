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

local technology_icon_size = 128
local technology_icon_path = "__BiterLogistics__/data/technologies/"

local technology_icons = {
  logistics = technology_icon_path .. "biter-logistics.png",
  biomass_cultivation = technology_icon_path .. "biter-logistics-biomass-cultivation.png",
  herbivorous_biters = technology_icon_path .. "biter-logistics-herbivorous-biters.png",
  circuit_control = technology_icon_path .. "biter-logistics-circuit-control.png",
  carrier_capacity = technology_icon_path .. "biter-logistics-carrier-capacity.png",
  carrier_speed = technology_icon_path .. "biter-logistics-carrier-speed.png",
  nest_capacity = technology_icon_path .. "biter-logistics-nest-capacity.png",
  depot_range = technology_icon_path .. "biter-logistics-depot-range.png",
  depot_capacity = technology_icon_path .. "biter-logistics-depot-capacity.png"
}

local function single_icon(icon)
  return {
    {
      icon = icon,
      icon_size = technology_icon_size
    }
  }
end

local function nothing_effect(description, icon, icon_size)
  return {
    type = "nothing",
    icon = icon,
    icon_size = icon_size or technology_icon_size,
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

local effect_descriptions = {
  carrier_food = {"modifier-description.biter-logistics-carrier-food", "[item=wood]"},
  carrier_capacity = {"modifier-description.biter-logistics-carrier-capacity", "1"},
  carrier_speed_20 = {"modifier-description.biter-logistics-carrier-speed", "20"},
  carrier_speed_10 = {"modifier-description.biter-logistics-carrier-speed", "10"},
  depot_capacity = {"modifier-description.biter-logistics-depot-capacity", "1"},
  circuit_control = {"modifier-description.biter-logistics-circuit-control"}
}

local logistics_tech = {
  type = "technology",
  name = constants.research.base,
  icons = single_icon(technology_icons.logistics),
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

local capacity_icons = single_icon(technology_icons.carrier_capacity)
local speed_icons = single_icon(technology_icons.carrier_speed)
local nest_capacity_icons = single_icon(technology_icons.nest_capacity)
local biomass_icons = single_icon(technology_icons.biomass_cultivation)
local herbivorous_icons = single_icon(technology_icons.herbivorous_biters)
local circuit_control_icons = single_icon(technology_icons.circuit_control)
local depot_range_icons = single_icon(technology_icons.depot_range)
local depot_capacity_icons = single_icon(technology_icons.depot_capacity)

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
  icons = herbivorous_icons,
  effects = {
    nothing_effect(effect_descriptions.carrier_food, technology_icons.herbivorous_biters)
  },
  prerequisites = {constants.research.base, "chemical-science-pack"},
  unit = {
    count = 250,
    ingredients = science.chemical,
    time = 30
  },
  order = "c-k-a-c[biter-logistics-herbivorous-biters]"
}

technologies[#technologies + 1] = {
  type = "technology",
  name = constants.research.circuit_control,
  icons = circuit_control_icons,
  effects = {
    {
      type = "unlock-recipe",
      recipe = constants.control_combinator_item
    },
    nothing_effect(effect_descriptions.circuit_control, technology_icons.circuit_control)
  },
  prerequisites = {constants.research.base, "chemical-science-pack"},
  unit = {
    count = 300,
    ingredients = science.chemical,
    time = 30
  },
  order = "c-k-a-d[biter-logistics-circuit-control]"
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
    effect_descriptions.carrier_capacity,
    technology_icons.carrier_capacity,
    technology_icon_size
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
    effect_descriptions.carrier_speed_20,
    technology_icons.carrier_speed,
    technology_icon_size
  )
end

technologies[#technologies + 1] = {
  type = "technology",
  name = constants.research.carrier_speed_leveled,
  icons = speed_icons,
  effects = {
    nothing_effect(effect_descriptions.carrier_speed_10, technology_icons.carrier_speed)
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
    {"modifier-description.biter-logistics-nest-cargo-slots", tostring(spec.slots)},
    technology_icons.nest_capacity,
    technology_icon_size
  )
end

for level, spec in ipairs({
  {count = 150, time = 30, radius = 40, ingredients = science.red_green, prerequisites = {constants.research.base}},
  {count = 300, time = 30, radius = 48, ingredients = science.chemical, prerequisites = {constants.research.depot_range_prefix .. "1", "chemical-science-pack"}},
  {count = 600, time = 30, radius = 56, ingredients = science.production, prerequisites = {constants.research.depot_range_prefix .. "2", "production-science-pack"}},
  {count = 1000, time = 60, radius = 64, ingredients = science.utility, prerequisites = {constants.research.depot_range_prefix .. "3", "utility-science-pack"}},
  {count = 1500, time = 60, radius = 72, ingredients = science.space, prerequisites = {constants.research.depot_range_prefix .. "4", "space-science-pack"}}
}) do
  technologies[#technologies + 1] = technology(
    constants.research.depot_range_prefix .. level,
    depot_range_icons,
    spec.prerequisites,
    spec.count,
    spec.ingredients,
    spec.time,
    {"modifier-description.biter-logistics-depot-range", tostring(spec.radius)},
    technology_icons.depot_range,
    technology_icon_size
  )
end

for level, spec in ipairs({
  {count = 150, time = 30, capacity = 2, ingredients = science.red_green, prerequisites = {constants.research.base}},
  {count = 300, time = 30, capacity = 3, ingredients = science.chemical, prerequisites = {constants.research.depot_capacity_prefix .. "1", "chemical-science-pack"}},
  {count = 600, time = 30, capacity = 4, ingredients = science.production, prerequisites = {constants.research.depot_capacity_prefix .. "2", "production-science-pack"}},
  {count = 1000, time = 60, capacity = 5, ingredients = science.utility, prerequisites = {constants.research.depot_capacity_prefix .. "3", "utility-science-pack"}}
}) do
  technologies[#technologies + 1] = technology(
    constants.research.depot_capacity_prefix .. level,
    depot_capacity_icons,
    spec.prerequisites,
    spec.count,
    spec.ingredients,
    spec.time,
    effect_descriptions.depot_capacity,
    technology_icons.depot_capacity,
    technology_icon_size
  )
end

data:extend(technologies)

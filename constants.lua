local constants = {}

constants.nest_entity = "biter-logistics-nest"
constants.nest_item = "biter-logistics-nest"
constants.depot_entity = "biter-logistics-fuel-depot"
constants.depot_item = "biter-logistics-fuel-depot"
constants.carrier_unit = "biter-logistics-carrier-biter-unit"
constants.carrier_item = "biter-logistics-carrier-biter"
constants.biomass_item = "biter-logistics-biter-biomass"

constants.nest_slots = {
  cargo_first = 1,
  cargo_count = 10,
  max_cargo_count = 40,
  total = 10,
  max_total = 40
}

constants.depot_slots = {
  carrier = 1,
  food_first = 2,
  food_count = 10,
  total = 11
}

constants.research = {
  base = "biter-logistics",
  biomass_cultivation = "biter-logistics-biomass-cultivation",
  herbivorous_biters = "biter-logistics-herbivorous-biters",
  carrier_capacity_prefix = "biter-logistics-carrier-capacity-",
  carrier_capacity_max_level = 4,
  carrier_speed_prefix = "biter-logistics-carrier-speed-",
  carrier_speed_leveled = "biter-logistics-carrier-speed-4",
  carrier_speed_leveled_first_level = 4,
  carrier_speed_max_level = 17,
  nest_capacity_prefix = "biter-logistics-nest-capacity-",
  default_carrier_capacity_stacks = 1,
  default_carrier_speed_multiplier = 1,
  default_nest_cargo_slots = 10,
  base_carrier_speed = 0.2,
  carrier_speed_finite_bonus = 0.2,
  carrier_speed_leveled_bonus = 0.1,
  max_carrier_speed_multiplier = 3
}

constants.nest_modes = {
  supply = "supply",
  request = "request"
}

constants.food = {
  carrier_capacity = 1000,
  base_job_cost = 20,
  cost_per_tile = 0.1,
  values = {
    [constants.biomass_item] = 100,
    ["raw-fish"] = 80
  },
  herbivorous_values = {
    wood = 20
  },
  space_age_values = {
    yumako = 40,
    jellynut = 60,
    nutrients = 120
  }
}

constants.ticks = {
  nest_update_interval = 30,
  depot_update_interval = 30,
  logistics_update_interval = 30,
  carrier_update_interval = 15,
  nests_per_update = 16,
  depots_per_update = 16,
  requests_per_update = 12,
  carriers_per_update = 32,
  idle_delay = 60,
  retry_delay = 120,
  destination_space_check_interval = 120,
  destination_space_check_jitter = 60,
  command_check_interval = 60,
  command_timeout = 60 * 60
}

constants.command = {
  radius = 0.75,
  interaction_radius = 4,
  destination_search_radius = 8,
  destination_precision = 0.5,
  stop_ticks = 5,
  pathfind_flags = {
    cache = true,
    low_priority = true
  }
}

constants.gui = {
  root = "biter_logistics_nest_gui",
  name_flow = "biter_logistics_name_flow",
  name_field = "biter_logistics_nest_name",
  name_suffix_label = "biter_logistics_name_suffix",
  mode_dropdown = "biter_logistics_mode",
  request_item_button = "biter_logistics_request_item"
}

constants.commands = {
  debug = "biter-logistics-debug"
}

return constants

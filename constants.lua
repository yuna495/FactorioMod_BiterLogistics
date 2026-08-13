local constants = {}

constants.nest_entity = "biter-logistics-nest"
constants.nest_item = "biter-logistics-nest"
constants.depot_entity = "biter-logistics-fuel-depot"
constants.depot_item = "biter-logistics-fuel-depot"
constants.carrier_unit = "biter-logistics-carrier-biter-unit"
constants.carrier_item = "biter-logistics-carrier-biter"
constants.biomass_item = "biter-logistics-biter-biomass"
constants.control_combinator_entity = "biter-logistics-control-combinator"
constants.control_combinator_item = "biter-logistics-control-combinator"

constants.visuals = {
  spawner_mask_sprite = "biter-logistics-spawner-color-mask",
  overlay_alpha = 0.82,
  range_alpha = 0.72,
  range_width = 4,
  color_settings = {
    supply = "biter-logistics-supply-color",
    request = "biter-logistics-request-color",
    depot = "biter-logistics-fuel-depot-color"
  },
  default_colors = {
    supply = {r = 1, g = 0.28, b = 0.22, a = 0.82},
    request = {r = 0.25, g = 0.58, b = 1, a = 0.82},
    depot = {r = 0.35, g = 0.95, b = 0.38, a = 0.82}
  }
}

constants.nest_slots = {
  cargo_first = 1,
  cargo_count = 10,
  max_cargo_count = 40,
  total = 10,
  max_total = 40
}

constants.depot_slots = {
  carrier = 1,
  egg = 2,
  food_first = 3,
  food_count = 10,
  total = 12,
  layout_version = 2
}

constants.hatching = {
  duration_ticks = 60 * 5
}

constants.research = {
  base = "biter-logistics",
  logistics_nest = "biter-logistics-logistics-nest",
  biomass_cultivation = "biter-logistics-biomass-cultivation",
  herbivorous_biters = "biter-logistics-herbivorous-biters",
  circuit_control = "biter-logistics-circuit-control",
  carrier_capacity_prefix = "biter-logistics-carrier-capacity-",
  carrier_capacity_max_level = 4,
  carrier_speed_prefix = "biter-logistics-carrier-speed-",
  carrier_speed_leveled = "biter-logistics-carrier-speed-4",
  carrier_speed_leveled_first_level = 4,
  carrier_speed_max_level = 17,
  nest_capacity_prefix = "biter-logistics-nest-capacity-",
  depot_range_prefix = "biter-logistics-depot-range-",
  depot_range_max_level = 5,
  depot_capacity_prefix = "biter-logistics-depot-capacity-",
  depot_capacity_max_level = 4,
  default_carrier_capacity_stacks = 1,
  default_carrier_speed_multiplier = 1,
  default_nest_cargo_slots = 10,
  default_depot_range = 32,
  default_depot_carrier_capacity = 1,
  depot_range_by_level = {40, 48, 56, 64, 72},
  base_carrier_speed = 0.2,
  carrier_speed_finite_bonus = 0.2,
  carrier_speed_leveled_bonus = 0.1,
  max_carrier_speed_multiplier = 3,
  max_depot_range = 72,
  max_depot_carrier_capacity = 5
}

constants.nest_modes = {
  supply = "supply",
  request = "request"
}

constants.settings = {
  feral_cargo_behavior = "biter-logistics-feral-cargo-behavior"
}

constants.request_modes = {
  simple = "simple",
  circuit = "circuit"
}

constants.request_thresholds = {
  default = 50,
  values = {25, 50, 75},
  fractions = {
    [25] = 0.25,
    [50] = 0.5,
    [75] = 0.75
  }
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
  route_stall_timeout = 60 * 10,
  command_timeout = 60 * 60,
  debug_log_window = 60 * 10,
  range_visual_update_interval = 60,
  gui_update_interval = 60,
  diagnostic_message_cooldown = 60 * 5,
  diagnostic_alert_update_interval = 60,
  diagnostic_alert_stale_ticks = 60 * 5
}

constants.spawner_egg_loot = {
  source_spawners = {
    ["biter-spawner"] = true,
    ["spitter-spawner"] = true
  },
  egg_item = "biter-egg",
  drop_chance = 0.60,
  drop_radius = 3,
  spill_radius = 0.25,
  flying_text_color = {r = 0.95, g = 0.78, b = 0.45},
  ignored_forces = {
    enemy = true,
    neutral = true
  }
}

constants.command = {
  radius = 0.75,
  interaction_radius = 4,
  destination_search_radius = 8,
  destination_precision = 0.5,
  destination_candidate_box_radius = 1.5,
  destination_candidate_offsets = {
    {name = "north", x = 0, y = -3.5},
    {name = "south", x = 0, y = 3.5},
    {name = "east", x = 3.5, y = 0},
    {name = "west", x = -3.5, y = 0},
    {name = "north-east", x = 2.5, y = -2.5},
    {name = "north-west", x = -2.5, y = -2.5},
    {name = "south-east", x = 2.5, y = 2.5},
    {name = "south-west", x = -2.5, y = 2.5}
  }
}

constants.feral = {
  cargo_behavior = {
    drop = "drop",
    destroy = "destroy"
  },
  failure_threshold = 3,
  failure_interval = 600,
  route_progress_min_delta = 0.5,
  attack_radius = 64,
  spawn_search_radius = 12,
  spawn_search_precision = 0.5,
  fallback_biter = "small-biter",
  biter_order = {"small-biter", "medium-biter", "big-biter", "behemoth-biter"},
  biter_rank = {
    ["small-biter"] = 1,
    ["medium-biter"] = 2,
    ["big-biter"] = 3,
    ["behemoth-biter"] = 4
  }
}

constants.gui = {
  root = "biter_logistics_nest_gui",
  name_flow = "biter_logistics_name_flow",
  name_field = "biter_logistics_nest_name",
  name_suffix_label = "biter_logistics_name_suffix",
  mode_dropdown = "biter_logistics_mode",
  request_type_dropdown = "biter_logistics_request_type",
  request_item_button = "biter_logistics_request_item",
  request_threshold_radio_prefix = "biter_logistics_threshold_",
  depot_status_flow = "biter_logistics_depot_status"
}

constants.commands = {
  debug = "biter-logistics-debug",
  test_move = "biter-logistics-test-move"
}

return constants

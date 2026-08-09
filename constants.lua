local constants = {}

constants.nest_entity = "biter-logistics-nest"
constants.nest_item = "biter-logistics-nest"
constants.carrier_unit = "biter-logistics-carrier-biter-unit"
constants.carrier_item = "biter-logistics-carrier-biter"

constants.slots = {
  carrier = 1,
  cargo_first = 2,
  cargo_last = 11,
  cargo_count = 10,
  total = 11
}

constants.ticks = {
  nest_update_interval = 30,
  carrier_update_interval = 15,
  nests_per_update = 16,
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
  destination_dropdown = "biter_logistics_destination"
}

constants.commands = {
  debug = "biter-logistics-debug"
}

return constants

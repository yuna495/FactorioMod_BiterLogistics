local constants = require("constants")
local state = require("scripts.state")

local research = {}

local capacity_technologies = {
  constants.research.carrier_capacity_prefix .. "1",
  constants.research.carrier_capacity_prefix .. "2",
  constants.research.carrier_capacity_prefix .. "3",
  constants.research.carrier_capacity_prefix .. "4"
}

local speed_technologies = {
  constants.research.carrier_speed_prefix .. "1",
  constants.research.carrier_speed_prefix .. "2",
  constants.research.carrier_speed_prefix .. "3"
}

local nest_capacity_technologies = {
  constants.research.nest_capacity_prefix .. "1",
  constants.research.nest_capacity_prefix .. "2",
  constants.research.nest_capacity_prefix .. "3"
}

local depot_range_technologies = {
  constants.research.depot_range_prefix .. "1",
  constants.research.depot_range_prefix .. "2",
  constants.research.depot_range_prefix .. "3",
  constants.research.depot_range_prefix .. "4",
  constants.research.depot_range_prefix .. "5"
}

local tracked_technologies = {
  [constants.research.carrier_speed_leveled] = true,
  [constants.research.herbivorous_biters] = true
}

for _, name in ipairs(capacity_technologies) do tracked_technologies[name] = true end
for _, name in ipairs(speed_technologies) do tracked_technologies[name] = true end
for _, name in ipairs(nest_capacity_technologies) do tracked_technologies[name] = true end
for _, name in ipairs(depot_range_technologies) do tracked_technologies[name] = true end

local function default_effects(force)
  return {
    force_name = force and force.name or nil,
    carrier_capacity_stacks = constants.research.default_carrier_capacity_stacks,
    carrier_speed_multiplier = constants.research.default_carrier_speed_multiplier,
    nest_cargo_slots = constants.research.default_nest_cargo_slots,
    depot_range = constants.research.default_depot_range,
    carrier_capacity_level = 0,
    carrier_speed_level = 0,
    nest_capacity_level = 0,
    depot_range_level = 0,
    herbivorous_biters = false
  }
end

local function technology(force, name)
  if not force or not force.valid then return nil end
  return force.technologies[name]
end

local function is_researched(force, name)
  local tech = technology(force, name)
  return tech and tech.valid and tech.researched or false
end

local function researched_finite_levels(force, names)
  local levels = 0
  for index, name in ipairs(names) do
    if is_researched(force, name) then
      levels = index
    end
  end
  return levels
end

local function researched_leveled_levels(force, name, first_level, max_level)
  local tech = technology(force, name)
  if not tech or not tech.valid then return 0 end

  local completed = tech.level - first_level
  if tech.researched then
    completed = completed + 1
  end
  completed = math.max(0, completed)
  if max_level then
    completed = math.min(completed, max_level - first_level + 1)
  end
  return completed
end

local function clamp(value, minimum, maximum)
  if value < minimum then return minimum end
  if value > maximum then return maximum end
  return value
end

local function calculate_force_effects(force)
  local effects = default_effects(force)

  local finite_capacity_levels = researched_finite_levels(force, capacity_technologies)
  effects.carrier_capacity_level = finite_capacity_levels
  effects.carrier_capacity_stacks = constants.research.default_carrier_capacity_stacks + effects.carrier_capacity_level

  local finite_speed_levels = researched_finite_levels(force, speed_technologies)
  local leveled_speed_levels = researched_leveled_levels(
    force,
    constants.research.carrier_speed_leveled,
    constants.research.carrier_speed_leveled_first_level,
    constants.research.carrier_speed_max_level
  )
  effects.carrier_speed_level = finite_speed_levels + leveled_speed_levels
  effects.carrier_speed_multiplier = clamp(
    constants.research.default_carrier_speed_multiplier
      + finite_speed_levels * constants.research.carrier_speed_finite_bonus
      + leveled_speed_levels * constants.research.carrier_speed_leveled_bonus,
    constants.research.default_carrier_speed_multiplier,
    constants.research.max_carrier_speed_multiplier
  )

  effects.nest_capacity_level = researched_finite_levels(force, nest_capacity_technologies)
  effects.nest_cargo_slots = clamp(
    constants.research.default_nest_cargo_slots + effects.nest_capacity_level * 10,
    constants.research.default_nest_cargo_slots,
    constants.nest_slots.max_cargo_count
  )

  effects.depot_range_level = researched_finite_levels(force, depot_range_technologies)
  effects.depot_range = constants.research.depot_range_by_level[effects.depot_range_level]
    or constants.research.default_depot_range

  effects.herbivorous_biters = is_researched(force, constants.research.herbivorous_biters)

  return effects
end

function research.effects_for_force_name(force_name)
  local data = state.get()
  local effects = force_name and data.force_effects[force_name] or nil
  if not effects then
    return default_effects(force_name and game.forces[force_name] or nil)
  end
  return effects
end

function research.carrier_capacity_for_force_name(force_name)
  return research.effects_for_force_name(force_name).carrier_capacity_stacks
end

function research.nest_cargo_slots_for_force_name(force_name)
  return research.effects_for_force_name(force_name).nest_cargo_slots
end

function research.depot_range_for_force_name(force_name)
  return research.effects_for_force_name(force_name).depot_range
end

local function stack_definition(stack)
  local item = {name = stack.name, count = stack.count}
  if stack.quality and stack.quality.name ~= "normal" then
    item.quality = stack.quality.name
  end
  return item
end

local function spill_overflow(entity, overflow)
  if not overflow or not entity or not entity.valid then return end
  for index = 1, #overflow do
    local stack = overflow[index]
    if stack and stack.valid_for_read then
      entity.surface.spill_item_stack{
        position = entity.position,
        stack = stack_definition(stack),
        allow_belts = false,
        force = entity.force
      }
    end
  end
end

function research.apply_to_nest_entity(entity)
  if not entity or not entity.valid or entity.name ~= constants.nest_entity then return end

  local cargo_slots = research.nest_cargo_slots_for_force_name(entity.force.name)
  local desired_total = cargo_slots
  local current_total = entity.get_inventory_size_override(defines.inventory.chest)
  if current_total == desired_total then return end

  local overflow = game.create_inventory(constants.nest_slots.max_total)
  entity.set_inventory_size_override(defines.inventory.chest, desired_total, overflow)
  spill_overflow(entity, overflow)
  overflow.destroy()
end

function research.apply_to_carrier(record)
  if not record or not record.entity or not record.entity.valid then return end
  if record.entity.name ~= constants.carrier_unit then return end

  record.base_speed = record.base_speed or constants.research.base_carrier_speed
  local multiplier = research.effects_for_force_name(record.entity.force.name).carrier_speed_multiplier
  record.entity.speed = record.base_speed * multiplier
end

local function apply_to_force_runtime(force_name)
  local data = state.get()
  for _, record in pairs(data.carriers) do
    if record.entity and record.entity.valid and record.entity.force.name == force_name then
      research.apply_to_carrier(record)
    end
  end

  for _, record in pairs(data.nests) do
    if record.entity and record.entity.valid and record.entity.force.name == force_name then
      research.apply_to_nest_entity(record.entity)
    end
  end

  for _, record in pairs(data.depots or {}) do
    if record.entity and record.entity.valid and record.entity.force.name == force_name then
      record.force_name = record.entity.force.name
    end
  end
end

function research.rebuild_force(force, apply_runtime)
  if not force or not force.valid then return nil end
  local data = state.get()
  local effects = calculate_force_effects(force)
  data.force_effects[force.name] = effects

  if apply_runtime then
    apply_to_force_runtime(force.name)
  end

  return effects
end

function research.rebuild_all(apply_runtime)
  for _, force in pairs(game.forces) do
    research.rebuild_force(force, apply_runtime)
  end
end

function research.on_research_changed(event)
  if not event.research or not event.research.valid then return end
  if not tracked_technologies[event.research.name] then return end
  research.rebuild_force(event.research.force, true)
end

function research.on_technology_effects_reset(event)
  if not event.force or not event.force.valid then return end
  research.rebuild_force(event.force, true)
end

return research

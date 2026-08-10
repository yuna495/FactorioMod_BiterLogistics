local research = require("scripts.research")

local networks = {}

local function position_of(record)
  if not record then return nil end
  if record.position then return record.position end
  if record.entity and record.entity.valid then return record.entity.position end
  return nil
end

function networks.same_force_surface(a, b)
  return a and b
    and a.force_name == b.force_name
    and a.surface_index == b.surface_index
end

function networks.distance_squared(a, b)
  local a_position = position_of(a)
  local b_position = position_of(b)
  if not a_position or not b_position then return 0 end

  local dx = a_position.x - b_position.x
  local dy = a_position.y - b_position.y
  return dx * dx + dy * dy
end

function networks.distance(a, b)
  return networks.distance_squared(a, b) ^ 0.5
end

function networks.route_distance(depot, source, destination)
  return networks.distance(depot, source)
    + networks.distance(source, destination)
    + networks.distance(destination, depot)
end

function networks.depot_range(depot)
  local force_name = depot and depot.force_name
  if not force_name and depot and depot.entity and depot.entity.valid then
    force_name = depot.entity.force.name
  end
  return research.depot_range_for_force_name(force_name)
end

function networks.depot_covers_position(depot, position)
  local depot_position = position_of(depot)
  if not depot_position or not position then return false end

  local range = networks.depot_range(depot)
  local dx = position.x - depot_position.x
  local dy = position.y - depot_position.y
  return dx * dx + dy * dy <= range * range
end

function networks.depot_covers_nest(depot, nest)
  return networks.same_force_surface(depot, nest)
    and networks.depot_covers_position(depot, position_of(nest))
end

return networks

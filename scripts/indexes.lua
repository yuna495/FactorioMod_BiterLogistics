local state = require("scripts.state")

local indexes = {}

local function scoped_table(root, force_name, surface_index)
  if not force_name or not surface_index then return nil end
  root[force_name] = root[force_name] or {}
  root[force_name][surface_index] = root[force_name][surface_index] or {}
  return root[force_name][surface_index]
end

local function unregister(root, record)
  if not record then return end
  local force_name = record.index_force_name or record.force_name
  local surface_index = record.index_surface_index or record.surface_index
  local scoped = force_name and surface_index and root[force_name] and root[force_name][surface_index]
  if scoped then
    scoped[record.id] = nil
  end
  record.index_force_name = nil
  record.index_surface_index = nil
end

local function register(root, record)
  if not record or not record.id then return end
  unregister(root, record)
  local scoped = scoped_table(root, record.force_name, record.surface_index)
  if not scoped then return end
  scoped[record.id] = true
  record.index_force_name = record.force_name
  record.index_surface_index = record.surface_index
end

function indexes.register_nest(record)
  register(state.get().nests_by_force_surface, record)
end

function indexes.unregister_nest(record)
  unregister(state.get().nests_by_force_surface, record)
end

function indexes.register_depot(record)
  register(state.get().depots_by_force_surface, record)
end

function indexes.unregister_depot(record)
  unregister(state.get().depots_by_force_surface, record)
end

function indexes.clear_nests()
  state.get().nests_by_force_surface = {}
end

function indexes.clear_depots()
  state.get().depots_by_force_surface = {}
end

function indexes.nest_ids(force_name, surface_index)
  local root = state.get().nests_by_force_surface
  return force_name and surface_index and root[force_name] and root[force_name][surface_index] or {}
end

function indexes.depot_ids(force_name, surface_index)
  local root = state.get().depots_by_force_surface
  return force_name and surface_index and root[force_name] and root[force_name][surface_index] or {}
end

return indexes

local constants = require("constants")

local egg_research = {}

local function technology(force, name)
  if not force or not force.valid then return nil end
  return force.technologies[name]
end

local function is_researched(force, name)
  local tech = technology(force, name)
  return tech and tech.valid and tech.researched or false
end

local function has_biter_egg(player)
  if not player or not player.valid then return false end
  local inventory = player.get_main_inventory()
  return inventory and inventory.valid and inventory.get_item_count(constants.spawner_egg_loot.egg_item) > 0
end

local function trigger_for_force(force)
  if not force or not force.valid then return false end
  if is_researched(force, constants.research.base) then return false end
  force.script_trigger_research(constants.research.base)
  return true
end

function egg_research.check_player(player)
  if not player or not player.valid then return false end
  if is_researched(player.force, constants.research.base) then return false end
  if not has_biter_egg(player) then return false end
  return trigger_for_force(player.force)
end

function egg_research.on_player_main_inventory_changed(event)
  local player = game.get_player(event.player_index)
  egg_research.check_player(player)
end

function egg_research.check_existing_players()
  for _, player in pairs(game.players) do
    egg_research.check_player(player)
  end
end

function egg_research.migrate_legacy_research()
  local data = storage.biter_logistics
  local old_schema_version = data and data.schema_version or nil
  if not old_schema_version or old_schema_version >= 14 then return end

  for _, force in pairs(game.forces) do
    local base = technology(force, constants.research.base)
    local logistics_nest = technology(force, constants.research.logistics_nest)
    if base and base.valid
      and base.researched
      and logistics_nest
      and logistics_nest.valid
      and not logistics_nest.researched
    then
      logistics_nest.researched = true
    end
  end
end

return egg_research

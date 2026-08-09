local constants = require("constants")
local state = require("scripts.state")
local nests = require("scripts.nests")
local carriers = require("scripts.carriers")

local gui = {}

local function valid(element)
  return element and element.valid
end

local function root(player)
  return player.gui.relative[constants.gui.root] or player.gui.screen[constants.gui.root]
end

local function close(player)
  local relative_frame = player.gui.relative[constants.gui.root]
  if relative_frame then relative_frame.destroy() end
  local screen_frame = player.gui.screen[constants.gui.root]
  if screen_frame then screen_frame.destroy() end
  local player_state = state.get().players[player.index]
  if player_state then
    player_state.open_nest_id = nil
    player_state.destination_options = nil
  end
end

local function destination_index(record, options)
  if not record.destination_nest_id then return 1 end
  for index, option in ipairs(options) do
    if option.nest_id == record.destination_nest_id then return index end
  end
  return 1
end

local function update_name_suffix(player, record)
  local frame = root(player)
  local name_flow = frame and frame[constants.gui.name_flow]
  local suffix_label = name_flow and name_flow[constants.gui.name_suffix_label]
  if suffix_label then
    suffix_label.caption = nests.duplicate_suffix_caption(record)
  end
end

local function add_status(frame, nest_id)
  local carrier_count = carriers.count_for_nest(nest_id)
  local active_count = carriers.active_for_nest(nest_id)

  frame.add{type = "label", caption = {"gui.biter-logistics-carrier-slot"}}
  frame.add{type = "label", caption = {"gui.biter-logistics-cargo-slots"}}

  local carrier_flow = frame.add{type = "flow", direction = "horizontal"}
  carrier_flow.add{type = "label", caption = {"gui.biter-logistics-carriers"}}
  carrier_flow.add{type = "label", caption = tostring(carrier_count)}

  local status_flow = frame.add{type = "flow", direction = "horizontal"}
  status_flow.add{type = "label", caption = {"gui.biter-logistics-status"}}
  if carrier_count == 0 then
    status_flow.add{type = "label", caption = {"gui.biter-logistics-status-no-carriers"}}
  else
    status_flow.add{type = "label", caption = {"gui.biter-logistics-status-carriers", carrier_count, active_count}}
  end
end

function gui.open(player, record)
  if not record then return end
  close(player)

  local data = state.get()
  local player_state = data.players[player.index] or {}
  data.players[player.index] = player_state

  local frame = player.gui.relative.add{
    type = "frame",
    name = constants.gui.root,
    caption = {"gui.biter-logistics-title"},
    direction = "vertical",
    anchor = {
      gui = defines.relative_gui_type.container_gui,
      position = defines.relative_gui_position.right,
      names = {constants.nest_entity}
    }
  }

  player_state.open_nest_id = record.id

  local name_flow = frame.add{
    type = "flow",
    name = constants.gui.name_flow,
    direction = "horizontal"
  }
  name_flow.add{type = "label", caption = {"gui.biter-logistics-name"}}
  name_flow.add{
    type = "textfield",
    name = constants.gui.name_field,
    text = record.display_name or ""
  }
  name_flow.add{
    type = "label",
    name = constants.gui.name_suffix_label,
    caption = nests.duplicate_suffix_caption(record)
  }

  local options = nests.destination_options(record.id)
  player_state.destination_options = options
  local items = {}
  for index, option in ipairs(options) do
    items[index] = option.caption
  end

  local destination_flow = frame.add{type = "flow", direction = "horizontal"}
  destination_flow.add{type = "label", caption = {"gui.biter-logistics-destination"}}
  destination_flow.add{
    type = "drop-down",
    name = constants.gui.destination_dropdown,
    items = items,
    selected_index = destination_index(record, options)
  }

  add_status(frame, record.id)
end

function gui.refresh(player)
  local player_state = state.get().players[player.index]
  local record = player_state and player_state.open_nest_id and nests.get(player_state.open_nest_id)
  if record and nests.is_valid(record) then
    gui.open(player, record)
  else
    close(player)
  end
end

function gui.close_nest(nest_id)
  for _, player in pairs(game.players) do
    local player_state = state.get().players[player.index]
    if player_state and player_state.open_nest_id == nest_id then
      close(player)
    end
  end
end

function gui.on_opened(event)
  local player = game.get_player(event.player_index)
  if not player or not event.entity or not event.entity.valid then return end
  local record = nests.get_by_entity(event.entity)
  if record then
    gui.open(player, record)
  end
end

function gui.on_closed(event)
  local player = game.get_player(event.player_index)
  if not player then return end

  if event.element and valid(event.element) and event.element.name == constants.gui.root then
    close(player)
    return
  end

  if event.entity and event.entity.valid and event.entity.name == constants.nest_entity then
    close(player)
  end
end

function gui.on_text_changed(event)
  if not valid(event.element) or event.element.name ~= constants.gui.name_field then return end
  local player = game.get_player(event.player_index)
  local player_state = state.get().players[event.player_index]
  if not player or not player_state or not player_state.open_nest_id then return end
  nests.set_display_name(player_state.open_nest_id, event.element.text)
  update_name_suffix(player, nests.get(player_state.open_nest_id))
end

function gui.on_selection_state_changed(event)
  if not valid(event.element) or event.element.name ~= constants.gui.destination_dropdown then return end
  local player = game.get_player(event.player_index)
  local player_state = state.get().players[event.player_index]
  if not player or not player_state or not player_state.open_nest_id then return end

  local option = player_state.destination_options and player_state.destination_options[event.element.selected_index]
  if not option then return end
  nests.set_destination(player_state.open_nest_id, option.nest_id)
  gui.refresh(player)
end

return gui

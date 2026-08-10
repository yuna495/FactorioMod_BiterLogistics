local constants = require("constants")
local state = require("scripts.state")
local nests = require("scripts.nests")
local depots = require("scripts.depots")
local carriers = require("scripts.carriers")
local logistics = require("scripts.logistics")
local food = require("scripts.food")

local gui = {}

local function valid(element)
  return element and element.valid
end

local function root(player)
  return player.gui.relative[constants.gui.root] or player.gui.screen[constants.gui.root]
end

local function player_state(player_index)
  local data = state.get()
  data.players[player_index] = data.players[player_index] or {}
  return data.players[player_index]
end

local function close(player)
  local relative_frame = player.gui.relative[constants.gui.root]
  if relative_frame then relative_frame.destroy() end
  local screen_frame = player.gui.screen[constants.gui.root]
  if screen_frame then screen_frame.destroy() end
  local pstate = state.get().players[player.index]
  if pstate then
    pstate.open_type = nil
    pstate.open_nest_id = nil
    pstate.open_depot_id = nil
  end
end

local function update_name_suffix(player, record)
  local frame = root(player)
  local name_flow = frame and frame[constants.gui.name_flow]
  local suffix_label = name_flow and name_flow[constants.gui.name_suffix_label]
  if suffix_label then
    suffix_label.caption = nests.duplicate_suffix_caption(record)
  end
end

local function add_name(frame, text, suffix)
  local name_flow = frame.add{
    type = "flow",
    name = constants.gui.name_flow,
    direction = "horizontal"
  }
  name_flow.add{type = "label", caption = {"gui.biter-logistics-name"}}
  name_flow.add{
    type = "textfield",
    name = constants.gui.name_field,
    text = text or "",
    icon_selector = true
  }
  name_flow.add{
    type = "label",
    name = constants.gui.name_suffix_label,
    caption = suffix or ""
  }
end

local function add_nest_status(frame, record)
  frame.add{type = "label", caption = {"gui.biter-logistics-cargo-slots", nests.cargo_slot_count(record)}}
  local mode = record.mode == constants.nest_modes.request
    and {"gui.biter-logistics-mode-request"}
    or {"gui.biter-logistics-mode-supply"}
  frame.add{type = "label", caption = {"gui.biter-logistics-status-nest", mode}}
end

local function add_depot_status(frame, record)
  local carrier_count = depots.assigned_carrier_count(record)
  local carrier_capacity = depots.carrier_capacity(record)
  local active_count = carriers.active_for_depot(record.id)

  frame.add{type = "label", caption = {"gui.biter-logistics-status-carriers", carrier_count, carrier_capacity, active_count}}
  frame.add{type = "label", caption = {"gui.biter-logistics-depot-food-slots", constants.depot_slots.food_count}}
  local food_flow = frame.add{type = "flow", direction = "horizontal"}
  food_flow.add{type = "label", caption = {"gui.biter-logistics-accepted-food"}}
  for _, entry in ipairs(food.accepted_for_force_name(record.force_name)) do
    food_flow.add{
      type = "sprite-button",
      sprite = "item/" .. entry.name,
      style = "slot_button",
      tooltip = {"gui.biter-logistics-food-item-tooltip", "[item=" .. entry.name .. "]", entry.value}
    }
  end
  if carrier_count >= carrier_capacity and depots.count_carrier_items(record) > 0 then
    frame.add{type = "label", caption = {"gui.biter-logistics-status-carrier-capacity-reached"}}
  end
  frame.add{type = "label", caption = {"gui.biter-logistics-food-energy", depots.available_food_energy(record)}}
end

local function add_nest_controls(frame, record)
  local mode_flow = frame.add{type = "flow", direction = "horizontal"}
  mode_flow.add{type = "label", caption = {"gui.biter-logistics-mode"}}
  mode_flow.add{
    type = "drop-down",
    name = constants.gui.mode_dropdown,
    items = {
      {"gui.biter-logistics-mode-supply"},
      {"gui.biter-logistics-mode-request"}
    },
    selected_index = record.mode == constants.nest_modes.request and 2 or 1
  }

  local request_flow = frame.add{type = "flow", direction = "horizontal"}
  request_flow.add{type = "label", caption = {"gui.biter-logistics-request-item"}}
  local button = request_flow.add{
    type = "choose-elem-button",
    name = constants.gui.request_item_button,
    elem_type = "item",
    style = "slot_button"
  }
  button.elem_value = record.request_item
  request_flow.visible = record.mode == constants.nest_modes.request
end

function gui.open_nest(player, record)
  if not record then return end
  close(player)

  local pstate = player_state(player.index)
  pstate.open_type = "nest"
  pstate.open_nest_id = record.id

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

  add_name(frame, record.display_name, nests.duplicate_suffix_caption(record))
  add_nest_controls(frame, record)
  add_nest_status(frame, record)
end

function gui.open_depot(player, record)
  if not record then return end
  close(player)

  local pstate = player_state(player.index)
  pstate.open_type = "depot"
  pstate.open_depot_id = record.id

  local frame = player.gui.relative.add{
    type = "frame",
    name = constants.gui.root,
    caption = {"gui.biter-logistics-depot-title"},
    direction = "vertical",
    anchor = {
      gui = defines.relative_gui_type.container_gui,
      position = defines.relative_gui_position.right,
      names = {constants.depot_entity}
    }
  }

  add_name(frame, record.display_name)
  add_depot_status(frame, record)
end

function gui.refresh(player)
  local pstate = state.get().players[player.index]
  if not pstate then return end
  if pstate.open_type == "nest" then
    local record = pstate.open_nest_id and nests.get(pstate.open_nest_id)
    if record and nests.is_valid(record) then
      gui.open_nest(player, record)
    else
      close(player)
    end
  elseif pstate.open_type == "depot" then
    local record = pstate.open_depot_id and depots.get(pstate.open_depot_id)
    if record and depots.is_valid(record) then
      gui.open_depot(player, record)
    else
      close(player)
    end
  end
end

function gui.close_nest(nest_id)
  for _, player in pairs(game.players) do
    local pstate = state.get().players[player.index]
    if pstate and pstate.open_type == "nest" and pstate.open_nest_id == nest_id then
      close(player)
    end
  end
end

function gui.close_depot(depot_id)
  for _, player in pairs(game.players) do
    local pstate = state.get().players[player.index]
    if pstate and pstate.open_type == "depot" and pstate.open_depot_id == depot_id then
      close(player)
    end
  end
end

function gui.on_opened(event)
  local player = game.get_player(event.player_index)
  if not player or not event.entity or not event.entity.valid then return end
  local nest_record = nests.get_by_entity(event.entity)
  if nest_record then
    gui.open_nest(player, nest_record)
    return
  end
  local depot_record = depots.get_by_entity(event.entity)
  if depot_record then
    gui.open_depot(player, depot_record)
  end
end

function gui.on_closed(event)
  local player = game.get_player(event.player_index)
  if not player then return end

  if event.element and valid(event.element) and event.element.name == constants.gui.root then
    close(player)
    return
  end

  if event.entity and event.entity.valid
    and (event.entity.name == constants.nest_entity or event.entity.name == constants.depot_entity) then
    close(player)
  end
end

function gui.on_text_changed(event)
  if not valid(event.element) or event.element.name ~= constants.gui.name_field then return end
  local player = game.get_player(event.player_index)
  local pstate = state.get().players[event.player_index]
  if not player or not pstate then return end

  if pstate.open_type == "nest" and pstate.open_nest_id then
    nests.set_display_name(pstate.open_nest_id, event.element.text)
    update_name_suffix(player, nests.get(pstate.open_nest_id))
  elseif pstate.open_type == "depot" and pstate.open_depot_id then
    depots.set_display_name(pstate.open_depot_id, event.element.text)
  end
end

function gui.on_selection_state_changed(event)
  if not valid(event.element) or event.element.name ~= constants.gui.mode_dropdown then return end
  local player = game.get_player(event.player_index)
  local pstate = state.get().players[event.player_index]
  if not player or not pstate or pstate.open_type ~= "nest" or not pstate.open_nest_id then return end

  local mode = event.element.selected_index == 2 and constants.nest_modes.request or constants.nest_modes.supply
  nests.set_mode(pstate.open_nest_id, mode)
  if mode == constants.nest_modes.request then
    logistics.enqueue_request(pstate.open_nest_id)
  end
  gui.refresh(player)
end

function gui.on_elem_changed(event)
  if not valid(event.element) or event.element.name ~= constants.gui.request_item_button then return end
  local player = game.get_player(event.player_index)
  local pstate = state.get().players[event.player_index]
  if not player or not pstate or pstate.open_type ~= "nest" or not pstate.open_nest_id then return end

  nests.set_request_item(pstate.open_nest_id, event.element.elem_value)
  logistics.enqueue_request(pstate.open_nest_id)
end

return gui

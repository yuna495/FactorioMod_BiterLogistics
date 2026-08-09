local constants = require("constants")

local visuals = {}

local function clamp(value)
  value = tonumber(value) or 0
  if value < 0 then return 0 end
  if value > 1 then return 1 end
  return value
end

local function setting_value(name, fallback)
  local setting = settings and settings.startup and settings.startup[name]
  if not setting then return fallback end
  return setting.value
end

local function color_for(kind)
  local name = constants.visuals.color_settings[kind]
  local defaults = constants.visuals.default_colors[kind]
  if not name or not defaults then
    return {r = 1, g = 1, b = 1, a = constants.visuals.overlay_alpha}
  end

  local value = setting_value(name, defaults) or defaults
  return {
    r = clamp(value.r or defaults.r),
    g = clamp(value.g or defaults.g),
    b = clamp(value.b or defaults.b),
    a = clamp(value.a or constants.visuals.overlay_alpha)
  }
end

local function render_object(reference)
  if not reference then return nil end
  if type(reference) == "number" then
    return rendering.get_object_by_id(reference)
  end
  return reference
end

local function destroy_object(reference)
  local object = render_object(reference)
  if not object then return end
  pcall(function()
    if object.valid ~= false then
      object.destroy()
    end
  end)
end

local function draw_color(record, kind)
  if not record or not record.entity or not record.entity.valid then return nil end
  return rendering.draw_sprite{
    sprite = constants.visuals.spawner_mask_sprite,
    surface = record.entity.surface,
    target = record.entity,
    tint = color_for(kind),
    render_layer = "higher-object-above"
  }
end

function visuals.update_nest(record)
  if not record then return end
  destroy_object(record.color_render_object_id)
  destroy_object(record.color_render_object)
  record.color_render_object_id = nil
  record.color_render_object = nil

  local kind = record.mode == constants.nest_modes.request and "request" or "supply"
  record.color_render_kind = kind
  local object = draw_color(record, kind)
  record.color_render_object_id = object and object.id or nil
end

function visuals.update_depot(record)
  if not record then return end
  destroy_object(record.color_render_object_id)
  destroy_object(record.color_render_object)
  record.color_render_object_id = nil
  record.color_render_object = nil
  record.color_render_kind = "depot"
  local object = draw_color(record, "depot")
  record.color_render_object_id = object and object.id or nil
end

function visuals.destroy(record)
  if not record then return end
  destroy_object(record.color_render_object_id)
  destroy_object(record.color_render_object)
  record.color_render_object_id = nil
  record.color_render_object = nil
  record.color_render_kind = nil
end

return visuals

data:extend({
  {
    type = "color-setting",
    name = "biter-logistics-supply-color",
    setting_type = "startup",
    default_value = {r = 1, g = 0.28, b = 0.22, a = 0.82},
    order = "a[supply]"
  },
  {
    type = "color-setting",
    name = "biter-logistics-request-color",
    setting_type = "startup",
    default_value = {r = 0.25, g = 0.58, b = 1, a = 0.82},
    order = "b[request]"
  },
  {
    type = "color-setting",
    name = "biter-logistics-fuel-depot-color",
    setting_type = "startup",
    default_value = {r = 0.35, g = 0.95, b = 0.38, a = 0.82},
    order = "c[fuel-depot]"
  },
  {
    type = "string-setting",
    name = "biter-logistics-feral-cargo-behavior",
    setting_type = "runtime-global",
    default_value = "drop",
    allowed_values = {"drop", "destroy"},
    order = "d[feral-cargo-behavior]"
  }
})

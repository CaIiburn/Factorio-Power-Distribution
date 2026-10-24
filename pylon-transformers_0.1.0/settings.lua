data:extend({
  ---------------------------------------------------------------------------------------------------
  -- Transformers
  ---------------------------------------------------------------------------------------------------

  -- Startup setting: how many ticks pass between transfer updates of one transformer.
  -- It is a startup setting because the energy buffers in the prototypes are sized from it.
  {
    type = "int-setting",
    name = "pt-update-interval",
    setting_type = "startup",
    default_value = 10,
    minimum_value = 1,
    maximum_value = 60,
    order = "a",
  },
  -- Runtime setting: whether heat-tier transformers explode when they reach their explosion
  -- temperature. When off, they still heat up, raise alerts and report the temperature.
  {
    type = "bool-setting",
    name = "pt-explosions",
    setting_type = "runtime-global",
    default_value = true,
    order = "a",
  },

  ---------------------------------------------------------------------------------------------------
  -- Pole classes
  ---------------------------------------------------------------------------------------------------
  {
    type = "double-setting",
    name = "pc-network-cap-multiplier",
    setting_type = "startup",
    default_value = 1,
    minimum_value = 0.25,
    maximum_value = 10,
    order = "b",
  },
  {
    type = "bool-setting",
    name = "pc-enforce-script-built",
    setting_type = "startup",
    default_value = false,
    order = "c",
  },
  {
    type = "string-setting",
    name = "pc-autowire-mode",
    setting_type = "runtime-per-user",
    default_value = "chain",
    allowed_values = { "chain", "nearest", "off" },
    order = "a",
  },
  {
    type = "bool-setting",
    name = "pc-show-zones",
    setting_type = "runtime-per-user",
    default_value = true,
    order = "b",
  },
  {
    type = "int-setting",
    name = "pc-zone-radius",
    setting_type = "runtime-per-user",
    default_value = 40,
    minimum_value = 16,
    maximum_value = 96,
    order = "c",
  },
})

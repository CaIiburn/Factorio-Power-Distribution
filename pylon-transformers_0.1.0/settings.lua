data:extend({
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
    order = "b",
  },
})

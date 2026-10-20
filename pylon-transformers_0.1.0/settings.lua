-- Startup setting: how many ticks pass between transfer updates of one transformer.
-- It is a startup setting because the energy buffers in the prototypes are sized from it.
data:extend({
  {
    type = "int-setting",
    name = "pt-update-interval",
    setting_type = "startup",
    default_value = 10,
    minimum_value = 1,
    maximum_value = 60,
    order = "a",
  },
})

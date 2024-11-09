local context = require "artist"()

-- Feel free to include custom modules here:
context:require "custom.display"
context:require "crafting"
context:require "custom.command_listener"
context:require "custom.inv_manager"

-- Run the display function with the context
context.config:save()

context:run()

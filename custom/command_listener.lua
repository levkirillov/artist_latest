--- Allows specifying"dropoff chests" - items deposited into them will be
-- transferred into the main system.

local log = require "artist.lib.log".get_logger(...)
local schema = require "artist.lib.config".schema

return function(context)
  local crafting = context:require "crafting"
  local inv_manager = context:require "custom.inv_manager"

  local config = context.config
    :group("commands", "Defines remote(and not) commands config")
    :define("side", "The side of wired modem to recive messages", 'back', schema.string)
    :get()
  local function missing(missing_item)

  end

  context.mediator:subscribe("crafing.missing", missing)
  -- Register a thread which just scans chests periodically.
  context:spawn(function()
    local crafts = crafting.get_crafts()
    rednet.open(config.side)
    while true do
        local id, message = rednet.receive()
        local data = {}
        for dat in tostring(message):gmatch("%S+") do
            table.insert(data, dat)
        end
        if data[1] == 'craft' then
            crafting.try_multi_craft(data[2],data[3])
        elseif message == 'get_crafts' then
            rednet.send(id, crafts)
        elseif data[1] == 'add_inv' then
          if not data[4] then
            inv_manager.addToInv(data[2],tonumber(data[3]))
          else
            inv_manager.addToInv(data[2],tonumber(data[3]),tonumber(data[4]))
          end
        elseif data[1] == 'take_inv' then
          if not data[4] then
            inv_manager.removeFromInv(data[2],tonumber(data[3]))
          else
            inv_manager.removeFromInv(data[2],tonumber(data[3]),tonumber(data[4]))
          end
        end
    end
  end)
end

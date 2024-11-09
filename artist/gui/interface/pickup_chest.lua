local completion = require "cc.completion"
local interface = require "artist.gui.interface"
local schema = require "artist.lib.config".schema
local tbl = require "artist.lib.tbl"
local pretty = require "cc.pretty"

local function complete_peripheral(str)
  local options = completion.peripheral(str)
  if not options then return nil end

  for i = #options, 1, -1 do
    if tbl.rs_sides[str .. options[i]] then table.remove(options, i) end
  end
  return options
end

return function(context)
  local config_group = context.config
    :group("pickup", "Defines a place to pick up items")
    :define("chest", "The chest from which to pick up items", "minecraft:chest_xx", schema.peripheral)
    :define("mode", "Use player inventory by default", false, schema.boolean)

  local chest = config_group:get().chest
  context.mediator:publish("nterface.inv_mode_set", config_group:get().mode)
  local mode = config_group:get().mode

  if chest == "minecraft:chest_xx" then
    print("No chest is specified in /.artist.d/config. Configure one now?")
    write("Chest Name> ")
    chest = read(nil, nil, complete_peripheral)

    if tbl.rs_sides[chest] then
      error("Dropoff chest must be attached via modems (for instance minecraft:chest_1).", 0)
    end

    config_group.underlying.chest = chest
  end

  if chest == "" then
    print("No chest configured, item extraction will not work.")
  end
  
  local items = context:require "artist.core.items"
  local inv_manager = context:require "custom.inv_manager"
  local function update_inv_mode(md)
    mode = md
  end
  context.mediator:subscribe("interface.inv_mode_update", update_inv_mode)

  return interface(context, function(hash, quantity)
    if mode then
      inv_manager.addToInv(hash,quantity)
    else
      if chest ~= "" then
        items:extract(chest, hash, quantity) 
        context.mediator:publish("pickup.take", { count = quantity, name = hash })
      end
    end
  end)
end

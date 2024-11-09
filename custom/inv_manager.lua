local log = require "artist.lib.log".get_logger(...)
local schema = require "artist.lib.config".schema
local class = require "artist.lib.class"
local inv_manager = class "custom.inv_manager"  ---@class inv_manager

local Items
local config
local inventory_manager_
local buffer_
local buffer_side
local inv
local buff
local _context

local wait = false

local function addToInv(item_name,count,slot)
    if inventory_manager_ == 'inventoryManager_xx' or buffer_ == 'minecraft:barell_xx' then return end
    while wait do
        os.sleep(0.001)
    end
    wait = true
    if slot == nil then
        Items:extract(buffer_, item_name, count, nil, function()
            inv.addItemToPlayer(buffer_side, {name=item_name, count=count})
            _context.mediator:publish("pickup.take", { count = count, name = item_name })
        end)
    else
        Items:extract(buffer_, item_name, count, nil, function()
            inv.addItemToPlayer(buffer_side, {name=item_name, toSlot=slot, count=count})
            _context.mediator:publish("pickup.take", { count = count, name = item_name })
        end)
    end
    wait = false
end

local function removeFromInv(item_name,count,slot)
    if inventory_manager_ == 'inventoryManager_xx' or buffer_ == 'minecraft:barell_xx' then return end
    while wait do
        os.sleep(0.001)
    end
    wait = true
    if slot then
        inv.removeItemFromPlayer(buffer_side, {name=item_name, fromSlot=slot, toSlot=1, count=count})
        while not next(buff.list()[2]) do
            os.sleep(0.001)
        end
        os.sleep(0.5)
        Items:insert(buffer_, 1, 64)
        _context.mediator:publish("dropoff.add", {name=item_name, count=count})
    else
        inv.removeItemFromPlayer(buffer_side, {name=item_name, count=count, toSlot=1})
        while not next(buff.list()[2]) do
            os.sleep(0.001)
            os.sleep(0.5)
        end
        Items:insert(buffer_, 2, 64)
        _context.mediator:publish("dropoff.add", {name=item_name, count=count})
    end
    wait = false
end

local function spawn()
end
function inv_manager:initialise(context)
    Items = context:require "artist.core.items"
    config = context.config
      :group("inventory_manager", "Defines inventory manager api")
      :define("inventory_manager", "The inventory peripheral", 'inventoryManager_xx', schema.peripheral)
      :define("buffer", "The inventory next to inventory manager", 'minecraft:barell_xx', schema.peripheral)
      :define("buffer_side", "The inventory next to inventory manager SIDE!(right,left,front,back,top,bottom)", 'right', schema.string)
    inventory_manager_ = config:get().inventory_manager
    buffer_ = config:get().buffer
    buffer_side = config:get().buffer_side
    inv = peripheral.wrap(inventory_manager_)
    buff = peripheral.wrap(buffer_)
    _context = context
    context:spawn(spawn)
end
inv_manager.addToInv = addToInv
inv_manager.removeFromInv = removeFromInv
return inv_manager

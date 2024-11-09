local barrel_from = nil
local barrel_to = nil
local in_ME = nil
local pretty = require "cc.pretty"
write("In ME(true/false): ")
--while true do
--  local v = read()
--  if v then
--    in_ME = v == "true" and true or false
--    break
--  end
--end

local slt = {
  [1] = 1,
  [2] = 2,
  [3] = 3,
  [4] = 5,
  [5] = 6,
  [6] = 7,
  [7] = 9,
  [8] = 10,
  [9] = 11,
}

-- Function to list available barrels and prompt for selection
local function selectBarrels()
  local barl = peripheral.getNames()
  local barrels = {}

  for _, br in ipairs(barl) do
    if br == "front" or br == "top" or br == "bottom" then
      table.insert(barrels, br)
    end
  end

  if #barrels == 0 then
    error("No barrels found nearby!")
  end

  print("Available barrels:")
  for i, side in ipairs(barrels) do
    print(i .. ": " .. side)
  end

  -- Prompt user to select the input barrel
  while true do
    write("Select barrel to take items from (number): ")
    local choice = tonumber(read())
    if choice and barrels[choice] then
      barrel_from = barrels[choice]
      break
    end
    print("Invalid choice, please try again.")
  end

  -- Prompt user to select the output barrel
  while true do
    write("Select barrel to push items to (number): ")
    local choice = tonumber(read())
    if choice and barrels[choice] and barrels[choice] ~= barrel_from then
      barrel_to = barrels[choice]
      break
    end
    print("Invalid choice, please try again.")
  end
end

-- Automatically detect the input and output barrels
selectBarrels()

local cycle = false
while true do
  os.sleep(1)
  if not cycle then
    cycle = true
    for i = 1, 16 do
      while turtle.getItemCount(i) > 0 do
        turtle.select(i)
        if barrel_to == "front" then
          turtle.drop()
        elseif barrel_to == "top" then
          turtle.dropUp()
        else
          turtle.dropDown()
        end
        --os.sleep(0.1)
      end
    end
    os.sleep(1)
    while true do
      local dev = peripheral.wrap(barrel_from)
      for i = 1, 9 do
        local slot = slt[i]
        if dev.list()[i] ~= nil then
          turtle.select(slot)
          if barrel_from == "front" then
            turtle.suck(1)
          elseif barrel_from == "top" then
            turtle.suckUp(1)
          else
            turtle.suckDown(1)
          end
          --os.sleep(0.1)
        end
      end
      local dev = peripheral.wrap(barrel_from)
      if next(dev.list()) == nil then
        break
      end
    end
    os.sleep(1)
    print(turtle.craft(64))
    cycle = false
    --os.sleep(1)
  end
end

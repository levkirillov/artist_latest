-- Load JSON library (assuming you're using a JSON parsing library like dkjson or cjson)
local class = require "artist.lib.class"
local Crafting = class "artist.custom.crafting"  ---@class Crafting

local json = require 'json'
local have_enough
local log
local load_crafting_status
local count_active_custom_crafts_for_devices
local save_crafting_status
local do_craft
local pretty = require "cc.pretty"
local items
local get_amount
local try_multi_craft
local save_reserved
local have_enough_simp
local check_done = true
local inserting = false
local reserving = false


local file = io.open(shell.dir().."/crafting_status.json", "w")
file:write("{}")
file:close()
local file = io.open(shell.dir().."/log.txt", "w")
file:write("")
file:close()

-- Load the recipes from the file
local function load_recipes()
    local file = io.open(shell.dir().."/recipes.json", "r")
    if file then
        local content = file:read("*a")
        file:close()
        return json.decode(content)
    else
        return {}
    end
end

function count_active_custom_crafts_for_devices(devices)
    local crafting_status = load_crafting_status()
    local active_crafts = 0

    -- Count how many processes are using the same custom devices
    for _, process in ipairs(crafting_status) do
        if process.recipe.devices then
            for device, _ in pairs(devices) do
                if process.recipe.devices[device] and process.status == "in_progress" then
                    active_crafts = active_crafts + 1
                end
            end
        end
    end

    return active_crafts
end

-- Function to count how many processes are using the same input chest (or devices)
local function count_active_crafts_for_input(input_c)
    local crafting_status = load_crafting_status()
    local active_crafts = 0

    -- Count how many processes are using the same input chest
    for _, process in ipairs(crafting_status) do
        if process.recipe.input_c == input_c and process.status == "in_progress" then
            active_crafts = active_crafts + 1
        end
    end

    return active_crafts
end

-- Function to check if custom crafting is busy, now considering multi_craft and multi_limit
local function is_crafting_busy(recipe)
    local crafting_status = load_crafting_status()
    if not crafting_status or not crafting_status.recipe then
        return false
    end
    
    -- If multi_craft is enabled, check the limit for both input chest and devices
    if recipe.multi_craft then
        -- Check for chest-based multi-crafting (input_c)
        local active_crafts_input = count_active_crafts_for_input(recipe.input_c)
        if active_crafts_input >= recipe.multi_limit then
            return true -- Input chest multi-craft limit reached
        end

        -- Check for custom devices multi-crafting
        if recipe.devices then
            local active_crafts_devices = count_active_custom_crafts_for_devices(recipe.devices)
            if active_crafts_devices >= recipe.multi_limit then
                return true -- Devices multi-craft limit reached
            end
        end

        -- Check if devices are being used for other recipes
        for device, _ in pairs(recipe.devices) do
            for _, process in ipairs(crafting_status) do
                if process.recipe.devices and process.recipe.devices[device] and process.status == "in_progress" and process.recipe.name ~= recipe.name then
                    return true -- Device is in use by another crafting process with a different recipe
                end
            end
        end
    else
        -- Non-multi-craft: Check if input chest is in use
        for _, process in ipairs(crafting_status) do
            if process.recipe.input_c == recipe.input_c and process.status == "in_progress" then
                return true -- Input chest is already in use
            end
        end

        -- Check if custom devices are in use
        if recipe.devices then
            for device, _ in pairs(recipe.devices) do
                for _, process in ipairs(crafting_status) do
                    if process.recipe.devices and process.recipe.devices[device] and process.status == "in_progress" then
                        return true -- Device is in use by another crafting process
                    end
                end
            end
        end
    end

    return false -- No busy process found
end

-- Save the crafting process to a file (ensure it's always an array)
function save_crafting_status(status)
    -- Ensure that 'status' is always a list (array)
    if type(status) ~= "table" or status[1] == nil then
        if status[1] == nil then
            status = {}
        else
            status = {status}  -- Wrap single object in array if it's not already
        end
    end

    local file = io.open(shell.dir().."/crafting_status.json", "w")

    file:write(json.encode(status))  -- Save as JSON array
    file:close()
end


-- Load the crafting process from a file
function load_crafting_status()
    local file = io.open(shell.dir().."/crafting_status.json", "r")
    if file then
        local content = file:read("*a")
        file:close()
        local status = json.decode(content)
        -- Ensure it is an array, not nested tables
        return type(status) == "table" and status or {}
    else
        return {}  -- No active crafting processes
    end
end


function log_status()
    local crafting_status = load_crafting_status()
    log("Current crafting status: " .. json.encode(crafting_status))
end

-- Define tag groups (can also be loaded from a file)
tags = {
    ['minecraft:logs'] = {'minecraft:oak_log', 'minecraft:birch_log'}
}

-- Function that checks if the given item or tag is available in sufficient quantity
function has_enough_item_or_tag(item_or_tag, count)
    if type(item_or_tag) == "table" and item_or_tag.tags then
        -- Check for each item in the tag
        for _, tag in ipairs(item_or_tag.tags) do
            if type(tag) == "string" then
                if have_enough(tag, count) then
                    return true
                end
            end
            for _, tag_item in ipairs(tags[tag] or {}) do
                if have_enough(tag_item, count) then
                    return true
                end
            end
        end
    else
        -- Direct check for the item itself
        return have_enough(item_or_tag, count)
    end
    return false
end
-- Function to extract and merge items within a scheme
function extract_and_merge_items_scheme(scheme)
    local extractedItems = {}

    for row = 1, #scheme do
        for col = 1, #scheme[row] do
            local item = scheme[row][col]

            if type(item) == "table" and #item > 1 and type(item[2]) == "table" and item[2].count then
                local itemName = item[1]
                local quantity = item[2].count or 1  -- Default count to 1 if not specified

                -- Merge items with the same name
                if extractedItems[itemName] then
                    extractedItems[itemName] = extractedItems[itemName] + quantity
                else
                    extractedItems[itemName] = quantity
                end
            end
        end
    end

    -- Convert extractedItems to list format
    local result = {}
    for itemName, quantity in pairs(extractedItems) do
        table.insert(result, {itemName, quantity})
    end

    return result
end
-- Function to extract and merge items specifically from devices
function extract_and_merge_from_devices(devices)
    local mergedItems = {}

    for _, slots in pairs(devices) do
        for _, itemData in pairs(slots) do
            if type(itemData) == "table" and itemData[2] and type(itemData[2]) == "table" then
                local itemName = itemData[1]
                local requiredCount = itemData[2].count or 1 -- Default to 1 if count is not specified

                -- Merge items with the same name
                if mergedItems[itemName] then
                    mergedItems[itemName] = mergedItems[itemName] + requiredCount
                else
                    mergedItems[itemName] = requiredCount
                end
            end
        end
    end

    -- Convert mergedItems to the desired format
    local result = {}
    for itemName, quantity in pairs(mergedItems) do
        table.insert(result, {itemName, quantity})
    end

    return result
end
-- Function to merge items with the same name in a list
function merge_items(itemList)
    local mergedItems = {}

    -- Merge items with the same name
    for _, item in ipairs(itemList) do
        local itemName, quantity = item[1], item[2]

        if mergedItems[itemName] then
            mergedItems[itemName] = mergedItems[itemName] + quantity
        else
            mergedItems[itemName] = quantity
        end
    end

    -- Convert mergedItems to the desired format
    local result = {}
    for itemName, quantity in pairs(mergedItems) do
        table.insert(result, {itemName, quantity})
    end

    return result
end
-- Function to merge two lists of items with quantities
function merge_two_lists(list1, list2)
    local mergedItems = {}

    -- Helper function to add items from a list into mergedItems
    local function add_items_to_merged(list)
        for _, item in ipairs(list) do
            local itemName, quantity = item[1], item[2]

            if mergedItems[itemName] then
                mergedItems[itemName] = mergedItems[itemName] + quantity
            else
                mergedItems[itemName] = quantity
            end
        end
    end

    -- Add items from both lists to mergedItems
    add_items_to_merged(list1)
    add_items_to_merged(list2)

    -- Convert mergedItems to the desired format
    local result = {}
    for itemName, quantity in pairs(mergedItems) do
        table.insert(result, {itemName, quantity})
    end

    return result
end
-- Function to gather missing ingredients from the crafting scheme
local used_items = {}
function save_reserved(crafting_status)
    local data = {}
    local recipes = load_recipes()
    for _, process in ipairs(crafting_status) do
        if process.recipe then
            local rs
            if process.recipe.scheme then
                rs = extract_and_merge_items_scheme(process.recipe.scheme)
            elseif process.recipe.devices then
                rs = extract_and_merge_from_devices(process.recipe.devices)
            end
            log(pretty.pretty(rs))
            if rs then
                merge_two_lists(data,rs)
            end
        end
    end
    log(pretty.pretty(data))
    used_items = data
end
-- Function to get the count of a specific item by name
function get_count_by_name(itemList, itemName)
    for _, item in ipairs(itemList) do
        if item[1] == itemName then
            return item[2]
        end
    end
    return 0  -- Return 0 if item is not found
end

function get_missing_from_scheme(scheme)
    local mergedItems = {}

    -- Traverse the scheme and merge items directly into mergedItems
    for row = 1, #scheme do
        for col = 1, #scheme[row] do
            local item = scheme[row][col]
            if type(item) == "table" then
                local itemName = item[1]
                local requiredCount = item[2].count or 1  -- Default to 1 if count is not specified

                -- Merge items with the same name
                if mergedItems[itemName] then
                    mergedItems[itemName] = mergedItems[itemName] + requiredCount
                else
                    mergedItems[itemName] = requiredCount
                end
            end
        end
    end

    -- Filter for missing items
    local result = {}
    for itemName, quantity in pairs(mergedItems) do
        if not has_enough_item_or_tag(itemName, (quantity + get_count_by_name(used_items,itemName))) then
            table.insert(result, {itemName, (quantity + get_count_by_name(used_items,itemName))})
        end
    end

    return result
end


-- Function to craft an item based on the type of recipe (crafting, custom)
function craft(item)
    local recipes = load_recipes()
    
    -- Check all types of recipes (crafting, custom) for the item
    local recipe_found = false

    -- Check if the item is a crafting recipe
    for _, recipe in pairs(recipes.crafting) do
        if recipe.result == item then
            craft_crafting_recipe(recipe)
            recipe_found = true
            break  -- Exit loop after crafting
        end
    end
    
    if not recipe_found then
        -- Check if the item is a custom device recipe
        for _, recipe in pairs(recipes.custom) do
            if recipe.result == item then
                craft_custom_recipe(recipe)
                recipe_found = true
                break  -- Exit loop after crafting
            end
        end
    end

    -- If no recipe found, item cannot be crafted
    if not recipe_found then
        log("not enough "..item)
        log("in craft")
    end
end
-- Function to aggregate missing items
local function aggregate_missing_items(missing_items)
    local aggregated = {}
    for _, item in ipairs(missing_items) do
        local item_name = item[1]
        local required_count = item[2]
        
        if not aggregated[item_name] then
            aggregated[item_name] = required_count
        else
            aggregated[item_name] = aggregated[item_name] + required_count
        end
    end
    return aggregated
end
local function wait()
    while not check_done do
        os.sleep(0.001)
    end
end
-- Function to handle crafting recipes with precise sub-recipe crafting
function craft_crafting_recipe(recipe)
    parallel.waitForAny(wait, wait)
    inserting = true
    local scheme = recipe['scheme']
    local input_container = recipe['input_c']
    local output_container = recipe['output_c']
    local recipes = load_recipes()  -- Load available recipes

    -- Main logic to gather and craft missing items
    local missing_items = aggregate_missing_items(get_missing_from_scheme(scheme))

    -- Process each unique missing item
    for item_name, required_count in pairs(missing_items) do
        -- Look for a recipe for the missing item in crafting or custom recipes
        local found_recipe = recipes.crafting[item_name] or recipes.custom[item_name]
        
        if found_recipe then
            -- Calculate the minimum crafting runs needed based on recipe count
            local output_count = found_recipe.count
            local craft_count = math.ceil(required_count / output_count)
            
            log("craft count: " .. tostring(craft_count))
            
            -- Craft just enough to meet the requirement
            local crafted = false
            for i = 1, craft_count do
                if recipes.crafting[item_name] then
                    crafted = craft_crafting_recipe(recipes.crafting[item_name])
                    log("crafting log")
                elseif recipes.custom[item_name] then
                    crafted = craft_custom_recipe(recipes.custom[item_name])
                    log("crafting log")
                end

                -- Stop if sub-crafting fails
                if not crafted then
                    not_enough({ { item_name, required_count } })
                    inserting = false
                    return false
                end
            end
        else
            -- No recipe for missing item, so crafting cannot continue
            not_enough({ { item_name, required_count } })
            inserting = false
            return false
        end
    end

    -- Crafting device crafting process would be triggered here
    local crafting_status = load_crafting_status()
    table.insert(crafting_status, {
        recipe = recipe,
        type = "crafting",
        status = "busy",
        amount = tostring(get_amount(recipe.result)),
    })
    log("adding craft to list "..recipe.result)
    log(pretty.pretty(crafting_status))
    save_crafting_status(crafting_status)
    inserting = false
    return true  -- Successfully started crafting
end
-- Function to handle custom device recipes with precise sub-recipe crafting
function craft_custom_recipe(recipe)
    parallel.waitForAny(wait, wait)
    inserting = true

    local recipes = load_recipes()  -- Load available recipes

    -- Check for missing materials and attempt to craft them if necessary
    for device, inputs in pairs(recipe.devices) do
        for slot, input in pairs(inputs) do
            local item = input[1]
            if item ~= "output" then
                local count = input[2].count
                local old = item
                if item.tags then
                    item = item.tags
                end

                -- Check if the item is available, and handle sub-recipes if it’s missing
                if not has_enough_item_or_tag(old, count) then
                    local found_recipe = recipes.crafting[old] or recipes.custom[old]

                    if found_recipe then
                        -- Calculate minimum crafting runs needed based on recipe count
                        local output_count = found_recipe.count
                        local craft_count = math.ceil(count / output_count)

                        -- Craft just enough to meet the requirement
                        local crafted = false
                        for i = 1, craft_count do
                            if recipes.crafting[old] then
                                crafted = craft_crafting_recipe(recipes.crafting[old])
                            elseif recipes.custom[old] then
                                crafted = craft_custom_recipe(recipes.custom[old])
                            end

                            -- Stop if sub-crafting fails
                            if not crafted then
                                not_enough({{old, count}})
                                inserting = false
                                return false
                            end
                        end
                    else
                        -- No recipe for missing item, so crafting cannot continue
                        not_enough({{old, count}})
                        inserting = false
                        return false
                    end
                end
            end
        end
    end

    -- Custom device crafting process would be triggered here
    local crafting_status = load_crafting_status()
    table.insert(crafting_status, {
        recipe = recipe,
        type = "custom",
        status = "busy",
        amount = tostring(get_amount(recipe.result)),
    })
    save_crafting_status(crafting_status)
    inserting = false
    return true  -- Successfully started crafting
end
function updateCountKeys(t, x) 
    for k, v in pairs(t) do 
        if type(v) == "table" then 
            updateCountKeys(v, x) 
        elseif k == "count" then 
            t[k] = t[k] * x 
        end 
    end
end

function check_crafting_status()
    log('reload')
    check_done = false
    local crafting_status = load_crafting_status()
    save_reserved(crafting_status)
    while reserving do
        os.sleep(0.0001)
    end
    local updated_status = {}

    -- Find the highest existing process_id in crafting_status
    local max_id = 0
    for _, process in ipairs(crafting_status) do
        max_id = math.max(max_id, process.process_id or 0)
    end

    -- Assign unique IDs to each process that lacks one
    for _, process in ipairs(crafting_status) do
        if not process.process_id then
            max_id = max_id + 1
            process.process_id = max_id
        end
    end

    -- First pass: mark processes and set flags
    for _, process in ipairs(crafting_status) do
        if process.status == 'in_progress' and not process.processed then
            local recipe = process.recipe
            if recipe then
                log("Processing 'in_progress' recipe: " .. pretty.pretty(recipe.result))
                process.processed = true
                local input_c, devices = recipe.input_c, recipe.devices
                for _, proc in ipairs(crafting_status) do
                    if proc.recipe and not proc.processed and proc.process_id ~= process.process_id then
                        local proc_recipe = proc.recipe
                        if input_c and proc_recipe.input_c == input_c and proc.status ~= 'in_progress' then
                            log("Marking as 'busy' due to shared input container: " .. input_c)
                            proc.status, proc.processed = "busy", true
                        elseif devices then
                            for dev in pairs(devices) do
                                if proc_recipe.devices and proc_recipe.devices[dev] then
                                    log("Marking as 'busy' due to shared device: " .. dev)
                                    proc.status, proc.processed = "busy", true
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    -- Update 'busy' processes with their item amounts
    for _, process in ipairs(crafting_status) do
        if process.status == 'busy' then
            local recipe = process.recipe
            if recipe then
                process.amount = tostring(get_amount(recipe.result))
            end
        end
    end

    -- Second pass: handle 'busy' recipes and dependencies
    local prog_set = false
    for _, process in ipairs(crafting_status) do
        if process.status == 'busy' and not process.processed then
            local recipe = process.recipe
            if recipe then
                log("Processing 'busy' recipe: " .. pretty.pretty(recipe.result))
                if (function()
                    if not recipe.multi_craft then
                        if recipe.scheme then
                            for _, proc in ipairs(crafting_status) do
                                if proc.recipe.scheme and proc.status == 'in_progress' and proc.recipe.input_c == recipe.input_c and proc.process_id ~= process.process_id then
                                    log("Found conflicting 'in_progress' with same input container: " .. recipe.input_c)
                                    return false
                                end
                            end
                            for _, row in ipairs(recipe.scheme) do
                                for _, item in ipairs(row) do
                                    if item[1] ~= "" then
                                        for _, pro in ipairs(crafting_status) do
                                            if pro.recipe.result == item[1] then
                                                log("Dependency found, cannot proceed: " .. item[1])
                                                return false
                                            end
                                        end
                                    end
                                end
                            end
                        else
                            if count_active_crafts_for_input(recipe.input_c) >= 1 or count_active_custom_crafts_for_devices(recipe.devices) >= 1 then
                                return false
                            end
                        end
                        return true
                    else
                        if process.recipe.amount == 0 then return false end
                        local multi_c = recipe.multi_limit or 1
                        if recipe.scheme then
                            local crafts = {}
                            for _, proc in ipairs(crafting_status) do
                                if proc.recipe.scheme and proc.status == 'in_progress' and proc.recipe.input_c == recipe.input_c and proc.process_id ~= process.process_id then
                                    table.insert(crafts, proc)
                                end
                            end
                            if (#crafts+1) >= multi_c then
                                return false
                            end
                            
                            for _, row in ipairs(recipe.scheme) do
                                for _, item in ipairs(row) do
                                    if item[1] ~= "" then
                                        for _, pro in ipairs(crafting_status) do
                                            log("item")
                                            log(item[1])
                                            if pro.recipe.result == item[1] then
                                                log("Dependency found, cannot proceed: " .. item[1])
                                                return false
                                            end
                                        end
                                    end
                                end
                            end
                            if process.recipe.amount then
                                if count_active_crafts_for_input(recipe.input_c) > 1 then
                                    return false
                                end
                                for _, proc in ipairs(crafting_status) do
                                    if process.status == 'in_progress' or proc.status == 'in_progress' then
                                        if process.process_id ~= proc.process_id then
                                            if proc.result == recipe.result then
                                                return false
                                            end
                                            if proc.input_c == process.input_c then
                                                return false
                                            end
                                        end
                                    end
                                end
                            end
                        elseif recipe.devices then
                            if count_active_custom_crafts_for_devices(recipe.devices) >= multi_c then
                                return false
                            end
                            if process.recipe.amount then
                                if count_active_crafts_for_input(recipe.input_c) > 1 then
                                    return false
                                end
                                for _, proc in ipairs(crafting_status) do
                                    if process.status == 'in_progress' or proc.status == 'in_progress' then
                                        if process.process_id ~= proc.process_id then
                                            if proc.result == recipe.result then
                                                return false
                                            end
                                            if proc.input_c == process.input_c then
                                                return false
                                            end
                                        end
                                    end
                                end
                            end
                        end
                        if (process.recipe.amount == 1 or process.recipe.amount == nil) then
                            local numeric_merge = 1
                            for _, proc in ipairs(crafting_status) do
                                if  table.concat(proc.recipe) == table.concat(process.recipe) and process.process_id ~= proc.process_id and numeric_merge <= multi_c and (proc.recipe.amount == 1 or proc.recipe.amount == nil) then
                                    numeric_merge = numeric_merge + 1
                                    proc.recipe.amount = 0
                                end
                            end
                            process.recipe.amount = numeric_merge
                            updateCountKeys(process.recipe, numeric_merge) 
                        end
                        return true
                    end
                end)() then
                    if not prog_set then
                        prog_set = true
                        process.status = 'in_progress'
                        log("Starting crafting process for: " .. pretty.pretty(recipe.result))
                        if do_craft(recipe) == '' then
                            log("Crafting Error : " .. recipe.result)
                            process.status = ''
                        end
                        process.processed = true
                    end
                end
            end
        end
    end

    -- Process output containers and update statuses
    for _, process in ipairs(crafting_status) do
        local recipe = process.recipe
        if recipe and recipe.devices then
            for dev, slots in pairs(recipe.devices) do
                for slot, data in pairs(slots) do
                    if data[1] == "output" then
                        items:insert(dev, tonumber(slot), 64)
                    end
                end
            end
        elseif recipe and recipe.output_c then
            for slot, _ in pairs(peripheral.call(recipe.output_c, "list") or {}) do
                items:insert(recipe.output_c, tonumber(slot), 64)
            end
        end
    end

    -- Final pass: mark completed processes and retry busy or in-progress items
    for _, process in ipairs(crafting_status) do
        local recipe = process.recipe
        if recipe then
            if have_enough_simp(recipe.result, recipe.count + tonumber(process.amount or 0)) and process.status == 'in_progress' then
                process.status = "completed"
                log("crafting for item " .. recipe.result .. " done")
            elseif process.status == "busy" or process.status == "in_progress" then
                if process.recipe.amount ~= 0 then
                    table.insert(updated_status, process)
                end
            end
        end
    end

    -- Save and reset
    save_crafting_status(updated_status)
    for _, process in ipairs(crafting_status) do
        process.processed = nil
    end
    check_done = true
end
function try_multi_craft(recipe,coun)
    local recipes = load_recipes() 
    local recipe_found = recipes.crafting[recipe] or recipes.custom[recipe]
    if not recipe_found then not_enough(recipe,count) inserting = false return end
    count = coun
    if not recipe_found.multi_craft or recipe_found.multi_limit == 1 then
        if recipes.crafting[recipe] then
            for i = 1, count do
                craft_crafting_recipe(recipe_found,1)
            end
        elseif recipes.custom[recipe] then
            for i = 1, count do
                craft_custom_recipe(recipe_found,1)
            end
        end
    elseif recipe_found.multi_craft and recipe_found.multi_limit > 1 and (tonumber(coun) <= tonumber(recipe_found.multi_limit)) then
        parallel.waitForAny(wait, wait)
        inserting = true
        updateCountKeys(recipe_found, coun)
        if recipes.crafting[recipe] then
            -- Main logic to gather and craft missing items
            local missing_items = aggregate_missing_items(get_missing_from_scheme(recipe_found.scheme))
            -- Process each unique missing item
            for item_name, required_count in pairs(missing_items) do
                -- Look for a recipe for the missing item in crafting or custom recipes
                local f_recipe = recipes.crafting[item_name] or recipes.custom[item_name]
                if f_recipe then
                    -- Calculate the minimum crafting runs needed based on recipe count
                    local output_count = f_recipe.count
                    local craft_count = math.ceil(required_count/output_count)
                    -- Craft just enough to meet the requirement
                    log(craft_count)
                    if try_multi_craft(item_name, craft_count) == false then
                        not_enough({ { item_name, required_count } })
                        inserting = false
                        return false
                    end
                else
                    -- No recipe for missing item, so crafting cannot continue
                    not_enough({ { item_name, required_count } })
                    inserting = false
                    return false
                end
            end
        else
            for device, inputs in pairs(recipe_found.devices) do
                for slot, input in pairs(inputs) do
                    local item = input[1]
                    if item ~= "output" then
                        local co = input[2].count or 1
                        local old = item
                        if item.tags then
                            item = item.tags
                        end
        
                        -- Check if the item is available, and handle sub-recipes if it’s missing
                        if not has_enough_item_or_tag(old, count) then
                            local f_recipe = recipes.crafting[old] or recipes.custom[old]
        
                            if f_recipe then
                                -- Calculate minimum crafting runs needed based on recipe count
                                local output_count = f_recipe.count
                                local craft_count = math.ceil(co/output_count)
        
                                -- Craft just enough to meet the requirement
                                if try_multi_craft(old, craft_count) == false then
                                    not_enough({ { old, required_count } })
                                    inserting = false
                                    return false
                                end
                            else
                                -- No recipe for missing item, so crafting cannot continue
                                not_enough({{old, count}})
                                inserting = false
                                return false
                            end
                        end
                    end
                end
            end
        end
        local crafting_status = load_crafting_status()
        local process
        if recipes.crafting[recipe] then
            process = {
                recipe = recipe_found,
                type = "crafting",
                status = "busy",
                amount = tostring(get_amount(recipe_found.result)),
            }
        else
            process = {
                recipe = recipe_found,
                type = "custom",
                status = "busy",
                amount = tostring(get_amount(recipe_found.result)),
            }
        end
        process.recipe.amount = coun
        table.insert(crafting_status, process)
        save_crafting_status(crafting_status)
        inserting = false
    elseif tonumber(coun) > tonumber(recipe_found.multi_limit) then
        print(coun)
        try_multi_craft(recipe,recipe_found.multi_limit)
        try_multi_craft(recipe,coun-recipe_found.multi_limit)
        inserting = false
    end
    inserting = false
end



function log(text)
    --local file = io.open("log.txt", "a")  -- Open in append mode
    --file:write(tostring(text) .. "\n")    -- Add a newline after each log entry
    --file:close()
end

return function(context)
    items = context:require "artist.core.items"

    -- have_enough function
    function have_enough(item_name, count)
        os.sleep(0.01)
        local total_count = 0 + get_count_by_name(used_items,item_name)

        for _, inventory in pairs(items.inventories) do
            for _, slot in pairs(inventory.slots or {}) do
                local item = items.item_cache[slot.hash]
                if item and item.details and item.details.name and item.details.name == item_name then
                    total_count = total_count + slot.count
                end
            end
        end

        return tonumber(total_count) >= tonumber(count)
    end

    -- have_enough function
    function have_enough_simp(item_name, count)
        os.sleep(0.01)
        local total_count = 0

        for _, inventory in pairs(items.inventories) do
            for _, slot in pairs(inventory.slots or {}) do
                local item = items.item_cache[slot.hash]
                if item and item.details and item.details.name and item.details.name == item_name then
                    total_count = total_count + slot.count
                end
            end
        end

        return total_count >= count
    end

    function get_amount(item_name)
        local total_count = 0

        for _, inventory in pairs(items.inventories) do
            for _, slot in pairs(inventory.slots or {}) do
                local item = items.item_cache[slot.hash]
                if item and item.details and item.details.name and item.details.name == item_name then
                    total_count = total_count + slot.count
                end
            end
        end

        return total_count
    end

    -- do_craft function
    function do_craft(recipe)
        if recipe.scheme then
            local num = 0
            for _, row in ipairs(recipe.scheme) do
                for _, item in ipairs(row) do
                    num = num + 1
                    if item ~= "" then
                        local c, use
                        if type(item) == "table" then
                            c = item[2].count or 1
                            if type(item[1]) == "table" then
                                for _, name in ipairs(item[1].tags) do
                                    if have_enough(name, c) then
                                        use = name
                                        break
                                    end
                                end
                            else
                                use = item[1]
                            end
                        else
                            use = item
                            c = 1
                        end
                    
                        if use and have_enough(use, c) then
                            local cache = nil
                            for _, val in pairs(items.item_cache) do
                                if val.hash == use then
                                    cache = val
                                    break
                                end
                            end
                        
                            if cache then
                                local status, result = pcall(function()
                                    items:extract(recipe.input_c, cache.hash, c, num)
                                end)
                                log("!!!status")
                                log(status)
                                if not status then return '' end
                            end
                        end
                    end
                end
            end
        elseif recipe.devices then
            for device, ins in pairs(recipe.devices) do
                for slot, item in pairs(ins) do
                    if item[1] ~= "output" then
                        local use, c
                        if item[1].tags then
                            c = item[2].count or 1
                            for _, name in ipairs(item[1].tags) do
                                if have_enough(name, c) then
                                    use = name
                                    break
                                end
                            end
                        else
                            use = item[1]
                            c = item[2].count or 1
                        end
                    
                        if use and have_enough(use, c) then
                            local cache = nil
                            for _, val in pairs(items.item_cache) do
                                if val.hash == use then
                                    cache = val
                                    break
                                end
                            end
                        
                            if cache then
                                items:extract(device, cache.hash, c, tonumber(slot))
                            end
                        end
                    end
                end
            end
        end
        return "in_progress"
    end
    
    --save_crafting_status({})
    local next_reload = nil
    local function queue_reload()
        if next_reload then return end
        next_reload = os.startTimer(0.2)
    end
    local function update_dropoff_pl(item)
        local crafting_status = load_crafting_status()
        for _, process in ipairs(crafting_status) do
            if process.recipe.result == item.name then
                process.amount = process.amount + item.count
            end
        end
        save_crafting_status(crafting_status)
    end
    local function update_dropoff_mn(item)
        local crafting_status = load_crafting_status()
        for _, process in ipairs(crafting_status) do
            if process.recipe.result == item.name then
                process.amount = process.amount - item.count
            end
        end
        save_crafting_status(crafting_status)
    end
    function not_enough(missing_items)
        log("not enough "..pretty.pretty(missing_items))
        context.mediator:publish("crafting.missing", missing_item)
    end
    function get_crafts()
        local crafts = {}
        local resc = load_recipes()
        for craft,_ in pairs(resc["crafting"]) do
            table.insert(crafts,craft)
        end
        for craft,_ in pairs(resc["custom"]) do
            table.insert(crafts,craft)
        end
        return crafts
    end
    context.mediator:subscribe("dropoff.add", update_dropoff_pl)
    context.mediator:subscribe("pickup.take", update_dropoff_mn)
    Crafting.get_crafts = get_crafts
    Crafting.try_multi_craft = try_multi_craft
    context:spawn(function()
        while true do
            os.sleep(0.001)
            if check_done then
                if not inserting then
                    check_crafting_status()
                end
            end
        end
    end)
    return Crafting
end


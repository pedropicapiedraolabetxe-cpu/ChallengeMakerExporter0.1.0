-- Challenge Maker conditions. No item grants, global stat edits or recursive rules.
local M = {}
M.Rewards = include("cm_rewards")
M.Options = {"hp_down", "hp_up", "speed_down", "speed_up", "tears_down", "tears_up",
    "damage_down", "damage_up", "range_down", "range_up", "shot_speed_down", "shot_speed_up", "luck_down", "luck_up"}
-- Event-only triggers belong on the IF/MUST side, never on the THEN side.
-- REPLACE WITH remains stat-only because there is no native Death's List reward
-- that can be safely rolled back after the room-clear callback has fired.
M.TriggerOptions = {}
for _, key in ipairs(M.Options) do M.TriggerOptions[#M.TriggerOptions+1] = key end
M.TriggerOptions[#M.TriggerOptions+1] = "death_list_complete"
M.TriggerOptions[#M.TriggerOptions+1] = "boss_defeated"
M.TriggerOptions[#M.TriggerOptions+1] = "item_used"
M.TriggerOptions[#M.TriggerOptions+1] = "pickup_collected"
M.TriggerOptions[#M.TriggerOptions+1] = "pickup_count"
M.TriggerOptions[#M.TriggerOptions+1] = "enemy_killed"
M.TriggerOptions[#M.TriggerOptions+1] = "room_entered_x"
M.TriggerOptions[#M.TriggerOptions+1] = "room_cleared_x"
M.TriggerOptions[#M.TriggerOptions+1] = "floor_cleared_time"
M.TriggerOptions[#M.TriggerOptions+1] = "no_damage_room"
M.TriggerOptions[#M.TriggerOptions+1] = "no_damage_floor"
for _,key in ipairs({"health_threshold","stat_threshold","has_property","active_fully_charged","pickup_spawned","deal_entered","secret_room_found","donation_made","machine_used","character_changed"}) do M.TriggerOptions[#M.TriggerOptions+1]=key end
for _,key in ipairs({"teleport_to_room_event","spawn_enemy_event","remove_item_event","reroll_item_event","dupe_item_event"}) do M.TriggerOptions[#M.TriggerOptions+1]=key end
M.TriggerOptions[#M.TriggerOptions+1]="void_absorb"
M.TriggerOptions[#M.TriggerOptions+1]="abbys_absorb"
M.TriggerOptions[#M.TriggerOptions+1] = "grab_item"
M.TriggerOptions[#M.TriggerOptions+1] = "room_clear"
M.TriggerOptions[#M.TriggerOptions+1] = "change_floor"
M.TriggerOptions[#M.TriggerOptions+1] = "change_stage"
M.TriggerOptions[#M.TriggerOptions+1] = "room_enter"
M.TriggerOptions[#M.TriggerOptions+1] = "uncleared_room_enter"
M.TriggerOptions[#M.TriggerOptions+1] = "taking_damage"
M.TriggerOptions[#M.TriggerOptions+1] = "key_pressed"
M.ReplaceTriggerOptions = M.Options
M.ActionOptions = {"hp_down", "hp_up", "speed_down", "speed_up",
    "fire_rate_down", "fire_rate_up", "tears_down", "tears_up",
    "damage_down", "damage_up", "range_down", "range_up",
    "shot_speed_down", "shot_speed_up", "luck_down", "luck_up"}
local valid = {}
for _, key in ipairs(M.Options) do valid[key] = true end
local actionValid = {}
for _, key in ipairs(M.ActionOptions) do actionValid[key] = true end
local defaultAmounts = {hp=1, speed=0.1, fire_rate=0.5, tears=0.5, damage=0.5, range=1, shot_speed=0.1, luck=1}
local function actionStat(key) return type(key)=="string" and key:match("^(.*)_%a+$") or nil end
local function validAmount(r)
    if not actionValid[r.action] or r.amount == nil then return true end
    local n = tonumber(r.amount)
    return n ~= nil and n == n and n > 0 and n < math.huge
end
function M.DefaultAmount(key) return defaultAmounts[actionStat(key)] or 1 end
function M.FormatAmount(value)
    local n = tonumber(value)
    if not n then return "" end
    if n == math.floor(n) then return tostring(math.floor(n)) end
    return (string.format("%.4f", n):gsub("0+$", ""):gsub("%.$", ""))
end
local function isItemAction(action) return action=="give_item" or action=="spawn_item" end
local function isRewardAction(action) return isItemAction(action) or action=="give_trinket" end
local specialActions={remove_item=true,reroll_item=true,dupe_item=true,spawn_trinket=true,give_pickup=true,spawn_pickup=true,heal=true,damage=true,add_heart_container=true,remove_heart_container=true,teleport_room=true,open_doors=true,close_doors=true,spawn_enemy=true,spawn_boss=true,apply_status=true,charge_item=true,
    change_character=true,use_active_effect=true,play_sound=true,show_message=true,start_timer=true,stop_timer=true,end_challenge=true,win_challenge=true,lose_challenge=true,repeat_floor=true,go_to_stage=true}
local function validSpecialAction(r)
    local c=r.effectConfig
    if r.action=="remove_item" then return M.Rewards.Valid(r.gift) and r.gift.kind=="fixed" end
    if r.action=="spawn_trinket" then return M.Rewards.ValidTrinket(r.gift) end
    if ({reroll_item=true,dupe_item=true,open_doors=true,close_doors=true,start_timer=true,stop_timer=true,end_challenge=true,win_challenge=true,lose_challenge=true,repeat_floor=true})[r.action] then return true end
    if r.action=="charge_item" then return type(c)=="table" and tonumber(c.amount) and tonumber(c.amount)>0 and tonumber(c.amount)==math.floor(tonumber(c.amount)) end
    if r.action=="heal" or r.action=="damage" or r.action=="add_heart_container" or r.action=="remove_heart_container" then return type(c)=="table" and tonumber(c.amount) and tonumber(c.amount)>0 end
    if r.action=="give_pickup" or r.action=="spawn_pickup" then return type(c)=="table" and ({coin=true,bomb=true,key=true,heart=true,card=true,pill=true,battery=true})[c.kind]==true and tonumber(c.amount) and tonumber(c.amount)>0 end
    if r.action=="teleport_room" then return type(c)=="table" and tonumber(c.roomType)~=nil end
    if r.action=="spawn_enemy" or r.action=="spawn_boss" then return type(c)=="table" and tonumber(c.type)~=nil end
    if r.action=="apply_status" then return type(c)=="table" and ({fear=true,confusion=true,poison=true,slow=true})[c.status]==true end
    if r.action=="change_character" then return type(c)=="table" and (tonumber(c.playerType)~=nil or tostring(c.token or "")~="") end
    if r.action=="use_active_effect" then return M.Rewards.Valid(r.gift) and r.gift.kind=="fixed" end
    if r.action=="play_sound" then return type(c)=="table" and tonumber(c.id)~=nil end
    if r.action=="show_message" then return type(c)=="table" and tostring(c.text or "")~="" end
    if r.action=="go_to_stage" then return type(c)=="table" and tonumber(c.stage)~=nil end
    return false
end
local triggerValid = {}
for _, key in ipairs(M.TriggerOptions) do triggerValid[key] = true end
-- Previously saved CLEARING ROOM rules stay playable, though the editor no longer offers new ones.
triggerValid.clearing_room = true
triggerValid.run_start=true
function M.Name(key)
    if key=="run_start" then return "RUN START" end
    local actionNames={remove_item="REMOVE ITEM",reroll_item="REROLL ITEM",dupe_item="DUPE ITEM",spawn_trinket="SPAWN TRINKET",give_pickup="GIVE PICKUP",spawn_pickup="SPAWN PICKUP",heal="HEAL",damage="DAMAGE",add_heart_container="ADD HEART CONTAINER",remove_heart_container="REMOVE HEART CONTAINER",teleport_room="TELEPORT TO ROOM",open_doors="OPEN DOORS",close_doors="CLOSE DOORS",spawn_enemy="SPAWN ENEMY",spawn_boss="SPAWN BOSS",apply_status="APPLY STATUS",charge_item="CHARGE ITEM",change_character="CHANGE CHARACTER",use_active_effect="USE ACTIVE ITEM EFFECT",play_sound="PLAY SOUND",show_message="SHOW MESSAGE",start_timer="START TIMER",stop_timer="STOP TIMER",end_challenge="END CHALLENGE",win_challenge="WIN CHALLENGE",lose_challenge="LOSE CHALLENGE",repeat_floor="REPEAT FLOOR",go_to_stage="GO TO FLOOR / STAGE"}
    if actionNames[key] then return actionNames[key] end
    if key == "finish" then return "FINISH THE CHALLENGE" end
    if key == "death_list_complete" then return "COMPLETE A DEATH'S LIST" end
    if key == "boss_defeated" then return "BOSS DEFEATED" end
    if key == "item_used" then return "ITEM USED" end
    if key == "pickup_collected" then return "PICKUP COLLECTED" end
    if key == "pickup_count" then return "PICKUP COUNT" end
    if key == "enemy_killed" then return "ENEMY KILLED" end
    if key == "room_entered_x" then return "ROOM ENTERED X TIMES" end
    if key == "room_cleared_x" then return "ROOM CLEARED X TIMES" end
    if key == "floor_cleared_time" then return "FLOOR CLEARED IN X TIME" end
    if key == "no_damage_room" then return "NO DAMAGE ROOM" end
    if key == "no_damage_floor" then return "NO DAMAGE FLOOR" end
    local extraNames={health_threshold="HEALTH BELOW / ABOVE",stat_threshold="STAT BELOW / ABOVE",has_property="HAS ITEM / TRINKET / TRANSFORMATION",active_fully_charged="ACTIVE ITEM FULLY CHARGED",pickup_spawned="PICKUP SPAWNED",deal_entered="DEAL ENTERED",secret_room_found="SECRET ROOM FOUND",donation_made="DONATION MADE",machine_used="MACHINE USED",character_changed="CHARACTER CHANGED",teleport_to_room_event="TELEPORT TO ROOM",spawn_enemy_event="SPAWN ENEMY",remove_item_event="REMOVE ITEM",reroll_item_event="REROLL ITEM",dupe_item_event="DUPE ITEM",void_absorb="VOID",abbys_absorb="ABBYS"}
    if extraNames[key] then return extraNames[key] end
    if key == "grab_item" then return "GRAB ITEM" end
    if key == "room_clear" then return "ROOM CLEAR" end
    if key == "change_floor" then return "CHANGE FLOOR" end
    if key == "change_stage" then return "CHANGE STAGE" end
    if key == "room_enter" then return "ROOM ENTER" end
    if key == "uncleared_room_enter" then return "UNCLEARED ROOM ENTER" end
    if key == "taking_damage" then return "TAKING DAMAGE" end
    if key == "clearing_room" then return "CLEARING ROOM" end
    if key == "key_pressed" then return "KEY PRESSED" end
    return string.upper((tostring(key):gsub("_", " ")))
end
local function validGrab(g)
    if type(g) ~= "table" then return false end
    if g.kind == "any" then return true end
    if g.kind == "fixed" then return type(g.token) == "string" and g.token ~= "" end
    if g.kind == "pool" then return type(g.pool) == "table" and (tonumber(g.pool.id) ~= nil or tostring(g.pool.name or "") ~= "") end
    return false
end
local function grabLabel(g)
    if type(g) ~= "table" or g.kind == "any" then return "ANY ITEM" end
    if g.kind == "fixed" then return tostring(g.name or g.token or "ITEM") end
    if g.kind == "pool" then return tostring((g.pool and (g.pool.label or g.pool.name)) or "POOL") end
    return "ITEM"
end
local function isRoomTrigger(trigger)
    return trigger == "room_enter" or trigger == "uncleared_room_enter" or trigger == "clearing_room"
end
local function validRoomFilter(filter)
    if type(filter) ~= "table" then return false end
    if filter.any == true then return true end
    if type(filter.types) ~= "table" then return false end
    for _, roomType in ipairs(filter.types) do
        if tonumber(roomType) then return true end
    end
    return false
end
local function roomFilterLabel(filter)
    if type(filter) ~= "table" or filter.any == true then return "ANY" end
    if type(filter.label) == "string" and filter.label ~= "" then return filter.label end
    local names = {}
    for _, roomType in ipairs(filter.types or {}) do names[#names+1] = "ROOM " .. tostring(roomType) end
    return #names > 0 and table.concat(names, ", ") or "ANY"
end
local function validBossFilter(filter)
    if type(filter)~="table" then return false end
    if filter.any==true then return true end
    if type(filter.stages)~="table" then return false end
    for _,sf in pairs(filter.stages) do
        if type(sf)=="table" then
            if sf.any==true then return true end
            if type(sf.bosses)=="table" then for _,on in pairs(sf.bosses) do if on==true then return true end end end
        end
    end
    return false
end
local function bossFilterLabel(filter)
    if type(filter)~="table" or filter.any==true then return "ANY" end
    local stages=0; local bosses=0
    for _,sf in pairs(filter.stages or {}) do
        if type(sf)=="table" then
            stages=stages+1
            if sf.any==true then bosses=bosses+1 else for _,on in pairs(sf.bosses or {}) do if on==true then bosses=bosses+1 end end end
        end
    end
    return tostring(stages).." STAGE"..(stages==1 and "" or "S")..", "..tostring(bosses).." SELECTION"..(bosses==1 and "" or "S")
end
local function validItemUse(filter)
    if type(filter)~="table" then return false end
    if filter.kind=="any" then return true end
    return filter.kind=="fixed" and type(filter.token)=="string" and filter.token~=""
end
local function itemUseLabel(filter)
    if type(filter)~="table" or filter.kind=="any" then return "ANY ACTIVE ITEM" end
    return tostring(filter.name or filter.token or "ACTIVE ITEM")
end
local pickupNames={any="ANY PICKUP",coin="COIN",bomb="BOMB",key="KEY",heart="HEART",card="CARD / RUNE",pill="PILL",trinket="TRINKET",battery="BATTERY",sack="SACK",chest="CHEST",collectible="COLLECTIBLE"}
local function validPickupFilter(filter) return type(filter)=="table" and pickupNames[tostring(filter.kind or "")]~=nil end
local function pickupFilterLabel(filter) return pickupNames[type(filter)=="table" and tostring(filter.kind or "") or "any"] or "ANY PICKUP" end
local countNames={coins="COINS",bombs="BOMBS",keys="KEYS",red_hearts="RED HEARTS",soul_hearts="SOUL HEARTS",black_hearts="BLACK HEARTS",bone_hearts="BONE HEARTS",rotten_hearts="ROTTEN HEARTS"}
local function validPickupCount(filter) return type(filter)=="table" and countNames[tostring(filter.kind or "")]~=nil and tonumber(filter.amount) and tonumber(filter.amount)>=0 end
local function pickupCountLabel(filter)
    if not validPickupCount(filter) then return "PICKUPS" end
    return countNames[tostring(filter.kind)].." >= "..tostring(math.floor(tonumber(filter.amount) or 0))
end
local function validEnemyFilter(filter)
    if type(filter)~="table" then return false end
    if filter.kind=="any" or filter.kind=="boss" or filter.kind=="champion" then return true end
    return filter.kind=="fixed" and tonumber(filter.type)~=nil
end
local function enemyFilterLabel(filter)
    if type(filter)~="table" or filter.kind=="any" then return "ANY ENEMY" end
    if filter.kind=="boss" then return "ANY BOSS" end
    if filter.kind=="champion" then return "ANY CHAMPION" end
    return tostring(filter.name or ("ENTITY "..tostring(filter.type or "?")))
end
local function validTriggerNumber(param)
    return type(param)=="table" and tonumber(param.amount)~=nil and tonumber(param.amount)>0
end
local function triggerNumberLabel(trigger,param)
    local n=tonumber(type(param)=="table" and param.amount or nil) or 0
    if trigger=="floor_cleared_time" then return tostring(n).." SECONDS" end
    return tostring(math.floor(n)).." TIMES"
end
local function validKeyBinding(binding)
    return type(binding) == "table" and tonumber(binding.code) ~= nil and
        type(binding.name) == "string" and binding.name ~= ""
end
local function validExtra(r)
    local x=r.extra
    if r.trigger=="health_threshold" then return type(x)=="table" and (x.direction=="above" or x.direction=="below") and tonumber(x.amount)~=nil end
    if r.trigger=="stat_threshold" then return type(x)=="table" and ({speed=true,tears=true,damage=true,range=true,shot_speed=true,luck=true})[x.stat]==true and (x.direction=="above" or x.direction=="below") and tonumber(x.amount)~=nil end
    if r.trigger=="has_property" then return type(x)=="table" and ((x.kind=="item" or x.kind=="trinket") and tostring(x.token or "")~="" or x.kind=="transformation" and tostring(x.key or "")~="") end
    if r.trigger=="pickup_spawned" then return validPickupFilter(x) end
    if r.trigger=="deal_entered" then return type(x)=="table" and (x.kind=="any" or x.kind=="devil" or x.kind=="angel") end
    if r.trigger=="teleport_to_room_event" then return type(r.eventConfig)=="table" and tonumber(r.eventConfig.roomType)~=nil end
    if r.trigger=="spawn_enemy_event" then return type(r.eventConfig)=="table" and tonumber(r.eventConfig.type)~=nil end
    if r.trigger=="remove_item_event" or r.trigger=="dupe_item_event" then return true end
    if r.trigger=="void_absorb" or r.trigger=="abbys_absorb" then
        local f=r.voidFilter;if type(f)~="table" or not ({any=true,active=true,passive=true})[f.category] or type(f.all)~="boolean" or type(f.choices)~="table" then return false end
        if f.all then return true end
        for _,enabled in pairs(f.choices) do if enabled==true then return true end end
        return false
    end
    return true
end
local function extraLabel(r)
    local x=r.extra or {}
    if r.trigger=="health_threshold" then return string.upper(x.direction or "?").." "..M.FormatAmount(x.amount or 0).." HEARTS" end
    if r.trigger=="stat_threshold" then return string.upper(tostring(x.stat or "STAT"):gsub("_"," ")).." "..string.upper(x.direction or "?").." "..M.FormatAmount(x.amount or 0) end
    if r.trigger=="has_property" then return tostring(x.name or x.key or x.token or "PROPERTY") end
    if r.trigger=="pickup_spawned" then return pickupFilterLabel(x) end
    if r.trigger=="deal_entered" then return string.upper(x.kind or "ANY") end
    if r.trigger=="teleport_to_room_event" or r.trigger=="spawn_enemy_event" then return r.eventConfig and r.eventConfig.label end
    if r.trigger=="void_absorb" or r.trigger=="abbys_absorb" then local f=r.voidFilter or {};return string.upper(f.category or "ANY")..(f.all and ": ANY ITEM" or ": CUSTOM") end
    return nil
end
function M.Valid(r)
    if type(r) ~= "table" or not triggerValid[r.trigger] then return false end
    if r.trigger == "grab_item" and not validGrab(r.grab) then return false end
    if isRoomTrigger(r.trigger) and not validRoomFilter(r.roomFilter) then return false end
    if r.trigger == "key_pressed" and not validKeyBinding(r.keyBinding) then return false end
    if r.trigger == "boss_defeated" and not validBossFilter(r.bossFilter) then return false end
    if r.trigger == "item_used" and not validItemUse(r.itemUse) then return false end
    if r.trigger == "pickup_collected" and not validPickupFilter(r.pickupFilter) then return false end
    if r.trigger == "pickup_count" and not validPickupCount(r.pickupCount) then return false end
    if r.trigger == "enemy_killed" and not validEnemyFilter(r.enemyFilter) then return false end
    if (r.trigger=="room_entered_x" or r.trigger=="room_cleared_x" or r.trigger=="floor_cleared_time") and not validTriggerNumber(r.triggerParam) then return false end
    if not validExtra(r) then return false end
    if r.logic~=nil then
        if (r.logic~="and" and r.logic~="or") or type(r.secondary)~="table" then return false end
        local s=r.secondary
        if not triggerValid[s.trigger] or (s.trigger=="grab_item" and not validGrab(s.grab)) or (isRoomTrigger(s.trigger) and not validRoomFilter(s.roomFilter)) or
            (s.trigger=="key_pressed" and not validKeyBinding(s.keyBinding)) or (s.trigger=="boss_defeated" and not validBossFilter(s.bossFilter)) or
            (s.trigger=="item_used" and not validItemUse(s.itemUse)) or (s.trigger=="pickup_collected" and not validPickupFilter(s.pickupFilter)) or
            (s.trigger=="pickup_count" and not validPickupCount(s.pickupCount)) or (s.trigger=="enemy_killed" and not validEnemyFilter(s.enemyFilter)) or
            ((s.trigger=="room_entered_x" or s.trigger=="room_cleared_x" or s.trigger=="floor_cleared_time") and not validTriggerNumber(s.triggerParam)) or not validExtra(s) then return false end
    end
    if r.afterAmount~=nil and (tonumber(r.afterAmount)==nil or tonumber(r.afterAmount)<1 or tonumber(r.afterAmount)~=math.floor(tonumber(r.afterAmount))) then return false end
    if not validAmount(r) then return false end
    if r.mode == "replace" then
        return valid[r.trigger] and (actionValid[r.action] or (isItemAction(r.action) and M.Rewards.Valid(r.gift)) or
            (r.action=="give_trinket" and M.Rewards.ValidTrinket(r.gift)) or (specialActions[r.action] and validSpecialAction(r)))
    elseif r.mode == "if" then
        return actionValid[r.action] or (isItemAction(r.action) and M.Rewards.Valid(r.gift)) or
            (r.action=="give_trinket" and M.Rewards.ValidTrinket(r.gift)) or (specialActions[r.action] and validSpecialAction(r))
    elseif r.mode == "must" then
        return r.action == "finish"
    end
    return false
end
function M.Label(r)
    local triggerName = M.Name(r.trigger)
    if r.trigger == "grab_item" then triggerName = triggerName .. ": " .. grabLabel(r.grab) end
    if isRoomTrigger(r.trigger) then triggerName = triggerName .. ": " .. roomFilterLabel(r.roomFilter) end
    if r.trigger == "key_pressed" then triggerName = triggerName .. ": " .. tostring(r.keyBinding.name) end
    if r.trigger == "boss_defeated" then triggerName = triggerName .. ": " .. bossFilterLabel(r.bossFilter) end
    if r.trigger == "item_used" then triggerName = triggerName .. ": " .. itemUseLabel(r.itemUse) end
    if r.trigger == "pickup_collected" then triggerName = triggerName .. ": " .. pickupFilterLabel(r.pickupFilter) end
    if r.trigger == "pickup_count" then triggerName = triggerName .. ": " .. pickupCountLabel(r.pickupCount) end
    if r.trigger == "enemy_killed" then triggerName = triggerName .. ": " .. enemyFilterLabel(r.enemyFilter) end
    if r.trigger=="room_entered_x" or r.trigger=="room_cleared_x" or r.trigger=="floor_cleared_time" then triggerName=triggerName..": "..triggerNumberLabel(r.trigger,r.triggerParam) end
    local xl=extraLabel(r); if xl then triggerName=triggerName..": "..xl end
    local actionName = M.Name(r.action)
    if actionValid[r.action] then
        local shown=M.FormatAmount(r.amount or M.DefaultAmount(r.action))
        if r.action=="hp_down" and (r.hpLethal==true or r.hpNonlethal==true) and not shown:find("%.") then shown=shown..".0" end
        actionName = actionName .. " " .. shown
    end
    local repeatLabel=""
    if r.mode~="must" then
        if r.repeatMode=="one_time" then repeatLabel=" [ONE-TIME]"
        elseif r.repeatMode=="repeat" then repeatLabel=" [REPEAT]"
        elseif r.repeatMode=="once_room" then repeatLabel=" [ONCE PER ROOM]"
        elseif r.repeatMode=="once_floor" then repeatLabel=" [ONCE PER FLOOR]"
        elseif r.repeatMode=="custom" then repeatLabel=" [MAX "..tostring(math.max(1,math.floor(tonumber(r.repeatAmount) or 1))).."]" end
    end
    local modifiers=""
    if tonumber(r.cooldownSeconds) and tonumber(r.cooldownSeconds)>0 then modifiers=modifiers.." [CD "..M.FormatAmount(r.cooldownSeconds).."s]" end
    if tonumber(r.cooldownRooms) and tonumber(r.cooldownRooms)>0 then modifiers=modifiers.." [CD "..tostring(math.floor(r.cooldownRooms)).." ROOMS]" end
    if tonumber(r.chance) and tonumber(r.chance)<100 then modifiers=modifiers.." ["..M.FormatAmount(r.chance).."%]" end
    if tonumber(r.delaySeconds) and tonumber(r.delaySeconds)>0 then modifiers=modifiers.." [DELAY "..M.FormatAmount(r.delaySeconds).."s]" end
    if r.logic and r.secondary then triggerName=triggerName.." "..string.upper(r.logic).." "..M.Name(r.secondary.trigger) end
    if tonumber(r.afterAmount) and tonumber(r.afterAmount)>1 then triggerName="AFTER "..tostring(math.floor(tonumber(r.afterAmount))).."x "..triggerName end
    local result=(r.enabled==false and "[OFF] " or "") .. (r.mode == "must" and "MUST " or "IF ") .. triggerName ..
        (r.mode == "replace" and " REPLACE WITH " or (r.mode == "if" and " THEN " or " TO ")) ..
        (r.action=="give_item" and M.Rewards.Label(r.gift) or (r.action=="spawn_item" and (M.Rewards.Label(r.gift):gsub("^GIVE ITEM", "SPAWN ITEM")) or (r.action=="use_active_effect" and ("USE ACTIVE ITEM EFFECT: "..tostring(r.gift and (r.gift.name or r.gift.token) or "ITEM")) or
        ((r.action=="give_trinket" or r.action=="spawn_trinket") and ((r.action=="spawn_trinket" and "SPAWN TRINKET: " or "")..M.Rewards.TrinketLabel(r.gift):gsub("^GIVE TRINKET: ","")) or
        (specialActions[r.action] and (M.Name(r.action)..(r.effectConfig and r.effectConfig.label and (": "..r.effectConfig.label) or "")) or actionName))))) .. repeatLabel .. modifiers
    if r.trigger=="run_start" then result=result:gsub("^IF RUN START THEN ","RUN START: "):gsub(" %[ONE%-TIME%]$","") end
    return result
end
function M.Key(r)
    local triggerKey = r.trigger
    if r.trigger == "grab_item" and type(r.grab) == "table" then
        if r.grab.kind == "any" then triggerKey = triggerKey .. "_any"
        elseif r.grab.kind == "fixed" then triggerKey = triggerKey .. "_fixed_" .. tostring(r.grab.token)
        elseif r.grab.kind == "pool" then triggerKey = triggerKey .. "_pool_" .. tostring((r.grab.pool and (r.grab.pool.name or r.grab.pool.id)) or "") end
    end
    if isRoomTrigger(r.trigger) and type(r.roomFilter) == "table" then
        if r.roomFilter.any == true then triggerKey = triggerKey .. "_any"
        else
            local types = {}
            for _, roomType in ipairs(r.roomFilter.types or {}) do types[#types+1] = tonumber(roomType) or roomType end
            table.sort(types, function(a,b) return tonumber(a) < tonumber(b) end)
            triggerKey = triggerKey .. "_" .. table.concat(types, "-")
        end
    end
    if r.trigger == "key_pressed" and type(r.keyBinding) == "table" then
        triggerKey = triggerKey .. "_" .. tostring(r.keyBinding.code)
    end
    if r.trigger == "boss_defeated" and type(r.bossFilter)=="table" then
        if r.bossFilter.any==true then triggerKey=triggerKey.."_any" else
            local parts={}
            for sid,sf in pairs(r.bossFilter.stages or {}) do
                local piece=tostring(sid)..":"
                if sf.any==true then piece=piece.."any" else
                    local ids={}; for bid,on in pairs(sf.bosses or {}) do if on==true then ids[#ids+1]=tonumber(bid) or bid end end
                    table.sort(ids,function(a,b) return tonumber(a)<tonumber(b) end); piece=piece..table.concat(ids,"-")
                end
                parts[#parts+1]=piece
            end
            table.sort(parts); triggerKey=triggerKey.."_"..table.concat(parts,"_")
        end
    end
    if r.trigger=="item_used" and type(r.itemUse)=="table" then triggerKey=triggerKey.."_"..tostring(r.itemUse.kind).."_"..tostring(r.itemUse.token or "") end
    if r.trigger=="pickup_collected" and type(r.pickupFilter)=="table" then triggerKey=triggerKey.."_"..tostring(r.pickupFilter.kind) end
    if r.trigger=="pickup_count" and type(r.pickupCount)=="table" then triggerKey=triggerKey.."_"..tostring(r.pickupCount.kind).."_"..tostring(r.pickupCount.amount) end
    if r.trigger=="enemy_killed" and type(r.enemyFilter)=="table" then triggerKey=triggerKey.."_"..tostring(r.enemyFilter.kind).."_"..tostring(r.enemyFilter.type or "").."_"..tostring(r.enemyFilter.variant or "").."_"..tostring(r.enemyFilter.subtype or "") end
    if (r.trigger=="room_entered_x" or r.trigger=="room_cleared_x" or r.trigger=="floor_cleared_time") and type(r.triggerParam)=="table" then triggerKey=triggerKey.."_"..tostring(r.triggerParam.amount or "") end
    if type(r.extra)=="table" then triggerKey=triggerKey.."_"..tostring(r.extra.kind or r.extra.stat or r.extra.key or r.extra.token or "").."_"..tostring(r.extra.direction or "").."_"..tostring(r.extra.amount or "") end
    if type(r.eventConfig)=="table" then triggerKey=triggerKey.."_"..tostring(r.eventConfig.roomType or r.eventConfig.type or "").."_"..tostring(r.eventConfig.variant or "").."_"..tostring(r.eventConfig.subtype or "") end
    if type(r.voidFilter)=="table" then
        triggerKey=triggerKey.."_"..tostring(r.voidFilter.category).."_"..tostring(r.voidFilter.all)
        local choices={};for token,on in pairs(r.voidFilter.choices or {}) do choices[#choices+1]=tostring(token).."="..tostring(on==true) end;table.sort(choices);triggerKey=triggerKey.."_"..table.concat(choices,"-")
    end
    if r.logic and r.secondary then local s=r.secondary;triggerKey=triggerKey.."_"..r.logic.."_"..tostring(s.trigger).."_"..tostring(s.keyBinding and s.keyBinding.code or "").."_"..tostring(s.triggerParam and s.triggerParam.amount or "").."_"..tostring(s.itemUse and s.itemUse.token or "").."_"..tostring(s.pickupFilter and s.pickupFilter.kind or "").."_"..tostring(s.enemyFilter and s.enemyFilter.type or "").."_"..tostring(s.extra and (s.extra.token or s.extra.key or s.extra.kind or s.extra.amount) or "").."_"..tostring(s.roomFilter and roomFilterLabel(s.roomFilter) or "").."_"..tostring(s.bossFilter and bossFilterLabel(s.bossFilter) or "").."_"..tostring(s.voidFilter and extraLabel(s) or "") end
    if r.afterAmount then triggerKey=triggerKey.."_after_"..tostring(r.afterAmount) end
    triggerKey=triggerKey.."_cds_"..tostring(r.cooldownSeconds or 0).."_cdr_"..tostring(r.cooldownRooms or 0).."_chance_"..tostring(r.chance or 100).."_delay_"..tostring(r.delaySeconds or 0)
    return "condition_"..r.mode.."_"..triggerKey.."_"..r.action..(r.action=="hp_down" and ((r.hpLethal or r.hpNonlethal) and "_lethal" or "_nonlethal") or "")..
        ((isRewardAction(r.action) or r.action=="remove_item" or r.action=="spawn_trinket" or r.action=="use_active_effect") and ("_"..M.Rewards.Key(r.gift)) or "")..(r.effectConfig and ("_"..tostring(r.effectConfig.kind or r.effectConfig.status or r.effectConfig.roomType or r.effectConfig.type or r.effectConfig.playerType or r.effectConfig.id or r.effectConfig.stage or r.effectConfig.text or "").."_"..tostring(r.effectConfig.amount or r.effectConfig.stageType or "")) or "")
end
local function stats(p)
    return {hp=p:GetHearts()+p:GetSoulHearts()+p:GetBoneHearts()*2,
        speed=p.MoveSpeed, tears=30/(math.max(-0.99,p.MaxFireDelay)+1), damage=p.Damage,
        range=p.TearRange, shot_speed=p.ShotSpeed, luck=p.Luck,
        health={red=p:GetHearts(), soul=p:GetSoulHearts(), bone=p:GetBoneHearts()}}
end
local function events(before, after)
    local result = {}
    for key, value in pairs(after) do
        if type(value) == "number" then
        local delta = value - before[key]
        if math.abs(delta) > 0.0001 then result[key..(delta > 0 and "_up" or "_down")] = true end
        end
    end
    return result
end
function M.Attach(mod, game, getConfig, isInitializing, blockedItem)
    local state = {bonus={}, met={}, activations={}}
    local previous, blockedMessageUntil = nil, 0
    local raw, previousRaw = {}, {}
    local pendingEvents = {}
    local pendingAbsorb=nil
    local activeEnemyBeforeDeath = {}
    local pendingGrabItems, pendingGrabTouch, grabPoolCache = {}, {}, {}
    local pendingPickupTouches = {}
    local choiceSuppressUntil = {}
    local confirmedChoiceRemovals = {}
    local previousPickupCounts = {}
    local previousExtra,previousPlayerType,slotStates = {},nil,{}
    local pedestalTracker=nil
    local suppressedDupePedestals={}
    local enteredRooms = {}
    local roomEnterCount, roomClearCount = 0, 0
    local roomDamaged, floorDamaged = false, false
    local levelStartFrame = game:GetFrameCount()
    local keyHeld = {}
    local deathList = {roomKey=nil, saw=false, failed=false, missing=0, cleared=false}
    local seenLevel, lastChapter = false, nil
    local runStartPending=false
    local evaluationSerial=0
    -- Do not read/set the run seed while the mod file is loading: outside a
    -- run GetStartSeed can be 0, and RNG:SetSeed rejects a zero seed.
    local chanceRoller=RNG()
    local delayed={}
    local function copyRaw()
        local result = {}
        for key,value in pairs(raw) do result[key] = value end
        return result
    end
    local guard = {}
    local function primary(p)
        return game:GetNumPlayers() > 0 and GetPtrHash(p) == GetPtrHash(Isaac.GetPlayer(0))
    end
    local function blackHeartCount(p)
        local mask=tonumber(p:GetBlackHearts()) or 0
        local n=0
        while mask>0 do if mask%2==1 then n=n+1 end; mask=math.floor(mask/2) end
        return n
    end
    local function config()
        local c = getConfig()
        return c and c.conditions and #c.conditions > 0 and c or nil
    end
    local function isModdedItem(id)
        local okEntry, entry = pcall(function() return XMLData.GetEntryById(XMLNode.ITEM, id) end)
        if okEntry and type(entry) == "table" and entry.sourceid ~= nil then
            local sid = tostring(entry.sourceid)
            if sid ~= "" and sid ~= "0" and sid ~= "nil" then
                local okMod, info = pcall(function() return XMLData.GetModById(sid) end)
                if okMod and type(info) == "table" and next(info) ~= nil then return true end
            end
        end
        return false
    end
    local function poolContainsItem(ref, id)
        if type(ref) ~= "table" then return false end
        if tonumber(ref.id) == -1000 or tostring(ref.name or "") == "__challenge_maker_mod_items__" then return isModdedItem(id) end
        local key = tostring(ref.name or ref.id or "?")
        if not grabPoolCache[key] then
            local set = {}
            for _, item in ipairs(M.Rewards.PoolItems(game:GetItemPool(), ref) or {}) do
                if item.itemID and item.itemID > 0 then set[item.itemID] = true end
            end
            grabPoolCache[key] = set
        end
        return grabPoolCache[key][id] == true
    end
    local function grabMatches(g, grabbed)
        if not validGrab(g) then return false end
        if g.kind == "any" then return next(grabbed) ~= nil end
        if g.kind == "fixed" then
            local id = M.Rewards.Resolve(g.token)
            return id ~= nil and grabbed[id] == true
        end
        if g.kind == "pool" then
            for id in pairs(grabbed) do if poolContainsItem(g.pool, id) then return true end end
        end
        return false
    end
    local function absorbedMatches(filter, absorbed)
        if type(filter)~="table" or type(absorbed)~="table" then return false end
        for id in pairs(absorbed) do
            local cfg=Isaac.GetItemConfig():GetCollectible(tonumber(id) or 0);local active=cfg and tonumber(cfg.Type)==tonumber((ItemType and ItemType.ITEM_ACTIVE) or 3)
            if filter.category=="any" or (filter.category=="active" and active) or (filter.category=="passive" and not active) then
                local token=tostring(id);local enabled=filter.choices and filter.choices[token]
                if enabled==nil then
                    for configured,value in pairs(filter.choices or {}) do
                        local resolved=M.Rewards.Resolve(configured)
                        if resolved and tonumber(resolved)==tonumber(id) then enabled=value;break end
                    end
                end
                if enabled==nil then enabled=filter.all end
                if enabled then return true end
            end
        end
        return false
    end
    local function singleRuleTriggered(rule, ev, grabbed)
        if ({health_threshold=true,stat_threshold=true,has_property=true,active_fully_charged=true})[rule.trigger] then
            local list=ev[rule.trigger]; return type(list)=="table" and list[M.Key(rule)]==true
        end
        if rule.trigger == "grab_item" then return grabMatches(rule.grab, grabbed) end
        if isRoomTrigger(rule.trigger) then
            local roomEvent = ev[rule.trigger]
            if type(roomEvent) ~= "table" or not validRoomFilter(rule.roomFilter) then return false end
            if rule.roomFilter.any == true then return true end
            for _, roomType in ipairs(rule.roomFilter.types or {}) do
                if tonumber(roomType) == tonumber(roomEvent.roomType) then return true end
            end
            return false
        end
        if rule.trigger == "key_pressed" then
            return type(ev.key_pressed) == "table" and ev.key_pressed[tostring(rule.keyBinding.code)] == true
        end
        if rule.trigger == "boss_defeated" then
            local be=ev.boss_defeated; local f=rule.bossFilter
            if type(be)~="table" or not validBossFilter(f) then return false end
            if f.any==true then return true end
            local sf=f.stages and f.stages[tostring(be.stageId)] or nil
            if type(sf)~="table" then return false end
            if sf.any==true then return true end
            return type(sf.bosses)=="table" and sf.bosses[tostring(be.bossId)]==true
        end
        if rule.trigger=="item_used" then
            local used=ev.item_used; local f=rule.itemUse
            if type(used)~="table" or not validItemUse(f) then return false end
            if f.kind=="any" then return next(used)~=nil end
            local id=M.Rewards.Resolve(f.token)
            return id~=nil and used[tostring(id)]==true
        end
        if rule.trigger=="pickup_collected" then
            local got=ev.pickup_collected; local f=rule.pickupFilter
            if type(got)~="table" or not validPickupFilter(f) then return false end
            return (f.kind=="any" and next(got)~=nil) or got[tostring(f.kind)]==true
        end
        if rule.trigger=="pickup_spawned" then
            local got=ev.pickup_spawned; local f=rule.extra
            return type(got)=="table" and validPickupFilter(f) and ((f.kind=="any" and next(got)~=nil) or got[tostring(f.kind)]==true)
        end
        if rule.trigger=="deal_entered" then return type(ev.deal_entered)=="table" and (rule.extra.kind=="any" or ev.deal_entered[rule.extra.kind]==true) end
        if rule.trigger=="teleport_to_room_event" then return type(ev.teleport_to_room_event)=="table" and tonumber(ev.teleport_to_room_event.roomType)==tonumber(rule.eventConfig.roomType) end
        if rule.trigger=="spawn_enemy_event" then
            for _,e in ipairs(ev.spawn_enemy_event or {}) do if tonumber(e.type)==tonumber(rule.eventConfig.type) and tonumber(e.variant or 0)==tonumber(rule.eventConfig.variant or 0) and tonumber(e.subtype or 0)==tonumber(rule.eventConfig.subtype or 0) then return true end end;return false
        end
        if rule.trigger=="remove_item_event" then return type(ev.remove_item_event)=="table" and next(ev.remove_item_event)~=nil end
        if rule.trigger=="void_absorb" or rule.trigger=="abbys_absorb" then return absorbedMatches(rule.voidFilter,ev[rule.trigger]) end
        if rule.trigger=="pickup_count" then
            local reached=ev.pickup_count; local f=rule.pickupCount
            return type(reached)=="table" and validPickupCount(f) and reached[tostring(f.kind)]==true
        end
        if rule.trigger=="room_entered_x" then
            if type(ev.room_entered_x)~="table" then return false end
            local count=math.floor(tonumber(ev.room_entered_x.count) or -1); local target=math.floor(tonumber(rule.triggerParam and rule.triggerParam.amount) or -1)
            if target<1 then return false end
            if rule.repeatMode=="repeat" or rule.repeatMode=="custom" then return count>0 and count%target==0 end
            return count==target
        end
        if rule.trigger=="room_cleared_x" then
            if type(ev.room_cleared_x)~="table" then return false end
            local count=math.floor(tonumber(ev.room_cleared_x.count) or -1); local target=math.floor(tonumber(rule.triggerParam and rule.triggerParam.amount) or -1)
            if target<1 then return false end
            if rule.repeatMode=="repeat" or rule.repeatMode=="custom" then return count>0 and count%target==0 end
            return count==target
        end
        if rule.trigger=="floor_cleared_time" then return type(ev.floor_cleared_time)=="table" and tonumber(ev.floor_cleared_time.seconds) and tonumber(ev.floor_cleared_time.seconds)<=tonumber(rule.triggerParam and rule.triggerParam.amount) end
        if rule.trigger=="no_damage_room" then return ev.no_damage_room==true end
        if rule.trigger=="no_damage_floor" then return ev.no_damage_floor==true end
        if rule.trigger=="enemy_killed" then
            local list=ev.enemy_killed; local f=rule.enemyFilter
            if type(list)~="table" or not validEnemyFilter(f) then return false end
            for _,e in ipairs(list) do
                if f.kind=="any" then return true end
                if f.kind=="boss" and e.boss then return true end
                if f.kind=="champion" and e.champion then return true end
                if f.kind=="fixed" then
                    if type(f.matches)=="table" and #f.matches>0 then
                        for _,m in ipairs(f.matches) do
                            if tonumber(m.type)==tonumber(e.type) and (m.variant==nil or tonumber(m.variant)==tonumber(e.variant)) and (m.subtype==nil or tonumber(m.subtype)==tonumber(e.subtype)) then return true end
                        end
                    elseif tonumber(f.type)==tonumber(e.type) and (f.variant==nil or tonumber(f.variant)==tonumber(e.variant)) and (f.subtype==nil or tonumber(f.subtype)==tonumber(e.subtype)) then return true end
                end
            end
            return false
        end
        return ev[rule.trigger] == true
    end
    local function ruleTriggered(rule,ev,grabbed)
        local first=singleRuleTriggered(rule,ev,grabbed)
        if rule.logic=="and" and type(rule.secondary)=="table" then return first and singleRuleTriggered(rule.secondary,ev,grabbed) end
        if rule.logic=="or" and type(rule.secondary)=="table" then return first or singleRuleTriggered(rule.secondary,ev,grabbed) end
        return first
    end
    local function activationMode(rule)
        if rule.repeatMode=="one_time" or rule.repeatMode=="repeat" or rule.repeatMode=="custom" or rule.repeatMode=="once_room" or rule.repeatMode=="once_floor" then return rule.repeatMode end
        -- Backward compatibility: old X-times counters were one-shot, while other old conditions repeated.
        if rule.trigger=="room_entered_x" or rule.trigger=="room_cleared_x" then return "one_time" end
        return "repeat"
    end
    local function canActivate(rule,index)
        local mode=activationMode(rule)
        local used=tonumber(state.activations and state.activations[tostring(index)]) or 0
        local key=tostring(index);local nowFrame=game:GetFrameCount()
        local lastFrame=state.lastActivationFrame and tonumber(state.lastActivationFrame[key])
        if lastFrame and nowFrame-lastFrame<math.floor(math.max(0,tonumber(rule.cooldownSeconds) or 0)*30) then return false end
        local lastRoom=state.lastActivationRoom and tonumber(state.lastActivationRoom[key])
        if lastRoom and roomClearCount-lastRoom<math.floor(math.max(0,tonumber(rule.cooldownRooms) or 0)) then return false end
        local target=math.max(1,math.floor(tonumber(rule.afterAmount) or 1))
        if target>1 then
            state.afterCounters=state.afterCounters or {};state.afterFrames=state.afterFrames or {}
            local key=tostring(index);local frame=evaluationSerial
            if state.afterFrames[key]~=frame then state.afterFrames[key]=frame;state.afterCounters[key]=(tonumber(state.afterCounters[key]) or 0)+1 end
            if state.afterCounters[key]<target then return false end
        end
        if not state.chanceSeeded then local seed=tonumber(game:GetSeeds():GetStartSeed()) or 1;if seed==0 then seed=1 end;chanceRoller:SetSeed(seed,35);state.chanceSeeded=true end
        local chance=math.max(0,math.min(100,tonumber(rule.chance) or 100));state.chanceChecks=state.chanceChecks or {}
        local check=state.chanceChecks[key]
        if not check or check.serial~=evaluationSerial then check={serial=evaluationSerial,pass=chance>=100 or (chance>0 and chanceRoller:RandomFloat()*100<chance)};state.chanceChecks[key]=check end
        if not check.pass then return false end
        if mode=="one_time" then return used<1 end
        if mode=="custom" then return used<math.max(1,math.floor(tonumber(rule.repeatAmount) or 1)) end
        if mode=="once_room" then return not (state.roomActivations and state.roomActivations[tostring(index)]) end
        if mode=="once_floor" then return not (state.floorActivations and state.floorActivations[tostring(index)]) end
        return true
    end
    local function markActivated(index,rule)
        state.activations=state.activations or {}
        local key=tostring(index); state.activations[key]=(tonumber(state.activations[key]) or 0)+1
        if activationMode(rule)=="once_room" then state.roomActivations=state.roomActivations or {};state.roomActivations[key]=true end
        if activationMode(rule)=="once_floor" then state.floorActivations=state.floorActivations or {};state.floorActivations[key]=true end
        state.lastActivationFrame=state.lastActivationFrame or {};state.lastActivationFrame[key]=game:GetFrameCount()
        state.lastActivationRoom=state.lastActivationRoom or {};state.lastActivationRoom[key]=roomClearCount
        if state.afterCounters then state.afterCounters[key]=0 end
    end
    local function markMust(c, ev, grabbed)
        grabbed = grabbed or {}
        for i, rule in ipairs(c.conditions) do
            if rule.enabled~=false and M.Valid(rule) and rule.mode == "must" and ruleTriggered(rule, ev, grabbed) then state.met[tostring(i)] = true end
        end
    end
    function guard.Reset()
        delayed={}
        state = {bonus={}, met={}, activations={},afterCounters={},afterFrames={},roomActivations={},floorActivations={},lastActivationFrame={},lastActivationRoom={},chanceChecks={}}
        previous = nil
        raw, previousRaw = {}, {}
        pendingEvents = {};pendingAbsorb=nil
        activeEnemyBeforeDeath = {}
        pendingGrabItems, pendingGrabTouch, grabPoolCache = {}, {}, {}
        pendingPickupTouches = {};choiceSuppressUntil={};suppressedDupePedestals={};confirmedChoiceRemovals={}
        previousPickupCounts = {}
        previousExtra,previousPlayerType,slotStates = {},nil,{}
        pedestalTracker=nil
        enteredRooms = {}
        roomEnterCount, roomClearCount = 0, 0
        roomDamaged, floorDamaged = false, false
        levelStartFrame = game:GetFrameCount()
        keyHeld = {}
        deathList = {roomKey=nil, saw=false, failed=false, missing=0, cleared=false}
        seenLevel, lastChapter = false, nil
        runStartPending=false
        blockedMessageUntil = 0
    end
    function guard.Snapshot()
        state.roomEnterCount=roomEnterCount or 0
        state.roomClearCount=roomClearCount or 0
        if state.timerStarted then state.timerElapsed=(tonumber(state.timerElapsed) or 0)+math.max(0,game:GetFrameCount()-state.timerStarted);state.timerStarted=game:GetFrameCount();state.timerRunning=true else state.timerRunning=false end
        return state
    end
    function guard.Restore(saved)
        if type(saved) ~= "table" then return end
        state = {bonus=type(saved.bonus)=="table" and saved.bonus or {}, met=type(saved.met)=="table" and saved.met or {}, activations=type(saved.activations)=="table" and saved.activations or {},afterCounters=type(saved.afterCounters)=="table" and saved.afterCounters or {},afterFrames={},roomActivations=type(saved.roomActivations)=="table" and saved.roomActivations or {},floorActivations=type(saved.floorActivations)=="table" and saved.floorActivations or {},lastActivationFrame=type(saved.lastActivationFrame)=="table" and saved.lastActivationFrame or {},lastActivationRoom=type(saved.lastActivationRoom)=="table" and saved.lastActivationRoom or {},chanceChecks={}, rewardRoll=tonumber(saved.rewardRoll) or 0,timerStarted=saved.timerRunning and game:GetFrameCount() or nil,timerElapsed=tonumber(saved.timerElapsed) or 0,timerRunning=saved.timerRunning==true}
        previous = nil
        raw, previousRaw = {}, {}
        pendingEvents = {};pendingAbsorb=nil
        pendingGrabItems, pendingGrabTouch, grabPoolCache = {}, {}, {}
        pendingPickupTouches = {};choiceSuppressUntil={};suppressedDupePedestals={};confirmedChoiceRemovals={}
        previousPickupCounts = {}
        previousExtra,previousPlayerType,slotStates = {},nil,{}
        pedestalTracker=nil
        enteredRooms = {}
        roomEnterCount, roomClearCount = math.max(0,math.floor(tonumber(saved.roomEnterCount) or 0)), math.max(0,math.floor(tonumber(saved.roomClearCount) or 0))
        roomDamaged, floorDamaged = false, false
        levelStartFrame = game:GetFrameCount()
        keyHeld = {}
        deathList = {roomKey=nil, saw=false, failed=false, missing=0, cleared=false}
        local level = game.GetLevel and game:GetLevel() or nil
        local stage = level and tonumber(level:GetStage()) or nil
        seenLevel = stage ~= nil
        lastChapter = stage and (stage <= 8 and math.floor((stage+1)/2) or stage-4) or nil
        runStartPending=false
        if game:GetNumPlayers() > 0 then
            local p = Isaac.GetPlayer(0)
            p:AddCacheFlags(CacheFlag.CACHE_ALL)
            p:EvaluateItems()
        end
    end
    function guard.ArmRunStart(enabled) runStartPending=enabled==true end
    function guard.CanFinish()
        local c = config()
        if not c then return true end
        for i, rule in ipairs(c.conditions) do
            if rule.enabled~=false and M.Valid(rule) and rule.mode=="must" then
                if ({health_threshold=true,stat_threshold=true,has_property=true,active_fully_charged=true})[rule.trigger] then
                    local p=game:GetNumPlayers()>0 and Isaac.GetPlayer(0) or nil
                    if not p or not guard.ExtraSatisfied(rule,p) then return false end
                elseif rule.trigger=="pickup_count" then
                    local p=game:GetNumPlayers()>0 and Isaac.GetPlayer(0) or nil
                    local f=rule.pickupCount; local amount=tonumber(f and f.amount) or 0; local value=0
                    if p then
                        if f.kind=="coins" then value=p:GetNumCoins() elseif f.kind=="bombs" then value=p:GetNumBombs() elseif f.kind=="keys" then value=p:GetNumKeys()
                        elseif f.kind=="red_hearts" then value=p:GetHearts()/2 elseif f.kind=="soul_hearts" then value=p:GetSoulHearts()/2 elseif f.kind=="black_hearts" then value=blackHeartCount(p)
                        elseif f.kind=="bone_hearts" then value=p:GetBoneHearts() elseif f.kind=="rotten_hearts" then value=p:GetRottenHearts() end
                    end
                    if value<amount then return false end
                elseif not state.met[tostring(i)] then return false end
            end
        end
        return true
    end
    -- Native intermediate stages retain changes hidden by the tears cap and
    -- Rock Bottom. Never return a value here: observing must not alter stats.
    local rawStat = {}
    if ModCallbacks.MC_EVALUATE_STAT and EvaluateStatStage then
        for name,stat in pairs({TEARS_UP="tears",FLAT_TEARS="tears",DAMAGE_UP="damage",FLAT_DAMAGE="damage"}) do
            local stage = EvaluateStatStage[name]
            if stage ~= nil then rawStat[stage] = stat end
        end
        mod:AddCallback(ModCallbacks.MC_EVALUATE_STAT, function(_,p,stage,value)
            if config() and primary(p) and rawStat[stage] and type(value)=="number" then
                raw[stage] = value
            end
        end)
    end
    mod:AddCallback(ModCallbacks.MC_EVALUATE_CACHE, function(_, p, flag)
        if not config() or not primary(p) then return end
        -- Read the native cache before our bonus and before the final held stats.
        if flag == CacheFlag.CACHE_SPEED then raw.speed = p.MoveSpeed
        elseif flag == CacheFlag.CACHE_RANGE then raw.range = p.TearRange
        elseif flag == CacheFlag.CACHE_SHOTSPEED then raw.shot_speed = p.ShotSpeed
        elseif flag == CacheFlag.CACHE_LUCK then raw.luck = p.Luck end
        local b = state.bonus
        if flag == CacheFlag.CACHE_SPEED then p.MoveSpeed = math.max(0.1,p.MoveSpeed+(b.speed or 0))
        elseif flag == CacheFlag.CACHE_FIREDELAY then
            local baseRate = 30/(math.max(-0.99,p.MaxFireDelay)+1)
            local tearsRate = baseRate + (b.tears or 0)
            if (b.tears or 0) > 0 then tearsRate = math.min(5, tearsRate) end
            tearsRate = math.max(0.1, tearsRate)
            local finalRate = tearsRate + (b.fire_rate or 0)
            if (b.fire_rate or 0) > 0 then finalRate = math.min(120, finalRate) end
            p.MaxFireDelay = 30/math.max(0.1,finalRate)-1
        elseif flag == CacheFlag.CACHE_DAMAGE then p.Damage = math.max(0.1,p.Damage+(b.damage or 0))
        elseif flag == CacheFlag.CACHE_RANGE then p.TearRange = math.max(40,p.TearRange+(b.range or 0))
        elseif flag == CacheFlag.CACHE_SHOTSPEED then p.ShotSpeed = math.max(0.1,p.ShotSpeed+(b.shot_speed or 0))
        elseif flag == CacheFlag.CACHE_LUCK then p.Luck = p.Luck+(b.luck or 0) end
    end)
    local function currentRoomKey()
        local level = game:GetLevel()
        local desc = level and level:GetCurrentRoomDesc() or nil
        return tostring(level and level:GetStage() or -1) .. ":" .. tostring(desc and desc.ListIndex or -1)
    end
    local function currentChapter()
        local level = game.GetLevel and game:GetLevel() or nil
        local stage = level and tonumber(level:GetStage()) or nil
        if not stage then return nil end
        -- Chapters 1-4 have two normal floors. Later special/endgame stages
        -- are separate chapters for condition purposes.
        return stage <= 8 and math.floor((stage+1)/2) or stage-4
    end
    function guard.ExtraSatisfied(rule,p)
        local x=rule.extra or {}
        local value=nil
        if rule.trigger=="health_threshold" then value=(p:GetHearts()+p:GetSoulHearts()+p:GetBoneHearts()*2)/2
        elseif rule.trigger=="stat_threshold" then
            local s=stats(p); value=s[x.stat]; if x.stat=="range" and value then value=value/40 end
        elseif rule.trigger=="has_property" then
            if x.kind=="item" then local id=M.Rewards.Resolve(x.token); return id and p:HasCollectible(id,true) or false end
            if x.kind=="trinket" then local id=M.Rewards.ResolveTrinket(x.token); return id and p:HasTrinket(id,true) or false end
            if x.kind=="transformation" then local id=tonumber(x.id); return id and id>=0 and p:HasPlayerForm(id) or false end
        elseif rule.trigger=="active_fully_charged" then
            for _,slot in ipairs({0,1,2,3}) do
                local id=p:GetActiveItem(slot)
                if id and id>0 then
                    local max=0; pcall(function() max=p:GetActiveMaxCharge(slot) end)
                    if not max or max<=0 then local cfg=Isaac.GetItemConfig():GetCollectible(id); max=cfg and tonumber(cfg.MaxCharges) or 0 end
                    if max and max>0 and p:GetActiveCharge(slot)>=max then return true end
                end
            end
            return false
        end
        local target=tonumber(x.amount); if value==nil or target==nil then return false end
        return x.direction=="above" and value>=target or x.direction=="below" and value<=target
    end
    local function resetDeathListRoom()
        deathList = {roomKey=currentRoomKey(), saw=false, failed=false, missing=0, cleared=false}
    end
    local function updateDeathListTracker()
        local c = config()
        if not c then return end
        local interested = false
        for _, rule in ipairs(c.conditions) do
            if rule.enabled~=false and M.Valid(rule) and rule.trigger == "death_list_complete" then interested = true break end
        end
        if not interested then return end
        local key = currentRoomKey()
        if deathList.roomKey ~= key then resetDeathListRoom() end
        if deathList.cleared then return end
        local skulls = Isaac.FindByType(EntityType.ENTITY_EFFECT, EffectVariant.DEATH_SKULL, -1, false, false)
        if #skulls > 0 then
            deathList.saw = true
            deathList.missing = 0
        elseif deathList.saw and not game:GetRoom():IsClear() and game:GetRoom():GetAliveEnemiesCount() > 0 then
            -- The mark can move between enemies without being queryable for a frame.
            -- Only call the attempt failed after a short continuous absence.
            deathList.missing = deathList.missing + 1
            if deathList.missing >= 4 then deathList.failed = true end
        end
    end
    if ModCallbacks.MC_POST_NEW_ROOM then
        mod:AddCallback(ModCallbacks.MC_POST_NEW_ROOM, function()
            state.roomActivations={}
            if not config() then return end
            resetDeathListRoom()
            local level = game:GetLevel()
            local desc = level and level:GetCurrentRoomDesc() or nil
            local room = game:GetRoom()
            local roomType = desc and desc.Data and tonumber(desc.Data.Type) or (room and room:GetType())
            local roomKey = currentRoomKey() .. ":" .. tostring(desc and desc.Dimension or 0)
            local visitCount = tonumber(desc and desc.VisitedCount) or 0
            local firstVisit = not enteredRooms[roomKey] and visitCount <= 1
            enteredRooms[roomKey] = true
            pedestalTracker=nil;confirmedChoiceRemovals={};choiceSuppressUntil={}
            roomEnterCount = roomEnterCount + 1
            pendingEvents.room_entered_x = {count=roomEnterCount}
            roomDamaged = false
            pendingEvents.room_enter = {roomType=roomType}
            if tonumber(roomType)==tonumber(RoomType.ROOM_DEVIL) then pendingEvents.deal_entered={devil=true}
            elseif tonumber(roomType)==tonumber(RoomType.ROOM_ANGEL) then pendingEvents.deal_entered={angel=true} end
            if tonumber(roomType)==tonumber(RoomType.ROOM_SECRET) or tonumber(roomType)==tonumber(RoomType.ROOM_SUPERSECRET) or (RoomType.ROOM_ULTRASECRET and tonumber(roomType)==tonumber(RoomType.ROOM_ULTRASECRET)) then pendingEvents.secret_room_found=true end
            if firstVisit then pendingEvents.uncleared_room_enter = {roomType=roomType} end
        end)
    end
    if ModCallbacks.MC_POST_NEW_LEVEL then
        mod:AddCallback(ModCallbacks.MC_POST_NEW_LEVEL, function()
            state.roomActivations={};state.floorActivations={}
            if not config() then seenLevel, lastChapter = false, nil return end
            local chapter = currentChapter()
            if seenLevel and not (isInitializing and isInitializing()) then
                pendingEvents.change_floor = true
                local elapsed=math.max(0,(game:GetFrameCount()-(levelStartFrame or game:GetFrameCount()))/30)
                pendingEvents.floor_cleared_time={seconds=elapsed}
                if not floorDamaged then pendingEvents.no_damage_floor=true end
                if lastChapter ~= nil and chapter ~= nil and chapter ~= lastChapter then
                    pendingEvents.change_stage = true
                end
            end
            seenLevel, lastChapter = true, chapter
            floorDamaged=false
            roomDamaged=false
            levelStartFrame=game:GetFrameCount()
            -- Room list indices are reused on a new floor (including Forget Me
            -- Now / R Key repeats), so first-visit tracking must start fresh.
            enteredRooms = {}
        end)
    end
    if ModCallbacks.MC_POST_ROOM_TRIGGER_CLEAR then
        mod:AddCallback(ModCallbacks.MC_POST_ROOM_TRIGGER_CLEAR, function(_, silent)
            local c = config()
            if not c then return end
            pendingEvents.room_clear = true
            roomClearCount = roomClearCount + 1
            pendingEvents.room_cleared_x = {count=roomClearCount}
            if not roomDamaged then pendingEvents.no_damage_room=true end
            local level = game:GetLevel()
            local desc = level and level:GetCurrentRoomDesc() or nil
            local room = game:GetRoom()
            local roomType = desc and desc.Data and tonumber(desc.Data.Type) or (room and room:GetType())
            pendingEvents.clearing_room = {roomType=roomType}
            if tonumber(roomType)==tonumber(RoomType.ROOM_BOSS) then
                local bossId=0; pcall(function() bossId=tonumber(room:GetBossID()) or 0 end)
                local stageId=nil; pcall(function() stageId=tonumber(Isaac.GetCurrentStageConfigId()) end)
                if bossId and bossId>0 and stageId then pendingEvents.boss_defeated={bossId=bossId,stageId=stageId} end
            end
            if deathList.roomKey ~= currentRoomKey() then resetDeathListRoom() end
            -- POST_ROOM_TRIGGER_CLEAR runs after the room awards/effects. Requiring a
            -- seen skull excludes ordinary room clears and no-enemy button rooms.
            if deathList.saw and not deathList.failed and not deathList.cleared then
                pendingEvents.death_list_complete = true
            end
            deathList.cleared = true
        end)
    end
    if ModCallbacks.MC_ENTITY_TAKE_DMG then
        mod:AddCallback(ModCallbacks.MC_ENTITY_TAKE_DMG, function(_, entity, amount, flags, source, countdown)
            local c = config()
            local player = entity and entity:ToPlayer() or nil
            if c and player and primary(player) and not (isInitializing and isInitializing()) then
                pendingEvents.taking_damage = true
                roomDamaged = true
                floorDamaged = true
            end
        end)
    end
    local function effect(p, key, selectedAmount, hpLethal)
        local stat, direction = key:match("^(.*)_(%a+)$")
        local sign = direction == "up" and 1 or -1
        local amount = tonumber(selectedAmount) or defaultAmounts[stat] or 1
        if stat == "hp" then
            local units = math.max(1, math.floor(amount*2+0.5))
            if sign > 0 then
                local before = p:GetHearts()
                p:AddHearts(units)
                local left = units-(p:GetHearts()-before)
                if left > 0 and p:CanPickSoulHearts() then p:AddSoulHearts(left) end
            else
                local total=p:GetHearts()+p:GetSoulHearts()
                local left = math.min(units,math.max(0,total-(hpLethal and 0 or 1)))
                local soul = math.min(left,p:GetSoulHearts())
                if soul > 0 then p:AddSoulHearts(-soul) end
                if left > soul then p:AddHearts(-(left-soul)) end
                if hpLethal and total>0 and units>=total and not p:IsDead() then p:Kill() end
            end
        else
            local internalAmount = stat == "range" and amount*40 or amount
            state.bonus[stat] = (state.bonus[stat] or 0)+internalAmount*sign
        end
    end
    local function specialEffect(p,rule)
        local c=rule.effectConfig or {};local action=rule.action
        if action=="remove_item" then local id=M.Rewards.Resolve(rule.gift and rule.gift.token);if id and p:HasCollectible(id,true) then p:RemoveCollectible(id) end
        elseif action=="reroll_item" then
            local pool=game:GetItemPool();local room=game:GetRoom();local poolType=pool:GetPoolForRoom(room:GetType(),game:GetSeeds():GetStartSeed())
            for _,e in ipairs(Isaac.FindByType(EntityType.ENTITY_PICKUP,PickupVariant.PICKUP_COLLECTIBLE,-1,false,false)) do local pu=e:ToPickup();if pu and pu.SubType>0 then local id=pool:GetCollectible(poolType,true,pu.InitSeed);pu:Morph(EntityType.ENTITY_PICKUP,PickupVariant.PICKUP_COLLECTIBLE,id,true,true,false);pendingEvents.reroll_item_event=true end end
        elseif action=="dupe_item" then
            local originals={};for _,e in ipairs(Isaac.FindByType(EntityType.ENTITY_PICKUP,PickupVariant.PICKUP_COLLECTIBLE,-1,false,false)) do local pu=e:ToPickup();if pu and tonumber(pu.SubType or 0)>0 then originals[#originals+1]=pu end end
            for _,pu in ipairs(originals) do
                local pos=game:GetRoom():FindFreePickupSpawnPosition(pu.Position,40,true,false)
                local copy=Isaac.Spawn(EntityType.ENTITY_PICKUP,PickupVariant.PICKUP_COLLECTIBLE,pu.SubType,pos,Vector.Zero,p):ToPickup()
                if copy then suppressedDupePedestals[GetPtrHash(copy)]=true;local data=copy:GetData();if data then data.ChallengeMakerDupeItem=true end end
            end
        elseif action=="spawn_trinket" then state.rewardRoll=(state.rewardRoll or 0)+1;M.Rewards.SpawnTrinket(p,rule.gift,game,state.rewardRoll)
        elseif action=="heal" then p:AddHearts(math.max(1,math.floor((tonumber(c.amount) or 1)*2+0.5)))
        elseif action=="damage" then p:TakeDamage(math.max(0.5,tonumber(c.amount) or 1),DamageFlag.DAMAGE_NO_PENALTIES,EntityRef(p),0)
        elseif action=="add_heart_container" then local n=math.max(1,math.floor((tonumber(c.amount) or 1)*2+0.5));p:AddMaxHearts(n,true);p:AddHearts(n)
        elseif action=="remove_heart_container" then p:AddMaxHearts(-math.min(p:GetMaxHearts(),math.max(1,math.floor((tonumber(c.amount) or 1)*2+0.5))),true)
        elseif action=="charge_item" then
            local slot=ActiveSlot and ActiveSlot.SLOT_PRIMARY or 0;local id=p:GetActiveItem(slot)
            if id and id>0 then local amount=math.max(1,math.floor(tonumber(c.amount) or 1));local current=p:GetActiveCharge(slot);local maximum=0;pcall(function() maximum=p:GetActiveMaxCharge(slot) end);p:SetActiveCharge(maximum and maximum>0 and math.min(maximum,current+amount) or current+amount,slot) end
        elseif action=="give_pickup" then
            local n=math.max(1,math.floor(tonumber(c.amount) or 1));if c.kind=="coin" then p:AddCoins(n) elseif c.kind=="bomb" then p:AddBombs(n) elseif c.kind=="key" then p:AddKeys(n) elseif c.kind=="heart" then p:AddHearts(n*2) elseif c.kind=="card" then p:AddCard(game:GetItemPool():GetCard(game:GetSeeds():GetStartSeed(),true,true,false)) elseif c.kind=="pill" then p:AddPill(game:GetItemPool():GetPill(game:GetSeeds():GetStartSeed())) elseif c.kind=="battery" then p:SetActiveCharge(p:GetActiveCharge()+n) end
        elseif action=="spawn_pickup" then
            local map={coin=PickupVariant.PICKUP_COIN,bomb=PickupVariant.PICKUP_BOMB,key=PickupVariant.PICKUP_KEY,heart=PickupVariant.PICKUP_HEART,card=PickupVariant.PICKUP_TAROTCARD,pill=PickupVariant.PICKUP_PILL,battery=PickupVariant.PICKUP_LIL_BATTERY};local v=map[c.kind]
            for i=1,math.max(1,math.floor(tonumber(c.amount) or 1)) do game:Spawn(EntityType.ENTITY_PICKUP,v,game:GetRoom():FindFreePickupSpawnPosition(p.Position,40,true,false),RandomVector()*2,p,0,math.max(1,(game:GetRoom():GetSpawnSeed()+i*8191)%2147483647)) end
        elseif action=="teleport_room" then
            local level=game:GetLevel();local wanted=tonumber(c.roomType);local target=nil
            if wanted==tonumber(RoomType.ROOM_DEVIL) or wanted==tonumber(RoomType.ROOM_ANGEL) then
                pcall(function() level:InitializeDevilAngelRoom(wanted==tonumber(RoomType.ROOM_ANGEL),wanted==tonumber(RoomType.ROOM_DEVIL)) end)
                if GridRooms and GridRooms.ROOM_DEVIL_IDX then target=GridRooms.ROOM_DEVIL_IDX else target=-3 end
            else
                local rooms=level:GetRooms();for i=0,rooms.Size-1 do local d=rooms:Get(i);if d and d.Data and tonumber(d.Data.Type)==wanted then target=d.SafeGridIndex;break end end
            end
            if target then pendingEvents.teleport_to_room_event={roomType=wanted};game:StartRoomTransition(target,Direction.NO_DIRECTION,RoomTransitionAnim.TELEPORT,p) end
        elseif action=="open_doors" or action=="close_doors" then for i=0,DoorSlot.NUM_DOOR_SLOTS-1 do local door=game:GetRoom():GetDoor(i);if door then if action=="open_doors" then door:Open() else door:Close(true) end end end
        elseif action=="spawn_enemy" or action=="spawn_boss" then state.rewardRoll=(state.rewardRoll or 0)+1;game:Spawn(tonumber(c.type),tonumber(c.variant) or 0,game:GetRoom():FindFreeTilePosition(p.Position,80),Vector.Zero,p,tonumber(c.subtype) or 0,math.max(1,(game:GetRoom():GetSpawnSeed()+state.rewardRoll*8191)%2147483647));pendingEvents.spawn_enemy_event=pendingEvents.spawn_enemy_event or {};pendingEvents.spawn_enemy_event[#pendingEvents.spawn_enemy_event+1]={type=c.type,variant=c.variant,subtype=c.subtype}
        elseif action=="apply_status" then
            for _,e in ipairs(Isaac.FindInRadius(p.Position,10000,EntityPartition.ENEMY)) do local n=e:ToNPC();if n then if c.status=="fear" then n:AddFear(EntityRef(p),150) elseif c.status=="confusion" then n:AddConfusion(EntityRef(p),150,false) elseif c.status=="poison" then n:AddPoison(EntityRef(p),150,p.Damage) elseif c.status=="slow" then n:AddSlowing(EntityRef(p),150,0.5,Color(1,1,1,1,0,0,0)) end end end
        elseif action=="change_character" then
            local id=tonumber(c.playerType);if not id and tostring(c.token or "")~="" then local ok,v=pcall(function()return Isaac.GetPlayerTypeByName(c.token,false)end);if ok then id=v end end
            if id and id>=0 then p:ChangePlayerType(id) end
        elseif action=="use_active_effect" then local id=M.Rewards.Resolve(rule.gift and rule.gift.token);if id then p:UseActiveItem(id,UseFlag.USE_NOANIM|UseFlag.USE_NOANNOUNCER) end
        elseif action=="play_sound" then SFXManager():Play(tonumber(c.id) or 1,1,0,false,1)
        elseif action=="show_message" then pcall(function()game:GetHUD():ShowFortuneText(tostring(c.text))end)
        elseif action=="start_timer" then state.timerStarted=game:GetFrameCount()
        elseif action=="stop_timer" then if state.timerStarted then state.timerElapsed=(tonumber(state.timerElapsed) or 0)+math.max(0,game:GetFrameCount()-state.timerStarted);state.timerStarted=nil end
        elseif action=="end_challenge" or action=="win_challenge" then Isaac.Spawn(EntityType.ENTITY_PICKUP,PickupVariant.PICKUP_TROPHY,0,p.Position,Vector.Zero,p)
        elseif action=="lose_challenge" then p:Kill()
        elseif action=="repeat_floor" then StageTransition.SetSameStage(true);game:StartStageTransition(true,1)
        elseif action=="go_to_stage" then StageTransition.SetNextStage(math.floor(tonumber(c.stage) or 1),math.floor(tonumber(c.stageType) or 0));game:StartStageTransition(true,1)
        end
    end
    local function applyRule(p,rule)
        if rule.action=="give_item" or rule.action=="spawn_item" then
            state.rewardRoll=(state.rewardRoll or 0)+1
            if rule.action=="spawn_item" then M.Rewards.Spawn(p,rule.gift,game,state.rewardRoll,blockedItem) else M.Rewards.Give(p,rule.gift,game,state.rewardRoll,blockedItem) end
        elseif rule.action=="give_trinket" then state.rewardRoll=(state.rewardRoll or 0)+1;M.Rewards.GiveTrinket(p,rule.gift,game,state.rewardRoll)
        elseif specialActions[rule.action] then specialEffect(p,rule)
        else effect(p,rule.action,rule.amount,rule.hpLethal==true or rule.hpNonlethal==true) end
    end
    local function pickupKind(variant)
        if variant==PickupVariant.PICKUP_COIN then return "coin" elseif variant==PickupVariant.PICKUP_BOMB then return "bomb" elseif variant==PickupVariant.PICKUP_KEY then return "key"
        elseif variant==PickupVariant.PICKUP_HEART then return "heart" elseif variant==PickupVariant.PICKUP_TAROTCARD then return "card" elseif variant==PickupVariant.PICKUP_PILL then return "pill"
        elseif variant==PickupVariant.PICKUP_TRINKET then return "trinket" elseif variant==PickupVariant.PICKUP_LIL_BATTERY then return "battery" elseif variant==PickupVariant.PICKUP_GRAB_BAG then return "sack"
        elseif variant==PickupVariant.PICKUP_COLLECTIBLE then return "collectible"
        elseif variant==PickupVariant.PICKUP_CHEST or variant==PickupVariant.PICKUP_BOMBCHEST or variant==PickupVariant.PICKUP_SPIKEDCHEST or variant==PickupVariant.PICKUP_ETERNALCHEST
            or variant==PickupVariant.PICKUP_MIMICCHEST or variant==PickupVariant.PICKUP_OLDCHEST or variant==PickupVariant.PICKUP_WOODENCHEST or variant==PickupVariant.PICKUP_MEGACHEST
            or variant==PickupVariant.PICKUP_HAUNTEDCHEST then return "chest" end
        return nil
    end
    if ModCallbacks.MC_USE_ITEM then mod:AddCallback(ModCallbacks.MC_USE_ITEM,function(_,itemID,rng,player,useFlags,activeSlot,varData)
        if not config() or not player or not primary(player) or (isInitializing and isInitializing()) then return end
        pendingEvents.item_used=pendingEvents.item_used or {}; pendingEvents.item_used[tostring(itemID)]=true
        local voidID=(CollectibleType and CollectibleType.COLLECTIBLE_VOID) or 477
        local abyssID=(CollectibleType and CollectibleType.COLLECTIBLE_ABYSS) or 706
        local absorbTrigger=tonumber(itemID)==tonumber(voidID) and "void_absorb" or (tonumber(itemID)==tonumber(abyssID) and "abbys_absorb" or nil)
        if absorbTrigger then
            local snapshot={}
            for _,entity in ipairs(Isaac.FindByType(EntityType.ENTITY_PICKUP,PickupVariant.PICKUP_COLLECTIBLE,-1,false,false)) do
                local pickup=entity:ToPickup();if pickup and tonumber(pickup.SubType or 0)>0 then snapshot[GetPtrHash(pickup)]=tonumber(pickup.SubType) end
            end
            pendingAbsorb={trigger=absorbTrigger,items=snapshot,frame=game:GetFrameCount()}
        end
    end) end
    mod:AddCallback(ModCallbacks.MC_PRE_PICKUP_COLLISION,function(_,pickup,collider)
        local c=config(); local player=collider and collider:ToPlayer() or nil
        if not c or not player or not primary(player) or not pickup then return end
        local kind=pickupKind(pickup.Variant); if kind then
            local optionsIndex=0;pcall(function() optionsIndex=tonumber(pickup.OptionsPickupIndex) or 0 end)
            local siblings={}
            if kind=="collectible" and optionsIndex>0 then
                for _,e in ipairs(Isaac.FindByType(EntityType.ENTITY_PICKUP,PickupVariant.PICKUP_COLLECTIBLE,-1,false,false)) do
                    local other=e:ToPickup();if other and other.OptionsPickupIndex==optionsIndex then siblings[GetPtrHash(other)]=true end
                end
            end
            pendingPickupTouches[GetPtrHash(pickup)]={pickup=pickup,kind=kind,subtype=tonumber(pickup.SubType) or 0,optionsIndex=optionsIndex,siblings=siblings,wasTouched=pickup.Touched==true,frame=game:GetFrameCount()}
        end
    end)
    -- Inventory addition can happen AFTER the pickup animation. Observe the
    -- completed native collision instead, while the choice is being consumed.
    if ModCallbacks.MC_POST_PICKUP_COLLISION then mod:AddCallback(ModCallbacks.MC_POST_PICKUP_COLLISION,function(_,pickup,collider)
        if not config() or not pickup or not collider or not collider:ToPlayer() then return end
        local touch=pendingPickupTouches[GetPtrHash(pickup)]
        if not touch or touch.kind~="collectible" or touch.optionsIndex<=0 then return end
        local collected=tonumber(pickup.SubType)==0 or (pickup.Touched==true and not touch.wasTouched)
        pcall(function() collected=collected or pickup:GetSprite():IsPlaying("Collect") end)
        if collected then
            for hash in pairs(touch.siblings or {}) do confirmedChoiceRemovals[hash]=true end
        end
    end,PickupVariant.PICKUP_COLLECTIBLE) end
    if ModCallbacks.MC_POST_PICKUP_INIT then mod:AddCallback(ModCallbacks.MC_POST_PICKUP_INIT,function(_,pickup)
        if not config() or not pickup then return end
        local kind=pickupKind(pickup.Variant)
        if kind then pendingEvents.pickup_spawned=pendingEvents.pickup_spawned or {}; pendingEvents.pickup_spawned[kind]=true end
    end) end
    if ModCallbacks.MC_POST_SLOT_UPDATE then mod:AddCallback(ModCallbacks.MC_POST_SLOT_UPDATE,function(_,slot)
        if not config() or not slot then return end
        local key=GetPtrHash(slot); local stateNow=0; pcall(function() stateNow=tonumber(slot:GetState()) or tonumber(slot.State) or 0 end); local old=slotStates[key]; slotStates[key]=stateNow
        if old~=nil and stateNow~=old then
            pendingEvents.machine_used=true
            local v=tonumber(slot.Variant)
            if (SlotVariant and (v==tonumber(SlotVariant.DONATION_MACHINE) or v==tonumber(SlotVariant.GREED_DONATION_MACHINE))) then pendingEvents.donation_made=true end
        end
    end) end
    if ModCallbacks.MC_POST_NPC_INIT then mod:AddCallback(ModCallbacks.MC_POST_NPC_INIT,function(_,npc)
        if not config() or not npc or (isInitializing and isInitializing()) then return end
        pendingEvents.spawn_enemy_event=pendingEvents.spawn_enemy_event or {};pendingEvents.spawn_enemy_event[#pendingEvents.spawn_enemy_event+1]={type=npc.Type,variant=npc.Variant,subtype=npc.SubType}
    end) end
    if ModCallbacks.MC_POST_PICKUP_MORPH then mod:AddCallback(ModCallbacks.MC_POST_PICKUP_MORPH,function(_,pickup,previousType,previousVariant,previousSubType)
        if not config() or not pickup or (isInitializing and isInitializing()) then return end
        if tonumber(previousVariant)==tonumber(PickupVariant.PICKUP_COLLECTIBLE) and tonumber(pickup.Variant)==tonumber(PickupVariant.PICKUP_COLLECTIBLE) and tonumber(previousSubType)~=tonumber(pickup.SubType) then pendingEvents.reroll_item_event=true end
    end) end
    if ModCallbacks.MC_NPC_UPDATE then mod:AddCallback(ModCallbacks.MC_NPC_UPDATE,function(_,entity)
        if not config() or not entity then return end
        local active=false; pcall(function() active=entity:IsActiveEnemy(false) end)
        if active then activeEnemyBeforeDeath[GetPtrHash(entity)]=true end
    end) end
    if ModCallbacks.MC_POST_NPC_DEATH then mod:AddCallback(ModCallbacks.MC_POST_NPC_DEATH,function(_,entity)
        if not config() or not entity then return end
        local ptr=GetPtrHash(entity)
        local wasActive=activeEnemyBeforeDeath[ptr]==true
        activeEnemyBeforeDeath[ptr]=nil
        local boss=false; pcall(function() boss=entity:IsBoss() end)
        if not wasActive and not boss then return end
        local champion=false; pcall(function() champion=entity:IsChampion() end)
        pendingEvents.enemy_killed=pendingEvents.enemy_killed or {}; pendingEvents.enemy_killed[#pendingEvents.enemy_killed+1]={type=entity.Type,variant=entity.Variant,subtype=entity.SubType,boss=boss,champion=champion}
    end) end
    -- GRAB ITEM only counts a collectible actually taken from a pedestal.
    -- PRE_PICKUP_COLLISION records the touch; POST_ADD_COLLECTIBLE confirms that
    -- the item really entered the player's inventory. Direct AddCollectible calls
    -- (for example GIVE ITEM) therefore do not satisfy GRAB ITEM.
    mod:AddCallback(ModCallbacks.MC_PRE_PICKUP_COLLISION, function(_, pickup, collider)
        local c = config()
        local player = collider and collider:ToPlayer() or nil
        if not c or not player or not primary(player) or pickup.SubType <= 0 then return end
        -- Never let a pedestal generated by THEN/REPLACE WITH -> SPAWN ITEM
        -- satisfy GRAB ITEM. GIVE ITEM already cannot enter this path because
        -- it adds directly to inventory and has no pickup collision.
        local pickupData = pickup:GetData()
        if pickupData and pickupData.ChallengeMakerSpawnItem then return end
        local interested = false
        for _, rule in ipairs(c.conditions) do
            if rule.enabled~=false and M.Valid(rule) and rule.trigger == "grab_item" then interested = true break end
        end
        if interested then
            pendingGrabTouch[GetPtrHash(player)] = {id=pickup.SubType, frame=game:GetFrameCount(), pickup=pickup}
        end
    end, PickupVariant.PICKUP_COLLECTIBLE)
    if ModCallbacks.MC_POST_ADD_COLLECTIBLE then
        mod:AddCallback(ModCallbacks.MC_POST_ADD_COLLECTIBLE, function(_, itemID, charge, firstTime, slot, varData, player)
            if not config() or not player or not primary(player) or (isInitializing and isInitializing()) then return end
            local frame=game:GetFrameCount()
            for _,candidate in pairs(pendingPickupTouches) do
                if candidate and tonumber(candidate.subtype)==tonumber(itemID) and frame-(candidate.frame or 0)<=30 and tonumber(candidate.optionsIndex or 0)>0 then
                    choiceSuppressUntil[tostring(candidate.optionsIndex)]=frame+15
                end
            end
            local touch = pendingGrabTouch[GetPtrHash(player)]
            if touch and touch.id == itemID and game:GetFrameCount() - touch.frame <= 60 then
                pendingGrabItems[itemID] = true
                pendingGrabTouch[GetPtrHash(player)] = nil
            end
        end)
    end

    mod:AddCallback(ModCallbacks.MC_POST_UPDATE, function()
        evaluationSerial=evaluationSerial+1
        local c = config()
        if not c or game:GetNumPlayers() == 0 then previous = nil; raw = {}; previousRaw = {}; pendingEvents = {}; pendingAbsorb=nil; pendingGrabItems = {}; pendingGrabTouch = {}; pendingPickupTouches = {}; choiceSuppressUntil={}; previousPickupCounts = {}; pedestalTracker=nil;suppressedDupePedestals={};delayed={}; return end
        if not seenLevel then seenLevel, lastChapter = true, currentChapter() end
        updateDeathListTracker()
        local p = Isaac.GetPlayer(0)
        if p:IsDead() or (isInitializing and isInitializing()) then previous = nil; return end
        local delayedApplied=false
        for i=#delayed,1,-1 do if game:GetFrameCount()>=(delayed[i].frame or 0) then applyRule(p,delayed[i].rule);table.remove(delayed,i);delayedApplied=true end end
        if delayedApplied then p:AddCacheFlags(CacheFlag.CACHE_ALL);p:EvaluateItems();M.Rewards.ReassertPocket(p);previous=stats(p);previousRaw=copyRaw();return end
        if runStartPending then pendingEvents.run_start=true;runStartPending=false end
        local checkedKeys = {}
        for _, rule in ipairs(c.conditions) do
            if rule.enabled~=false and M.Valid(rule) and rule.trigger == "key_pressed" then
                local code = tonumber(rule.keyBinding.code)
                if code and not checkedKeys[code] then
                    checkedKeys[code] = true
                    local okTriggered, triggered = pcall(function() return Input.IsButtonTriggered(code, 0) end)
                    local okPressed, pressed = pcall(function() return Input.IsButtonPressed(code, 0) end)
                    pressed = okPressed and pressed == true
                    if (okTriggered and triggered) or (pressed and not keyHeld[code]) then
                        pendingEvents.key_pressed = pendingEvents.key_pressed or {}
                        pendingEvents.key_pressed[tostring(code)] = true
                    end
                    keyHeld[code] = pressed
                end
            end
        end
        local now = stats(p)
        -- Track pedestal identity rather than relying on the removal callback.
        -- Eternal D6 can alter pickup flags before removing an item, but a pedestal
        -- that vanishes between two frames is unambiguous. A normal pickup is
        -- excluded by PRE_PICKUP_COLLISION, and a reroll keeps the same pointer.
        local currentPedestals={}
        for _,entity in ipairs(Isaac.FindByType(EntityType.ENTITY_PICKUP,PickupVariant.PICKUP_COLLECTIBLE,-1,false,false)) do
            local pickup=entity:ToPickup();if pickup and tonumber(pickup.SubType or 0)>0 then
                local optionsIndex=0;pcall(function() optionsIndex=tonumber(pickup.OptionsPickupIndex) or 0 end)
                currentPedestals[GetPtrHash(pickup)]={subtype=pickup.SubType,pickup=pickup,optionsIndex=optionsIndex}
            end
        end
        local absorbedHashes={}
        if pendingAbsorb then
            local absorbed={}
            for hash,id in pairs(pendingAbsorb.items or {}) do
                if not currentPedestals[hash] then absorbedHashes[hash]=true;absorbed[tostring(id)]=true end
            end
            if next(absorbed)~=nil then
                pendingEvents[pendingAbsorb.trigger]=pendingEvents[pendingAbsorb.trigger] or {}
                for id in pairs(absorbed) do pendingEvents[pendingAbsorb.trigger][id]=true end
                pendingAbsorb=nil
            elseif game:GetFrameCount()-(pendingAbsorb.frame or 0)>3 then pendingAbsorb=nil end
        end
        if pedestalTracker then
            local oldStillPresent={}
            for hash,old in pairs(pedestalTracker) do if currentPedestals[hash] then oldStillPresent[tostring(old.subtype)]=true end end
            for hash,current in pairs(currentPedestals) do
                local token=tostring(current.subtype)
                if not pedestalTracker[hash] and not suppressedDupePedestals[hash] then
                    local entityData=nil;if current.pickup then pcall(function() entityData=current.pickup:GetData() end) end
                    if not (entityData and entityData.ChallengeMakerDupeItem) and oldStillPresent[token] then pendingEvents.dupe_item_event=true end
                end
            end
            -- Choice pedestals share OptionsPickupIndex. If the player actually
            -- touched one and it disappeared, every sibling from that same group
            -- that vanishes in the same update was removed by making the choice,
            -- not by an item-removal effect.
            local chosenOptionGroups={}
            local frame=game:GetFrameCount()
            for group,untilFrame in pairs(choiceSuppressUntil) do if tonumber(untilFrame)>=frame then chosenOptionGroups[group]=true else choiceSuppressUntil[group]=nil end end
            for hash in pairs(pendingPickupTouches) do
                local old=pedestalTracker[hash]
                if old and not currentPedestals[hash] and tonumber(old.optionsIndex or 0)>0 then chosenOptionGroups[tostring(old.optionsIndex)]=true end
            end
            for hash,old in pairs(pedestalTracker) do
                local removedByChoice=tonumber(old.optionsIndex or 0)>0 and chosenOptionGroups[tostring(old.optionsIndex)]==true
                if not currentPedestals[hash] and not pendingPickupTouches[hash] and not absorbedHashes[hash] and not removedByChoice and not confirmedChoiceRemovals[hash] then pendingEvents.remove_item_event=pendingEvents.remove_item_event or {};pendingEvents.remove_item_event[tostring(old.subtype or 0)]=true end
            end
        end
        for hash in pairs(confirmedChoiceRemovals) do if not currentPedestals[hash] then confirmedChoiceRemovals[hash]=nil end end
        for hash in pairs(suppressedDupePedestals) do if currentPedestals[hash] then suppressedDupePedestals[hash]=nil end end
        pedestalTracker=currentPedestals
        local playerType=tonumber(p:GetPlayerType())
        if previousPlayerType~=nil and playerType~=previousPlayerType then pendingEvents.character_changed=true end
        previousPlayerType=playerType
        for _,rule in ipairs(c.conditions) do
            if rule.enabled~=false and M.Valid(rule) and ({health_threshold=true,stat_threshold=true,has_property=true,active_fully_charged=true})[rule.trigger] then
                local key=M.Key(rule); local yes=guard.ExtraSatisfied(rule,p)
                if yes and previousExtra[key]~=true then pendingEvents[rule.trigger]=pendingEvents[rule.trigger] or {}; pendingEvents[rule.trigger][key]=true end
                previousExtra[key]=yes
            end
        end
        for hash,touch in pairs(pendingPickupTouches) do
            if not touch or game:GetFrameCount()-(touch.frame or 0)>30 then pendingPickupTouches[hash]=nil else
                local picked=false; local pu=touch.pickup; pcall(function() picked=(not pu:Exists()) or pu.Touched==true end)
                if picked then pendingEvents.pickup_collected=pendingEvents.pickup_collected or {}; pendingEvents.pickup_collected[tostring(touch.kind)]=true; pendingPickupTouches[hash]=nil end
            end
        end
        local counts={coins=p:GetNumCoins(),bombs=p:GetNumBombs(),keys=p:GetNumKeys(),red_hearts=p:GetHearts()/2,soul_hearts=p:GetSoulHearts()/2,black_hearts=blackHeartCount(p),bone_hearts=p:GetBoneHearts(),rotten_hearts=p:GetRottenHearts()}
        pendingEvents.pickup_count=pendingEvents.pickup_count or {}
        for _,rule in ipairs(c.conditions) do
            if rule.enabled~=false and M.Valid(rule) and rule.trigger=="pickup_count" then
                local f=rule.pickupCount; local kind=tostring(f.kind); local amount=tonumber(f.amount) or 0; local old=previousPickupCounts[kind]
                if counts[kind] and counts[kind]>=amount and (old==nil or old<amount) then pendingEvents.pickup_count[kind]=true end
            end
        end
        previousPickupCounts=counts
        if not previous then
            -- Seed every intermediate channel, including when starting without
            -- any stat item. This evaluation is baseline-only, never an event.
            p:AddCacheFlags(CacheFlag.CACHE_ALL)
            p:EvaluateItems()
            previous = stats(p)
            previousRaw = copyRaw()
            return
        end
        local ev = events(previous, now)
        for key, value in pairs(pendingEvents) do if value then ev[key] = value end end
        pendingEvents = {}
        -- A pedestal can take several frames between the initial collision and
        -- MC_POST_ADD_COLLECTIBLE (pickup animation, active-item swapping, etc.).
        -- Keep the touch alive long enough for the real add callback to confirm it,
        -- but discard stale contacts so a later direct GIVE ITEM cannot count.
        local frameNow = game:GetFrameCount()
        for hash, touch in pairs(pendingGrabTouch) do
            if not touch or frameNow - (touch.frame or frameNow) > 60 then
                pendingGrabTouch[hash] = nil
            end
        end
        local grabbed = pendingGrabItems
        pendingGrabItems = {}
        for key,value in pairs(raw) do
            local old = previousRaw[key]
            if old ~= nil and math.abs(value-old)>0.0001 then
                local stat = rawStat[key] or key
                ev[stat..(value>old and "_up" or "_down")] = true
            end
        end
        markMust(c, ev, grabbed)
        local changed = false
        local cancelled = {}
        -- Cancel each original change once, before applying any selected effects.
        -- All rules see the same original event, regardless of their list order.
        for i, rule in ipairs(c.conditions) do
            if rule.enabled~=false and M.Valid(rule) and rule.mode == "replace" and ruleTriggered(rule, ev, grabbed) and canActivate(rule,i) and not cancelled[rule.trigger] then
                local stat = rule.trigger:match("^(.*)_%a+$")
                if stat == "hp" then
                    local h = previous.health
                    local bones = h.bone-p:GetBoneHearts()
                    if bones ~= 0 then p:AddBoneHearts(bones) end
                    p:AddHearts(h.red-p:GetHearts())
                    p:AddSoulHearts(h.soul-p:GetSoulHearts())
                else
                    state.bonus[stat] = (state.bonus[stat] or 0)-(now[stat]-previous[stat])
                end
                cancelled[rule.trigger] = true
                changed = true
            end
        end
        for i, rule in ipairs(c.conditions) do
            if rule.enabled~=false and M.Valid(rule) and (rule.mode == "if" or rule.mode == "replace") and ruleTriggered(rule, ev, grabbed) and canActivate(rule,i) then
                local delay=math.max(0,tonumber(rule.delaySeconds) or 0)
                if delay>0 then delayed[#delayed+1]={frame=game:GetFrameCount()+math.floor(delay*30+0.5),rule=M.Rewards.Copy(rule)} else applyRule(p,rule) end
                markActivated(i,rule)
                changed = changed or delay<=0
            end
        end
        if changed then
            p:AddCacheFlags(CacheFlag.CACHE_ALL)
            p:EvaluateItems()
            M.Rewards.ReassertPocket(p)
            local after = stats(p)
            markMust(c, events(now,after), {})
            previous = after -- Consume generated changes; do not feed them back into IF.
        else previous = now end
        -- Consume both raw and visible changes caused by THEN / REPLACE WITH.
        -- A visible change plus one or more intermediate changes is one trigger.
        previousRaw = copyRaw()
    end)
    mod:AddCallback(ModCallbacks.MC_PRE_PICKUP_COLLISION, function(_, pickup, collider)
        if collider:ToPlayer() and not guard.CanFinish() then
            blockedMessageUntil = game:GetFrameCount()+90
            return true
        end
    end, PickupVariant.PICKUP_TROPHY)
    mod:AddCallback(ModCallbacks.MC_POST_PICKUP_UPDATE, function(_, pickup)
        if guard.CanFinish() then return end
        for i=0,game:GetNumPlayers()-1 do
            if Isaac.GetPlayer(i).Position:DistanceSquared(pickup.Position) < 48*48 then
                blockedMessageUntil = game:GetFrameCount()+30
            end
        end
    end, PickupVariant.PICKUP_TROPHY)
    mod:AddCallback(ModCallbacks.MC_POST_RENDER, function()
        if not config() then return end
        local frames=tonumber(state.timerElapsed) or 0;if state.timerStarted then frames=frames+math.max(0,game:GetFrameCount()-state.timerStarted) end
        if frames>0 or state.timerStarted then Isaac.RenderText(string.format("TIMER %.2f",frames/30),16,34,1,1,1,1) end
        if not guard.CanFinish() and game:GetFrameCount() <= blockedMessageUntil then
            Isaac.RenderText("TROPHY LOCKED: COMPLETE ALL MUST CONDITIONS", 25, 50, 1, 0.7, 0.3, 1)
            local y = 63
            for i,r in ipairs(config().conditions) do
                if M.Valid(r) and r.mode == "must" and not state.met[tostring(i)] then
                    Isaac.RenderText(M.Label(r),25,y,1,1,1,1)
                    y = y+12
                end
            end
        end
    end)
    return guard
end
return M

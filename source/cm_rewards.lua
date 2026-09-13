-- GIVE/SPAWN ITEM selection and bounded random sampling. No mutation of item pools.
local M = {}

-- Immutable editor-side snapshot of pool membership. Runtime ban logic can
-- remove collectibles from ItemPool, so picker menus must not depend on the
-- current mutable pool contents.
local poolSnapshot = {}

-- REPENTOGON's ItemPool can be temporarily unavailable/uninitialised while the
-- editor is loading. Keep one immutable copy of pool membership and, if the
-- live pool cannot provide it, reconstruct the original definition from
-- itempools.xml through XMLData. This makes the GIVE/SPAWN browser independent
-- from later BANNED ITEMS/BANNED POOLS mutations.
local function normalizePoolItem(raw)
    if raw == nil then return nil end
    local function field(name)
        local ok, value = pcall(function() return raw[name] end)
        return ok and value or nil
    end
    local id = tonumber(field("itemID") or field("itemid") or field("id"))
    if (not id or id <= 0) then
        local name = field("name")
        if type(name) == "string" and name ~= "" then
            local ok, resolved = pcall(function() return Isaac.GetItemIdByName(name) end)
            if ok then id = tonumber(resolved) end
        end
    end
    if not id or id <= 0 then return nil end
    local initial = tonumber(field("initialWeight") or field("initialweight") or field("weight") or 1) or 1
    local weight = tonumber(field("weight") or field("initialWeight") or field("initialweight") or 1) or 1
    return {itemID=id, initialWeight=initial, weight=weight}
end

local function copyPoolItems(items)
    if type(items) ~= "table" then return nil end
    local out, seen = {}, {}
    for _, raw in pairs(items) do
        local item = normalizePoolItem(raw)
        if item and not seen[item.itemID] then
            seen[item.itemID] = true
            out[#out + 1] = item
        end
    end
    table.sort(out, function(a,b) return a.itemID < b.itemID end)
    return #out > 0 and out or nil
end

local function xmlPoolEntry(id, ref)
    if not XMLData or not XMLNode or not XMLNode.ITEMPOOL then return nil end
    local entry = nil
    if ref and ref.name and ref.name ~= "" and XMLData.GetEntryByName then
        pcall(function() entry = XMLData.GetEntryByName(XMLNode.ITEMPOOL, ref.name) end)
    end
    if not entry and XMLData.GetEntryById then
        pcall(function() entry = XMLData.GetEntryById(XMLNode.ITEMPOOL, id) end)
    end
    -- ITEMPOOL nodes do not necessarily have an explicit numeric id; on those
    -- REPENTOGON exposes their order. Pool 0 is the first entry.
    if not entry and XMLData.GetEntryByOrder then
        pcall(function() entry = XMLData.GetEntryByOrder(XMLNode.ITEMPOOL, id + 1) end)
    end
    return type(entry) == "table" and entry or nil
end

local function poolItemsFromXML(id, ref)
    local entry = xmlPoolEntry(id, ref)
    if not entry then return nil end

    -- itempools.xml children are normally returned as entry.item[]. Be a little
    -- defensive for REPENTOGON revisions/custom pools that expose a different
    -- child key.
    local candidates = {}
    local function appendChildren(value)
        if type(value) ~= "table" then return end
        -- A single child node may be returned directly rather than as an array.
        if normalizePoolItem(value) then
            candidates[#candidates + 1] = value
            return
        end
        for _, child in pairs(value) do
            if type(child) == "table" and normalizePoolItem(child) then
                candidates[#candidates + 1] = child
            end
        end
    end
    appendChildren(entry.item)
    appendChildren(entry.collectible)
    appendChildren(entry.poolitem)
    if #candidates == 0 then
        for key, value in pairs(entry) do
            if type(value) == "table" and key ~= "metadata" then appendChildren(value) end
        end
    end
    return copyPoolItems(candidates)
end

local function capturePool(pool, id, ref)
    if not id or id < 0 then return nil end
    if poolSnapshot[id] and #poolSnapshot[id] > 0 then return poolSnapshot[id] end

    local live = nil
    if pool then
        local ok, items = pcall(function() return pool:GetCollectiblesFromPool(id) end)
        if ok then live = copyPoolItems(items) end
    end
    local copy = live or poolItemsFromXML(id, ref)
    if copy and #copy > 0 then poolSnapshot[id] = copy end
    return copy
end

function M.PrimePoolSnapshot(pool, refs)
    if type(refs) ~= "table" then return end
    for _, ref in ipairs(refs) do
        local numeric = type(ref) == "table" and tonumber(ref.id or ref.poolId) or tonumber(ref)
        if numeric and numeric >= 0 then capturePool(pool, numeric, ref) end
    end
end
function M.Resolve(token)
    local id = tonumber(token)
    if not id and type(token)=="string" then id=Isaac.GetItemIdByName(token) end
    return id and id>0 and id or nil
end
function M.Valid(g)
    if type(g)~="table" then return false end
    if g.kind=="fixed" then return type(g.token)=="string" and g.token~="" end
    return g.kind=="random" and type(g.pools)=="table" and type(g.excluded)=="table"
end
function M.Copy(g)
    if type(g)~="table" then return nil end
    local out={}
    for k,v in pairs(g) do out[k]=type(v)=="table" and M.Copy(v) or v end
    return out
end
function M.Key(g)
    if type(g)=="table" and g.kind=="random" and type(g.excluded)=="table" and type(g.pools)~="table" then
        local parts={"random_trinket",tostring(g.delivery or "normal")}
        for _,token in ipairs(g.excluded) do parts[#parts+1]="exclude:"..tostring(token) end
        table.sort(parts)
        return table.concat(parts,"|")
    end
    if not M.Valid(g) then return "" end
    if g.kind=="fixed" then return "fixed:"..g.token..":"..tostring(g.delivery or "normal") end
    local parts={g.modEnabled==false and "mod:off" or "mod:on"}
    for _,p in ipairs(g.pools) do parts[#parts+1]="pool:"..tostring(p.name or p.id)..":"..tostring(p.off==true) end
    for _,token in ipairs(g.excluded) do parts[#parts+1]="exclude:"..token end
    table.sort(parts)
    return table.concat(parts,"|")
end
function M.Label(g)
    if g and g.kind=="fixed" then
        local suffix=g.delivery=="pocket" and " [POCKET]" or ""
        return "GIVE ITEM: "..tostring(g.name or g.token)..suffix
    end
    return "GIVE ITEM: RANDOM"
end
function M.PoolID(ref)
    local numeric=tonumber(ref.id)
    local vanillaCount=tonumber(ItemPoolType.NUM_ITEMPOOLS or 0) or 0

    -- Built-in pools have stable ItemPoolType IDs. Resolve those numerically;
    -- GetPoolIdByName is intended for named/custom pools and may return nil for
    -- vanilla names such as "treasure" or "shop".
    if numeric and numeric>=0 and (vanillaCount<=0 or numeric<vanillaCount) then
        return numeric
    end

    -- Mod/custom pool IDs can move depending on the enabled mods, so prefer
    -- their stable XML name when one is available.
    if ref.name and ref.name~="" then
        local id=Isaac.GetPoolIdByName(ref.name)
        if id and id>=0 then return id end
        return nil -- Removed/renamed mod pool must not resolve to a different pool.
    end
    return numeric
end
function M.PoolItems(pool, ref)
    local id=M.PoolID(ref)
    if not id or id<0 then return nil end
    return capturePool(pool, id, ref)
end
function M.Candidates(g,game,blocked,player)
    if not M.Valid(g) then return {} end
    local config=Isaac.GetItemConfig()
    local function owned(id)
        if not player or not id then return false end
        local ok, has = pcall(function() return player:HasCollectible(id, true) end)
        return ok and has == true
    end
    if g.kind=="fixed" then
        local id=M.Resolve(g.token)
        return id and config:GetCollectible(id) and not owned(id) and not (blocked and blocked(id)) and {{id=id,weight=1}} or {}
    end
    local pool=game:GetItemPool()
    local excluded, found = {}, {}
    for _,token in ipairs(g.excluded) do local id=M.Resolve(token); if id then excluded[id]=true end end
    local vanillaLimit=tonumber(CollectibleType.NUM_COLLECTIBLES) or 734
    local function add(id,weight)
        if not id or id<=0 or excluded[id] or owned(id) or (g.modEnabled==false and id>=vanillaLimit)
            or (blocked and blocked(id)) or not config:GetCollectible(id) then return end
        if blocked then
            local ok,can=pcall(function() return pool:CanSpawnCollectible(id,false) end)
            if ok and not can then return end
        end
        -- An item in multiple enabled pools remains one candidate.
        found[id]=math.max(found[id] or 0,math.max(0,weight or 1))
    end
    for _,ref in ipairs(g.pools) do
        if not ref.off then
            for _,item in ipairs(M.PoolItems(pool,ref) or {}) do
                add(item.itemID,item.initialWeight or item.weight or 1)
            end
        end
    end
    if g.modEnabled~=false then
        for id=vanillaLimit,config:GetCollectibles().Size-1 do add(id,1) end
    end
    local out={}
    for id,weight in pairs(found) do if weight>0 then out[#out+1]={id=id,weight=weight} end end
    table.sort(out,function(a,b) return a.id<b.id end)
    return out
end
local pendingPocket = {}
function M.Give(p,g,game,roll,blocked)
    local choices=M.Candidates(g,game,blocked,p)
    if #choices==0 then
        Isaac.DebugString("[Challenge Maker] GIVE ITEM: no eligible item; reward skipped.")
        return false
    end
    local id=choices[1].id
    if g.kind=="random" then
        local rng=RNG()
        rng:SetSeed((game:GetSeeds():GetStartSeed()+roll*104729)%2147483646+1,35)
        local total=0
        for _,v in ipairs(choices) do total=total+v.weight end
        local pick=rng:RandomFloat()*total
        for _,v in ipairs(choices) do
            pick=pick-v.weight
            if pick<0 then id=v.id; break end
        end
    end
    if g.kind=="fixed" and g.delivery=="pocket" and ActiveSlot and ActiveSlot.SLOT_POCKET then
        -- AddCollectible cannot create a pocket-active slot on characters that
        -- did not start with one. SetPocketActiveItem is the native API made
        -- for assigning that slot to any character.
        p:SetPocketActiveItem(id,ActiveSlot.SLOT_POCKET,true)
        pendingPocket[GetPtrHash(p)]=id
    else
        p:AddCollectible(id,0,true,ActiveSlot and ActiveSlot.SLOT_PRIMARY or 0)
    end
    return true
end
function M.ReassertPocket(p)
    if not p or not ActiveSlot or not ActiveSlot.SLOT_POCKET then return end
    local key=GetPtrHash(p)
    local id=pendingPocket[key]
    if not id then return end
    pendingPocket[key]=nil
    -- EvaluateItems may rebuild active slots in the same conditions tick.
    -- Reassert once afterwards; do not keep forcing the slot on later frames.
    p:SetPocketActiveItem(id,ActiveSlot.SLOT_POCKET,true)
end
function M.ValidTrinket(g)
    if type(g)~="table" or (g.delivery~="normal" and g.delivery~="smelted") then return false end
    if g.kind=="fixed" then return type(g.token)=="string" and g.token~="" end
    return g.kind=="random" and type(g.excluded)=="table"
end
function M.ResolveTrinket(token)
    local id=tonumber(token)
    if not id and type(token)=="string" then id=Isaac.GetTrinketIdByName(token) end
    return id and id>0 and id or nil
end
function M.TrinketLabel(g)
    return "GIVE TRINKET: "..tostring(g and (g.kind=="random" and "RANDOM" or g.name or g.token) or "TRINKET")..
        (g and g.delivery=="smelted" and " [SMELTED]" or " [NORMAL]")
end
function M.TrinketCandidates(g)
    if type(g)~="table" or g.kind~="random" or type(g.excluded)~="table" then return {} end
    local excluded={}
    for _,token in ipairs(g.excluded) do local id=M.ResolveTrinket(token);if id then excluded[id]=true end end
    local list={};local config=Isaac.GetItemConfig();local entries=config:GetTrinkets()
    for id=1,(tonumber(entries and entries.Size) or 1)-1 do
        if not excluded[id] and config:GetTrinket(id) then list[#list+1]={id=id,weight=1} end
    end
    return list
end
function M.GiveTrinket(p,g,game,roll)
    if not M.ValidTrinket(g) then return false end
    local id=M.ResolveTrinket(g.token)
    if g.kind=="random" then
        local choices=M.TrinketCandidates(g)
        if #choices==0 then Isaac.DebugString("[Challenge Maker] GIVE TRINKET: no eligible trinket; reward skipped.");return false end
        local rng=RNG();rng:SetSeed(((game and game:GetSeeds():GetStartSeed() or 1)+(tonumber(roll) or 1)*130363)%2147483646+1,35)
        id=choices[rng:RandomInt(#choices)+1].id
    end
    if not id or not Isaac.GetItemConfig():GetTrinket(id) then return false end
    if g.delivery=="smelted" then p:AddSmeltedTrinket(id,true)
    else p:AddTrinket(id,true) end
    return true
end
function M.SpawnTrinket(p,g,game,roll)
    if not M.ValidTrinket(g) then return false end
    local id=M.ResolveTrinket(g.token)
    if g.kind=="random" then
        local choices=M.TrinketCandidates(g)
        if #choices==0 then return false end
        local rng=RNG();rng:SetSeed((game:GetSeeds():GetStartSeed()+(tonumber(roll) or 1)*130363)%2147483646+1,35)
        id=choices[rng:RandomInt(#choices)+1].id
    end
    if not id or not Isaac.GetItemConfig():GetTrinket(id) then return false end
    local seed=math.max(1,(game:GetRoom():GetSpawnSeed()+(tonumber(roll) or 1)*8191)%2147483647)
    game:Spawn(EntityType.ENTITY_PICKUP,PickupVariant.PICKUP_TRINKET,p.Position,Vector.Zero,p,id,seed)
    return true
end
function M.Spawn(p,g,game,roll,blocked)
    local choices=M.Candidates(g,game,blocked,p)
    if #choices==0 then
        Isaac.DebugString("[Challenge Maker] SPAWN ITEM: no eligible item; reward skipped.")
        return false
    end
    local id=choices[1].id
    if g.kind=="random" then
        local rng=RNG()
        rng:SetSeed((game:GetSeeds():GetStartSeed()+roll*104729)%2147483646+1,35)
        local total=0
        for _,v in ipairs(choices) do total=total+v.weight end
        local pick=rng:RandomFloat()*total
        for _,v in ipairs(choices) do
            pick=pick-v.weight
            if pick<0 then id=v.id; break end
        end
    end
    local room=game:GetRoom()
    local pos=room:GetCenterPos()
    local spawned=Isaac.Spawn(EntityType.ENTITY_PICKUP, PickupVariant.PICKUP_COLLECTIBLE, id, pos, Vector.Zero, nil)
    -- Pedestals created by a Conditions SPAWN ITEM action are rewards generated
    -- by Challenge Maker, not natural items the player found. Mark the actual
    -- entity so GRAB ITEM can explicitly ignore it even when the player later
    -- picks it up by hand.
    if spawned then
        local data=spawned:GetData()
        data.ChallengeMakerSpawnItem=true
    end
    return true
end
return M

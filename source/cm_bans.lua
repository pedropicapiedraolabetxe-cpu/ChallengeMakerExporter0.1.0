-- Shared by Challenge Maker and its standalone exporter. Requires REPENTOGON.
local Bans = {}
local MOD_ITEMS_POOL_ID = -1000
local MOD_ITEMS_POOL_NAME = "__challenge_maker_mod_items__"
local function isExternalModSource(sourceId)
    if sourceId == nil then return false end
    local sid = tostring(sourceId)
    if sid == "" or sid == "0" or sid == "nil" then return false end
    local ok, modInfo = pcall(function() return XMLData.GetModById(sid) end)
    return ok and type(modInfo) == "table" and next(modInfo) ~= nil
end

local names = {"treasure", "shop", "boss", "devil", "angel", "secret", "library",
    "shellGame", "goldenChest", "redChest", "beggar", "demonBeggar", "curse",
    "keyMaster", "batteryBum", "momsChest", "greedTreasure", "greedBoss",
    "greedShop", "greedDevil", "greedAngel", "greedCurse", "greedSecret",
    "craneGame", "ultraSecret", "bombBum", "planetarium", "oldChest",
    "babyShop", "woodenChest", "rottenBeggar"}

function Bans.Catalog()
    local entries = {}
    local count = #names
    local ok, n = pcall(function() return Game():GetItemPool():GetNumItemPools() end)
    if ok then count = math.max(count, n) end
    for id = 0, count - 1 do
        local name = names[id + 1]
        if not name then
            local found, node = pcall(function() return XMLData.GetEntryById(XMLNode.ITEMPOOL, id) end)
            name = found and node and node.name or nil
        end
        local label = name or ("CUSTOM " .. id)
        label = label:gsub("(%l)(%u)", "%1 %2"):upper()
        entries[#entries + 1] = {id=id, poolId=id, poolName=name,
            name="POOL: " .. label, lower=("pool " .. label .. " " .. (name or "")):lower()}
    end
    -- Virtual pool: every collectible supplied by an enabled mod. This is not
    -- an ItemPoolType; it is expanded into individual banned IDs in Build().
    entries[#entries + 1] = {id=MOD_ITEMS_POOL_ID, poolId=MOD_ITEMS_POOL_ID, poolName=MOD_ITEMS_POOL_NAME,
        name="POOL: MOD ITEMS", lower="pool mod items modded custom mods"}
    return entries
end

function Bans.Attach(mod, game, getConfig)
    local self = {set={}, config=nil, membership={}}
    local function resolve(token)
        local id = tonumber(token)
        if not id and type(token) == "string" then id = Isaac.GetItemIdByName(token) end
        return id and id > 0 and id or nil
    end
    function self:Build(config)
        self.config = config
        self.set = {}
        if not config then return self.set end
        for _, token in ipairs(config.bannedItemTokens or config.banned or {}) do
            local id = resolve(token)
            if id then self.set[id] = true end
        end
        for _, id in ipairs(config.bannedItems or {}) do
            id = resolve(id)
            if id then self.set[id] = true end
        end
        local pool = game:GetItemPool()
        for _, ref in ipairs(config.bannedPools or {}) do
            local id = type(ref) == "table" and tonumber(ref.id) or tonumber(ref)
            local refName = type(ref) == "table" and tostring(ref.name or "") or ""
            local isModItems = id == MOD_ITEMS_POOL_ID or refName == MOD_ITEMS_POOL_NAME

            if isModItems then
                -- REPENTOGON's XMLData tags entries originating from content XML
                -- supplied by mods with sourceid. Expand the virtual pool now so
                -- every path (Chaos, Death Certificate, Spindown, direct spawn,
                -- inventory grant, etc.) is handled by the same global ban set.
                local vanillaLimit = tonumber(CollectibleType.NUM_COLLECTIBLES or 734) or 734
                local okCount, count = pcall(function() return XMLData.GetNumEntries(XMLNode.ITEM) end)
                if okCount and type(count) == "number" then
                    for order = 1, count do
                        local okEntry, entry = pcall(function() return XMLData.GetEntryByOrder(XMLNode.ITEM, order) end)
                        if okEntry and type(entry) == "table" then
                            local itemID = tonumber(entry.id)
                            local sourceId = entry.sourceid
                            if itemID and itemID > 0 and isExternalModSource(sourceId) then
                                self.set[itemID] = true
                            end
                        end
                    end
                else
                    -- Defensive fallback if XMLData is unavailable: modded
                    -- collectibles are allocated after the vanilla range.
                    local cfg = Isaac.GetItemConfig()
                    for itemID = vanillaLimit, cfg:GetCollectibles().Size - 1 do
                        local item = cfg:GetCollectible(itemID)
                        if item then self.set[itemID] = true end
                    end
                end
            else
                if type(ref) == "table" and ref.name then
                    local named = Isaac.GetPoolIdByName(ref.name)
                    if named and named >= 0 then id = named end
                end
                if id and id >= 0 then
                    -- Never lose membership just because weight dropped to zero or
                    -- RemoveCollectible was already called during this run.
                    self.membership[id] = self.membership[id] or {}
                    for _, item in ipairs(pool:GetCollectiblesFromPool(id)) do
                        if item.itemID > 0 then self.membership[id][item.itemID] = true end
                    end
                    for itemID in pairs(self.membership[id]) do self.set[itemID] = true end
                end
            end
        end
        return self.set
    end
    function self:Sync()
        local config = getConfig()
        if config ~= self.config then self:Build(config) end
        return config ~= nil and next(self.set) ~= nil
    end
    function self:Blocked(id)
        return self:Sync() and self.set[id] == true
    end
    function self:Replacement(seed, poolID)
        local pool = game:GetItemPool()
        local options = {}
        if poolID and poolID >= 0 then
            for _, item in ipairs(pool:GetCollectiblesFromPool(poolID)) do
                if not self.set[item.itemID] and item.weight > 0
                    and pool:CanSpawnCollectible(item.itemID, false) then
                    options[#options + 1] = item.itemID
                end
            end
        end
        if #options == 0 then
            local cfg = Isaac.GetItemConfig()
            for id = 1, cfg:GetCollectibles().Size - 1 do
                local item = cfg:GetCollectible(id)
                if item and not item.Hidden and not self.set[id]
                    and pool:CanSpawnCollectible(id, false) then options[#options + 1] = id end
            end
        end
        if #options == 0 then return 0 end
        return options[(math.abs(tonumber(seed) or 0) % #options) + 1]
    end
    function self:PedestalReplacement(id, seed)
        if self.spindownUntil and game:GetFrameCount() <= self.spindownUntil then
            local cfg = Isaac.GetItemConfig()
            for candidate = id - 1, 1, -1 do
                local item = cfg:GetCollectible(candidate)
                if item and not item.Hidden and not self.set[candidate] then return candidate end
            end
            return 0
        end
        return self:Replacement(seed)
    end
    function self:CleanPickup(pickup)
        if not pickup or pickup.Variant ~= PickupVariant.PICKUP_COLLECTIBLE
            or not self:Blocked(pickup.SubType) then return end
        -- Spindown must walk downward through IDs, not roll a random pool item.
        local id = self:PedestalReplacement(pickup.SubType, pickup.InitSeed)
        if id == 0 then pickup:Remove() return end
        local options, price, auto, touched = pickup.OptionsPickupIndex, pickup.Price, pickup.AutoUpdatePrice, pickup.Touched
        pickup:Morph(EntityType.ENTITY_PICKUP, PickupVariant.PICKUP_COLLECTIBLE, id, true, true, true)
        pickup.OptionsPickupIndex, pickup.Price, pickup.AutoUpdatePrice, pickup.Touched = options, price, auto, touched
    end
    local function add(callback, fn, filter)
        mod:AddPriorityCallback(callback, CallbackPriority.LATE, fn, filter)
    end
    add(ModCallbacks.MC_POST_GET_COLLECTIBLE, function(_, id, poolID, decrease, seed)
        if self:Blocked(id) then
            local replacement = self:Replacement(seed, poolID)
            -- 0 is handled by vanilla's exhausted-pool fallback. Spawn/Add guards
            -- below also reject a banned Breakfast fallback, without recursion.
            return replacement
        end
    end)
    add(ModCallbacks.MC_PRE_ENTITY_SPAWN, function(_, kind, variant, id, pos, vel, spawner, seed)
        if kind == EntityType.ENTITY_PICKUP and variant == PickupVariant.PICKUP_COLLECTIBLE and self:Blocked(id) then
            local replacement = self:PedestalReplacement(id, seed)
            if replacement > 0 then return {kind, variant, replacement, seed} end
            return {EntityType.ENTITY_EFFECT, EffectVariant.POOF01, 0, seed}
        end
    end)
    add(ModCallbacks.MC_POST_PICKUP_INIT, function(_, pickup) self:CleanPickup(pickup) end, PickupVariant.PICKUP_COLLECTIBLE)
    add(ModCallbacks.MC_POST_PICKUP_UPDATE, function(_, pickup) self:CleanPickup(pickup) end, PickupVariant.PICKUP_COLLECTIBLE)
    add(ModCallbacks.MC_PRE_PICKUP_COLLISION, function(_, pickup)
        if self:Blocked(pickup.SubType) then self:CleanPickup(pickup) return true end
    end, PickupVariant.PICKUP_COLLECTIBLE)
    add(ModCallbacks.MC_PRE_ADD_COLLECTIBLE, function(_, id)
        if self:Blocked(id) then return false end
    end)
    add(ModCallbacks.MC_PRE_USE_ITEM, function()
        if self:Sync() then self.spindownUntil = game:GetFrameCount() + 3 end
    end, CollectibleType.COLLECTIBLE_SPINDOWN_DICE)
    add(ModCallbacks.MC_POST_UPDATE, function()
        if not self:Sync() then return end
        -- Includes items initialized by native character/challenge XML before
        -- Lua knows which challenge is active, and direct inventory grants.
        for i = 0, game:GetNumPlayers() - 1 do
            local player = Isaac.GetPlayer(i)
            for id in pairs(self.set) do
                local count = player:GetCollectibleNum(id, true)
                for _ = 1, count do player:RemoveCollectible(id) end
            end
        end
        for _, entity in ipairs(Isaac.FindByType(EntityType.ENTITY_PICKUP, PickupVariant.PICKUP_COLLECTIBLE, -1, false, false)) do
            self:CleanPickup(entity:ToPickup())
        end
    end)
    return self
end

return Bans

-- Compatibility support for packs made by earlier Challenge Maker exporters.
local M = {}

function M.Attach(mod, currentConfig, fixBannedPickups, fixSize)
    local cards, trinkets = nil, nil
    local bannedFor = nil

    local function banned(config)
        if bannedFor == config then return cards, trinkets end
        cards, trinkets = {}, {}
        bannedFor = config
        if not config then return cards, trinkets end
        local banModPickups, banModTrinkets = false, false
        for _, entry in ipairs(config.bannedPickups or {}) do
            local id = tonumber(entry.token) or tonumber(entry.id)
            if entry.kind == 'mod_pickups' then banModPickups = true
            elseif entry.kind == 'mod_trinkets' then banModTrinkets = true
            elseif entry.kind == 'card' and id then cards[id] = true
            elseif entry.kind == 'trinket' and id then trinkets[id] = true end
        end
        if banModPickups or banModTrinkets then
            for _, pair in ipairs({{XMLNode.CARD, cards, banModPickups}, {XMLNode.TRINKET, trinkets, banModTrinkets}}) do
                if pair[3] then
                    local count = XMLData.GetNumEntries(pair[1])
                    for order = 1, count do
                        local node = XMLData.GetEntryByOrder(pair[1], order)
                        if node and node.sourceid then
                            local ok, source = pcall(XMLData.GetModById, tostring(node.sourceid))
                            local id = tonumber(node.id)
                            if id and ok and type(source) == 'table' and next(source) then pair[2][id] = true end
                        end
                    end
                end
            end
        end
        return cards, trinkets
    end

    local function replacement(variant, original, seed)
        local bannedCards, bannedTrinkets = banned(currentConfig())
        local goldenFlag = TrinketType.TRINKET_GOLDEN_FLAG or 32768
        local kind, blocked, flag
        if variant == PickupVariant.PICKUP_TAROTCARD then
            kind, blocked, flag = XMLNode.CARD, bannedCards[original], 0
        elseif variant == PickupVariant.PICKUP_TRINKET then
            kind, blocked, flag = XMLNode.TRINKET, bannedTrinkets[original % goldenFlag], original >= goldenFlag and goldenFlag or 0
        end
        if not blocked then return false end
        local candidates = {}
        local root = Isaac.GetItemConfig()
        for order = 1, XMLData.GetNumEntries(kind) do
            local node = XMLData.GetEntryByOrder(kind, order)
            local id = node and tonumber(node.id)
            if id and id > 0 and not (variant == PickupVariant.PICKUP_TAROTCARD and bannedCards[id] or variant == PickupVariant.PICKUP_TRINKET and bannedTrinkets[id]) then
                local cfg = variant == PickupVariant.PICKUP_TAROTCARD and root:GetCard(id) or root:GetTrinket(id)
                if cfg then
                    local available = true
                    if cfg.IsAvailable then pcall(function() available = cfg:IsAvailable() end) end
                    if available then candidates[#candidates + 1] = id end
                end
            end
        end
        if #candidates == 0 then return true end
        return true, candidates[(math.abs(tonumber(seed) or 0) % #candidates) + 1] + flag
    end

    if fixBannedPickups then
        function mod:OnExportedBannedPickup(pickup)
            if not currentConfig() or not pickup then return end
            local blocked, newId = replacement(pickup.Variant, tonumber(pickup.SubType) or 0, pickup.InitSeed)
            if not blocked then return end
            if not newId then pickup:Remove(); return end
            local price, options = pickup.Price, pickup.OptionsPickupIndex
            pickup:Morph(EntityType.ENTITY_PICKUP, pickup.Variant, newId, true, true, true)
            pickup.Price, pickup.OptionsPickupIndex = price, options
        end
        for _, variant in ipairs({PickupVariant.PICKUP_TAROTCARD, PickupVariant.PICKUP_TRINKET}) do
            mod:AddCallback(ModCallbacks.MC_POST_PICKUP_INIT, mod.OnExportedBannedPickup, variant)
            mod:AddCallback(ModCallbacks.MC_POST_PICKUP_UPDATE, mod.OnExportedBannedPickup, variant)
        end
    end

    if fixSize then
        local startupFrames = 0
        local function refreshSize()
            local config = currentConfig()
            if not config or not tonumber(config.sizeSteps) or Game():GetNumPlayers() < 1 then return end
            local player = Isaac.GetPlayer(0)
            player:AddCacheFlags(CacheFlag.CACHE_SIZE)
            player:EvaluateItems()
        end
        function mod:OnExportedSizeCache(player, flag)
            if flag ~= CacheFlag.CACHE_SIZE or not player then return end
            local config = currentConfig()
            local steps = math.floor(tonumber(config and config.sizeSteps) or 0)
            if steps ~= 0 then player.SpriteScale = player.SpriteScale * (steps > 0 and 1.25 ^ steps or 0.8 ^ (-steps)) end
        end
        mod:AddCallback(ModCallbacks.MC_EVALUATE_CACHE, mod.OnExportedSizeCache, CacheFlag.CACHE_SIZE)
        mod:AddCallback(ModCallbacks.MC_POST_GAME_STARTED, function(_, continued)
            startupFrames = 45
            refreshSize()
        end)
        mod:AddCallback(ModCallbacks.MC_POST_UPDATE, function()
            if startupFrames <= 0 then return end
            startupFrames = startupFrames - 1
            if startupFrames == 44 or startupFrames == 35 or startupFrames == 15 or startupFrames == 0 then
                refreshSize()
            end
        end)
    end
end

return M

-- Appended to generated main.lua: shares its mod, configs and ban policy.
do
    local json = require('json')
    local rulesByName = json.decode(exportedConditionsJSON)
    for name, rules in pairs(rulesByName) do
        if configsByName[name] then configsByName[name].conditions = rules end
    end
    local initializing = true
    local stopped = false
    local engine = include('cm_conditions')
    local guard = engine.Attach(mod, game, function()
        if stopped then return nil end
        return currentConfig()
    end, function() return initializing end, function(id) return bannedSet[id] == true end)
    mod:AddCallback(ModCallbacks.MC_POST_GAME_STARTED, function(_, continued)
        initializing = true
        stopped = false
        guard.Reset()
        local cfg = currentConfig()
        if cfg then
            if continued and mod:HasData() then
                local ok, saved = pcall(json.decode, mod:LoadData())
                if ok and type(saved)=='table' and saved.challenge == Isaac.GetChallenge()
                    and saved.seed == game:GetSeeds():GetStartSeed() then guard.Restore(saved.state) end
            end
            guard.ArmRunStart(not continued)
        end
        initializing = false
    end)
    mod:AddCallback(ModCallbacks.MC_PRE_GAME_EXIT, function(_, shouldSave)
        if shouldSave and currentConfig() then
            mod:SaveData(json.encode({challenge=Isaac.GetChallenge(), seed=game:GetSeeds():GetStartSeed(), state=guard.Snapshot()}))
        else mod:SaveData('{}') end
        stopped = true
    end)
end

-- General challenge settings, kept outside main.lua to preserve Lua's local limit.
local M = {}

M.fields = {
    {key="containers", label="RED CONTAINERS", max=24, group="health"},
    {key="red", label="RED HALF HEARTS", max=48, group="health"},
    {key="soul", label="SOUL HALF HEARTS", max=48, group="health"},
    {key="black", label="BLACK HALF HEARTS", max=48, group="health"},
    {key="bone", label="BONE HEARTS", max=12, group="health"},
    {key="rotten", label="ROTTEN HEARTS", max=12, group="health"},
    {key="coins", label="STARTING COINS", max=99},
    {key="bombs", label="STARTING BOMBS", max=99},
    {key="keys", label="STARTING KEYS", max=99},
    {key="activeCharge", label="ACTIVE CHARGE", max=99},
    {key="pocketCharge", label="POCKET ACTIVE CHARGE", max=99},
    {key="maxTime", label="MAX TIME (SECONDS)", max=999999},
    {key="maxLives", label="MAX LIVES (1 TO 99)", max=99, min=1},
}

M.curses = {
    {key="darkness", label="DARKNESS", flag="CURSE_OF_DARKNESS"},
    {key="lost", label="LOST", flag="CURSE_OF_THE_LOST"},
    {key="unknown", label="UNKNOWN", flag="CURSE_OF_THE_UNKNOWN"},
    {key="blind", label="BLIND", flag="CURSE_OF_BLIND"},
    {key="maze", label="MAZE", flag="CURSE_OF_MAZE"},
}

function M.ApplyStart(config, player)
    if not config or not player then return end
    local h = config.startHealth or {}
    local function set(getter, adder, target)
        local n = tonumber(target)
        if n == nil then return end
        n = math.max(0, math.floor(n))
        pcall(function() player[adder](player, n - player[getter](player)) end)
    end
    -- Set maximum first; red hearts cannot exceed the available capacity.
    set("GetMaxHearts", "AddMaxHearts", h.containers and h.containers * 2)
    set("GetHearts", "AddHearts", h.red)
    -- Black hearts share the soul-heart pool. Rebuild it once when either
    -- count is explicitly configured, to avoid retaining the character's old
    -- black hearts or counting them twice.
    if h.soul ~= nil or h.black ~= nil then
        set("GetSoulHearts", "AddSoulHearts", 0)
        pcall(function() player:AddSoulHearts(math.floor(tonumber(h.soul) or 0)) end)
        pcall(function() player:AddBlackHearts(math.floor(tonumber(h.black) or 0)) end)
    end
    set("GetBoneHearts", "AddBoneHearts", h.bone)
    set("GetRottenHearts", "AddRottenHearts", h.rotten)
    set("GetNumCoins", "AddCoins", config.startCoins)
    set("GetNumBombs", "AddBombs", config.startBombs)
    set("GetNumKeys", "AddKeys", config.startKeys)
    local charges=config.startCharges or {}
    for _,entry in ipairs({{key="activeCharge",slot=ActiveSlot.SLOT_PRIMARY},{key="pocketCharge",slot=ActiveSlot.SLOT_POCKET}}) do
        local charge=tonumber(charges[entry.key])
        if charge then pcall(function()
            if player:GetActiveItem(entry.slot)>0 then player:SetActiveCharge(math.max(0,math.floor(charge)),entry.slot) end
        end) end
    end
end

function M.ApplyCurses(config, level)
    if not config or not level then return end
    local choices=config.curseModes or {}
    local required, forbidden=0,0
    for _,curse in ipairs(M.curses) do
        local flag=LevelCurse and LevelCurse[curse.flag]
        if flag then
            if choices[curse.key]=="required" then required=required|flag
            elseif choices[curse.key]=="forbidden" then forbidden=forbidden|flag end
        end
    end
    if forbidden~=0 then level:RemoveCurses(forbidden) end
    if required~=0 then level:AddCurse(required,true) end
end

return M

-- Run-wide limits are isolated to keep main.lua below Lua's local-variable cap.
local M = {}

function M.Attach(mod, game, current)
    local state = {lives=1, elapsed=0, startFrame=0, expired=false}
    local function frame() return game:GetFrameCount() end
    local function primary(player)
        return player and game:GetNumPlayers()>0 and GetPtrHash(player)==GetPtrHash(Isaac.GetPlayer(0))
    end

    function M.Reset()
        state = {lives=1, elapsed=0, startFrame=frame(), expired=false}
    end

    function M.Restore(saved)
        if type(saved)~="table" then return end
        state.lives=math.max(1,math.floor(tonumber(saved.lives) or 1))
        state.elapsed=math.max(0,math.floor(tonumber(saved.elapsed) or 0))
        state.startFrame=frame()
        state.expired=saved.expired==true
    end

    function M.Snapshot()
        return {lives=state.lives,elapsed=state.elapsed+math.max(0,frame()-state.startFrame),expired=state.expired}
    end

    function M.Update()
        local cfg=current()
        if not cfg or state.expired then return end
        local seconds=tonumber(cfg.maxTime)
        if seconds and seconds>0 and game:GetNumPlayers()>0
            and state.elapsed+math.max(0,frame()-state.startFrame)>=seconds*30 then
            state.expired=true
            Isaac.GetPlayer(0):Kill()
        end
    end

    function mod:ChallengeMakerPreRevive(player)
        local cfg=current()
        if not cfg or not primary(player) then return end
        local maximum=tonumber(cfg.maxLives)
        if state.expired or (maximum and maximum>0 and state.lives>=maximum) then return false end
    end

    function mod:ChallengeMakerPostRevive(player)
        if current() and primary(player) then state.lives=state.lives+1 end
    end

    if ModCallbacks.MC_PRE_PLAYER_REVIVE and ModCallbacks.MC_POST_PLAYER_REVIVE then
        mod:AddCallback(ModCallbacks.MC_PRE_PLAYER_REVIVE,mod.ChallengeMakerPreRevive)
        mod:AddCallback(ModCallbacks.MC_POST_PLAYER_REVIVE,mod.ChallengeMakerPostRevive)
    end
    M.Reset()
    return M
end

return M

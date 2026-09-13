-- Shared by the editor and exported packs. No editor assets or globals required.
local M = {}
local mouseDown = Input.IsMouseBtnPressed
local keyDown, keyPressed = Input.IsButtonPressed, Input.IsButtonTriggered
local wheel = Input.GetMouseWheel
local function clamp(n,a,b) return math.max(a,math.min(b,n)) end
local function box(x,y,w,h,r,g,b,a)
    local c=KColor(r,g,b,a or 1)
    Isaac.DrawLine(Vector(x,y+h/2),Vector(x+w,y+h/2),c,c,math.floor(h))
end
local function text(s,x,y,scale) Isaac.RenderScaledText(s,x,y,scale,scale,1,1,1,1) end
function M.Wrap(value,width,scale)
    local lines={}
    value=tostring(value or ''):gsub('\r\n','\n'):gsub('\r','\n')
    for paragraph in (value..'\n'):gmatch('(.-)\n') do
        local line=''
        for word in paragraph:gmatch('%S+') do
            local candidate=line=='' and word or line..' '..word
            if Isaac.GetTextWidth(candidate)*scale<=width then line=candidate
            else
                if line~='' then lines[#lines+1]=line;line='' end
                for char in word:gmatch('[%z\1-\127\194-\244][\128-\191]*') do
                    if line~='' and Isaac.GetTextWidth(line..char)*scale>width then lines[#lines+1]=line;line='' end
                    line=line..char
                end
            end
        end
        lines[#lines+1]=line
    end
    return lines
end
function M.Area(value,x,y,w,h,state,followEnd)
    local scale,step=0.9,15
    local lines=M.Wrap(value,w-24,scale)
    local visible=math.max(1,math.floor(h/step))
    local maximum=math.max(0,#lines-visible)
    state.scroll=clamp(state.scroll or 0,0,maximum)
    if followEnd then state.scroll=maximum end
    local delta=0
    if wheel then local v=wheel();delta=v and v.Y or 0 end
    if keyPressed(Keyboard.KEY_UP,0) then delta=delta+1 end
    if keyPressed(Keyboard.KEY_DOWN,0) then delta=delta-1 end
    state.scroll=clamp(state.scroll-delta*3,0,maximum)
    local pos=Isaac.WorldToScreen(Isaac.ScreenToWorld(Input.GetMousePosition(false)))
    if maximum>0 and mouseDown(0) and pos.X>=x+w-12 and pos.X<=x+w and pos.Y>=y and pos.Y<=y+h then
        state.scroll=clamp(math.floor((pos.Y-y)/h*(maximum+visible)-visible/2),0,maximum)
    end
    state.scroll=math.floor(state.scroll)
    for i=1,visible do
        local line=lines[state.scroll+i]
        if line then text(line,x,y+(i-1)*step,scale) end
    end
    if maximum>0 then
        box(x+w-8,y,6,h,0.2,0.2,0.2)
        local thumb=math.max(12,h*visible/#lines)
        box(x+w-8,y+(h-thumb)*state.scroll/maximum,6,thumb,0.8,0.8,0.8)
    end
end
function M.Attach(mod,getConfig,manualStart)
    local state={open=false,scroll=0,wasDown=false,closing=false,hudWasVisible=nil}
    local lastChallenge=nil
    local mainMenuSeen=true
    local function setHUDVisible(visible)
        pcall(function() Game():GetHUD():SetVisible(visible) end)
    end
    local function restoreHUD()
        if state.hudWasVisible ~= nil then
            setHUDVisible(state.hudWasVisible)
            state.hudWasVisible=nil
        end
    end
    local function hideHUD()
        if state.hudWasVisible == nil then
            local ok, visible=pcall(function() return Game():GetHUD():IsVisible() end)
            if ok then state.hudWasVisible=visible==true
            else state.hudWasVisible=true end
        end
        setHUDVisible(false)
    end
    function state.Blocked() return state.open or state.closing end
    function state.Close()
        state.open=false;state.closing=false
        restoreHUD()
    end
    function state.Start(_, continued)
        restoreHUD()
        local challenge=Isaac.GetChallenge()
        local isReset=lastChallenge~=nil and challenge==lastChallenge and not mainMenuSeen
        lastChallenge=challenge
        mainMenuSeen=false
        local cfg=getConfig()
        state.value=cfg and tostring(cfg.description or '') or ''
        state.open=continued~=true and not isReset and state.value:find('%S')~=nil
        state.closing=false;state.scroll=0;state.wasDown=mouseDown(0)
        if state.open then hideHUD() end
    end
    if not manualStart then mod:AddCallback(ModCallbacks.MC_POST_GAME_STARTED,state.Start) end
    mod:AddCallback(ModCallbacks.MC_MAIN_MENU_RENDER,function()
        mainMenuSeen=true
        state.Close()
    end)
    mod:AddCallback(ModCallbacks.MC_PRE_GAME_EXIT,state.Close)
    mod:AddCallback(ModCallbacks.MC_PRE_UPDATE,function()
        if state.open then
            hideHUD()
            return true
        end
        -- Keep swallowing the click-release frame, but the HUD was already
        -- restored by the X and must not be hidden again here.
        if state.closing then return true end
    end)
    mod:AddCallback(ModCallbacks.MC_INPUT_ACTION,function(_,entity,hook,action)
        if not state.Blocked() then return end
        -- This includes ACTION_RESTART, preventing R/Retry while the panel is open.
        if hook==InputHook.GET_ACTION_VALUE then return 0 end
        return false
    end)
    mod:AddCallback(ModCallbacks.MC_POST_RENDER,function()
        local down=mouseDown(0)
        if not state.open then
            -- Do not pass the click that closed the panel through to gameplay.
            if state.closing and not down then state.closing=false end
            state.wasDown=down;return
        end
        local w,h=Isaac.GetScreenWidth(),Isaac.GetScreenHeight()
        -- An opaque full-screen layer also covers UI drawn by other mods before us.
        hideHUD()
        box(0,0,w,h,0,0,0,1)
        box(12,12,w-24,h-24,0.35,0.35,0.35)
        box(14,14,w-28,h-28,0.07,0.07,0.09)
        text('DESCRIPTION',28,25,1)
        local x,y=w-49,21
        box(x,y,25,24,0.8,0.06,0.06)
        text('X',x+9,y+6,1)
        M.Area(state.value,28,60,w-56,h-99,state)
        text('SCROLL: MOUSE WHEEL / UP / DOWN',28,h-30,0.65)
        local p=Isaac.WorldToScreen(Isaac.ScreenToWorld(Input.GetMousePosition(false)))
        if down and not state.wasDown and p.X>=x and p.X<=x+25 and p.Y>=y and p.Y<=y+24 then
            state.open=false;state.closing=true
            restoreHUD()
        end
        state.wasDown=down
    end)
    return state
end
return M

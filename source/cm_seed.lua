-- Isaac-style, eight-character run seeds (displayed by the game as XXXX XXXX).
local M = {}

function M.Normalize(input)
    if type(input)~="string" then return nil end
    local code=input:upper():gsub("%s+", "")
    if #code~=8 or not code:match("^[A-Z0-9]+$") then return nil end
    return code
end

function M.Parse(input)
    local code=M.Normalize(input)
    if not code or not Seeds or not Seeds.String2Seed then return nil end
    local formatted=code:sub(1,4).." "..code:sub(5)
    if Seeds.IsSpecialSeed then
        local ok,special=pcall(Seeds.IsSpecialSeed,formatted)
        if ok and special then return nil end
    end
    local valid=false
    if Seeds.IsStringValidSeed then
        local ok,result=pcall(Seeds.IsStringValidSeed,formatted)
        valid=ok and result==true
        if not valid then
            ok,result=pcall(Seeds.IsStringValidSeed,code)
            valid=ok and result==true
        end
    else valid=true end
    if not valid then return nil end
    for _,candidate in ipairs({formatted,code}) do
        local ok,number=pcall(Seeds.String2Seed,candidate)
        if ok and type(number)=="number" and number>0 then
            if not Seeds.Seed2String then return code,number end
            local converted,stringValue=pcall(Seeds.Seed2String,number)
            if converted and M.Normalize(stringValue)==code then return code,number end
        end
    end
    return nil
end

return M

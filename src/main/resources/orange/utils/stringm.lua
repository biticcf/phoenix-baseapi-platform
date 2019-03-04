local string_gsub = string.gsub
local string_find = string.find
local table_insert = table.insert

local _M = {}

function _M.trim_all(str)
    if not str or str == "" then return "" end
    local result = string_gsub(str, " ", "")
    return result
end

function _M.strip(str)
    if not str or str == "" then return "" end
    local result = string_gsub(str, "^ *", "")
    result = string_gsub(result, "( *)$", "")
    return result
end

function _M.split(str,sep)
    if not str or str == "" then return {} end
    if not sep or sep == "" then return { str } end
    local sep, fields = sep or "\t", {}
    local pattern = string.format("([^%s]+)", sep)
    str:gsub(pattern, function(c) fields[#fields+1] = c end)
    return fields
end

function _M.replace(source,pattern,replace)
    return (string:gsub(source,pattern,replace))
end

function _M.startswith(str, substr)
    if str == nil or substr == nil then
        return false
    end
    if string_find(str, substr) ~= 1 then
        return false
    else
        return true
    end
end

function _M.endswith(str, substr)
    if str == nil or substr == nil then
        return false
    end
    local str_reverse = string.reverse(str)
    local substr_reverse = string.reverse(substr)
    if string.find(str_reverse, substr_reverse) ~= 1 then
        return false
    else
        return true
    end
end

return _M

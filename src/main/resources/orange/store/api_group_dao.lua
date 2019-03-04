local ipairs = ipairs
local table_insert = table.insert
local table_concat = table.concat
local type = type
local xpcall = xpcall
local orange_db = require("orange.store.orange_db")


local _M = {
    desc = "store[api_group] access & local cache manage"
}

function _M.get_api_groups(store)
    local api_groups, err = store:query({
        sql = "select * from api_group where `status` = 0 order by `name` asc",
        params = {}
    })

    if not err and api_groups and type(api_groups) == "table" and #api_groups > 0 then
        return api_groups
    end

    return nil
end

-- ########################### local cache init start #############################
function _M.init_api_groups(store)
    local api_groups = _M.get_api_groups(store)
    if not api_groups or not api_groups.name then
        ngx.log(ngx.ERR, "error to find api_groups from storage when initializing api_group!")
        return false
    end
    
    local success, err, forcible = orange_db.set_json("api_groups", api_groups)
    if err or not success then
        ngx.log(ngx.ERR, "init api_group error, err:", err)
        return false
    end
    
    return true
end

return _M

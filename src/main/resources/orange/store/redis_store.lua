local type = type
local cjson = require("cjson")
local redis = require("resty.redis")
local redis_db = require("orange.store.redis_db")
local Store = require("orange.store.base")
local stringy = require("orange.utils.stringy")

local RedisStore = Store:extend()

function RedisStore:new(options)
    self._name = options.name or "store_redis"
    RedisStore.super.new(self, self._name)
    self.store_type = "redis"
    self.data = {}
    self.db = redis_db:new(options)
end

function RedisStore:queryHostByUri(uri)
    if not uri or uri == "" or uri == "/" then 
        ngx.log(ngx.ERR, "RedisStore:queryHostByUri, error: uri is nil!")
        return nil
    end
    
    if string.find(uri, "/") == 1 then
        uri = string.sub(uri, 2)
    end
    
    local host, port, tree, err
    
    local ctxes = stringy.split(uri, "/")
    local tree_key = "API_URI_TREE_" .. tostring(ctxes[1])
    
    tree, err = self.db:get(tree_key)
    if not tree or err or type(tree) == 'userdata' then
        ngx.log(ngx.ERR, "RedisStore:queryHostByUri.get[" .. tostring(tree_key) .. "], error:", err)
        return nil
    end
    
    local treeJson, err = cjson.decode(tree)
    if err or not treeJson then
        ngx.log(ngx.ERR, "RedisStore:queryHostByUri.decode[" .. tostring(tree) .. "], error:", err)
        return nil
    end
    
    local uriId, localJson, tmpJson, newUrl
    local placeholders = {}
    local find = false;
    -- 遍历查找uri匹配的id(pairs用于<key,value>,ipairs用于数字索引)
    localJson = treeJson
    for i, _uri in pairs(ctxes) do
        tmpJson = localJson[_uri]
        -- 占位符匹配
        if not tmpJson then
            tmpJson = localJson["_0_"]
            if tmpJson and type(tmpJson) == "table" then
                table.insert(placeholders, #placeholders + 1, _uri)
            end
        end
        localJson = tmpJson
        
        if not tmpJson or type(tmpJson) ~= "table" then break end
    end
    
    if localJson and type(localJson) == "table" then
        uriId = localJson.id
    end
    
    if not uriId or uriId == -1 or type(uriId) ~= "number" then
        ngx.log(ngx.ERR, "RedisStore:queryHostByUri not find uri id!")
        return nil
    end
    
    local uri_key = "API_VER_ITEM_" .. tostring(uriId)
    local uriStr, err = self.db:get(uri_key)
    if not uriStr then
        ngx.log(ngx.ERR, "RedisStore:queryHostByUri.get[" .. tostring(uri_key) .. "], error:", err)
        return nil
    end
    
    local uriJson, err = cjson.decode(uriStr)
    if not uriJson then
        ngx.log(ngx.ERR, "RedisStore:queryHostByUri.decode[" .. tostring(uriStr) .. "], error:", err)
        return nil
    end
    
    local apiUrl, err = uriJson["apiUrl"]
    if not apiUrl or apiUrl == "" or string.find(apiUrl, "http://") ~= 1 then
        ngx.log(ngx.ERR, "RedisStore:queryHostByUri.apiUrl[" .. tostring(apiUrl) .. "], error:", err)
        return nil
    end
    
    -- 去掉http://
    apiUrl = string.sub(apiUrl, 8)
    local apiHostPort = apiUrl
    newUrl = ""
    local idx = string.find(apiUrl, "/")
    if idx and idx > 0 then
        apiHostPort = string.sub(apiUrl, 1, idx - 1)
        -- 包含/
        newUrl = string.sub(apiUrl, idx)
    end
    
    local idx0 = string.find(newUrl, "?")
    if idx0 then
        newUrl = string.sub(newUrl, 1, idx0 - 1)
    end
    
    -- 替换占位符
    local pidx = string.find(newUrl, "{{")
    if pidx and type(uriId) == "number" and pidx >= 1 then
        local ctxes_new = stringy.split(newUrl, "/")
        local tmlUrl = ""
        local indx = 0
        for i, v in ipairs(ctxes_new) do
            if v and string.find(v, "{{") == 1 then
                indx = indx + 1
                local _tmpV = placeholders[indx];
                if not _tmpV then
                    _tmpV = ctxes_new[i]
                end
                tmlUrl = tmlUrl .. "/" .. tostring(_tmpV)
            elseif v then
                tmlUrl = tmlUrl .. "/" .. tostring(ctxes_new[i])
            else
            end
        end
        newUrl = tmlUrl
    end
    
    local idx1 = string.find(apiHostPort, ":")
    if not idx1 then
        host = apiHostPort
        port = 80
    else
        host = string.sub(apiHostPort, 1, idx1 - 1)
        port = tonumber(string.sub(apiHostPort, idx1 + 1))
    end
    
    return host, port, uriId, newUrl
end

function RedisStore:queryUriMethod(key, field)
    if not key or not field then
        ngx.log(ngx.ERR, "RedisStore:queryUriMethod(" .. tostring(key) .. "," .. tostring(field) .. ")")
        ngx.log(ngx.ERR, "param error")
        return nil
    end
    return self.db:hget(key,field)
end

function RedisStore:rate_limiting(key,expire_time)
    if not key or not expire_time then
        ngx.log(ngx.ERR, "RedisStore:rate_limiting(" .. key .. ",".. expire_time ..")")
        ngx.log(ngx.ERR, "param error")
        return nil
    end
    local res, err = self.db:rate_limiting(key, expire_time)
    ngx.log(ngx.ERR, "self.db:rate_limiting(" .. tonumber(res) ..")")
    return res
end

return RedisStore

local ipairs = ipairs
local type = type
local encode_base64 = ngx.encode_base64
local string_format = string.format
local string_gsub = string.gsub
local tabel_insert = table.insert
local cjson = require("cjson.safe")

local utils = require("orange.utils.utils")
local BasePlugin = require("orange.plugins.base_handler")
local stringm = require("orange.utils.stringm")
local http = require("orange.utils.http")

local TokenValidateHandler = BasePlugin:extend()
TokenValidateHandler.PRIORITY = 2000

function TokenValidateHandler:new(store,redis,config)
    TokenValidateHandler.super.new(self, "token_validate-plugin")
    self.store = store
    self.config = config
    self.redis = redis
end
local function getMethodNum(method)
    if method == "GET" then
        return 0
    elseif method == "POST" then
        return 1
    elseif method == "PUT" then
        return 2
    elseif method == "DELETE" then
        return 3
    elseif method == "PATCH" then
        return 4
    else 
        return 5
    end
end

local function compareUri(uri,gateway_uri)
    local uriTable = stringm.split(uri,"/")
    local gatewayTable = stringm.split(gateway_uri,"/")
    if #uriTable ~= #gatewayTable then return false end
    for k,v in ipairs(uriTable) do
        local gatewayspl = gatewayTable[k]
        if v ~= gatewayspl and not (stringm.startswith(gatewayspl,"{{") and stringm.endswith(gatewayspl,"}}")) then 
            return false 
        end
    end
    return true
end

local function matchUri(uri,res)
    for _,v in ipairs(res) do
        local gateway_uri = v["gateway_uri"]
        local res = compareUri(uri,gateway_uri)
        if res then
            return true
        end
    end
    return false
end


local function getMethod(mysqldb,uri,method)
    local sql = "select av.gateway_uri from api_version av left join api_method am on av.id=am.api_version_id where am.token_flag = 0 and am.method_type = ? and av.gateway_uri = ?"
    local methodnum = getMethodNum(method)
    local param = {methodnum,uri}
    local res, err = mysqldb:query(sql,param)
    if err then
        ngx.log(ngx.DEBUG, "mysql_db:query, error:", err, " sql:", sql)
        return false
    end
    if res and type(res) == "table" then
        if #res <= 0 then
            local sql = "select av.gateway_uri from api_version av left join api_method am on av.id=am.api_version_id where am.token_flag = 0 and am.method_type = ?"
            local param = {methodnum}
            local res, err = mysqldb:query(sql,param)
            if err then
                ngx.log(ngx.DEBUG, "mysql_db:query, error:", err, " sql:", sql)
                return false
            end
            if res and type(res) == "table" then
                if #res <= 0 then
                    ngx.log(ngx.WARN, "mysql_db:query empty, sql:", sql)
                    return false
                else
                    return matchUri(uri,res)
                end
            end
        else
            ngx.log(ngx.DEBUG, "mysql_db:query success, sql:", sql)
            return true
        end
    end
    return false
end

local function validateToken(env,urls,src,token,puid,account)
    if not src then return false end
    if not token then return false end
    if src ~= "c" and src ~= "b" then return false end
    if src == "c" and not puid then return false end
    if src == "b" and not account then return false end
    local url,host,path,schame,schame_host
    local query,param="",{}
    if src == "c" then
        url = urls.validate_token_c
        if env ~= "prod" then
            url = (string_gsub(url,"{{puid}}",puid))
        end
        query = "puid="..puid.."&ploginToken="..token
    elseif src == "b" then
        url = urls.validate_token_b
        query = "account="..account.."&sessionToken="..token
    end

    local httpc = http.new()
    httpc:set_keepalive(60000,10)
    httpc:set_timeout(5000)
    local uri = url.."?"..query
    local res, err = httpc:request_uri(uri)
    ngx.log(ngx.DEBUG, "httpc:request_uri(uri) result.res is not nil: "..tostring((res ~= nil)))
    ngx.log(ngx.DEBUG, "httpc:request_uri(uri) result.err has error: "..tostring((err == true)))
    if res ~= nil then
        local body = cjson.decode(res.body)
        if src == "c" then
            if tonumber(body.status) ~= 200 then return false end
            if body then ngx.log(ngx.DEBUG,"body.status :"..tostring(body.status).." body.message :"..body.message) end
        elseif src == "b" then
            if body then ngx.log(ngx.DEBUG,"body.data :"..tostring(body.data)) end
            if not body.data then return false end
        end
    else
        return false
    end
    return true
end

function TokenValidateHandler:access()
    local uri = ngx.var.uri
    local method = ngx.req.get_method()
    local mysqldb = self.store.db
    local config = self.config
    local res = getMethod(mysqldb,uri,method)
    ngx.log(ngx.DEBUG, "getMethod result :", tostring(res))
    if res then
        local token = ngx.var.http_token
        local src = ngx.var.http_src
        local puid = ngx.var.http_puid
        local account = ngx.var.http_account
        local env = config.env
        local url = config.url
        ngx.log(ngx.DEBUG, "config.env :", env)
        ngx.log(ngx.DEBUG, "config.url.validate_token_c :", tostring(url.validate_token_c))
        ngx.log(ngx.DEBUG, "config.url.validate_token_b :", tostring(url.validate_token_b))
        ngx.log(ngx.DEBUG, "token :", token)
        ngx.log(ngx.DEBUG, "src :", src)
        ngx.log(ngx.DEBUG, "puid :", puid)
        ngx.log(ngx.DEBUG, "account :", account)
        local valres = validateToken(env,url,src,token,puid,account)
        ngx.log(ngx.DEBUG, "validatetoken result :", tostring(valres))
        if not valres then
            return ngx.exit(ngx.HTTP_UNAUTHORIZED)
        end
    end
    return
end

return TokenValidateHandler

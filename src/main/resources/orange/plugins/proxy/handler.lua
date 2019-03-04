local BasePlugin = require("orange.plugins.base_handler")
local cjson = require("cjson.safe")
local http = require("orange.utils.http")
local string_gsub = string.gsub
local stringy = require("orange.utils.stringy")
local responses = require("orange.lib.responses")

local ProxyHandler = BasePlugin:extend()
ProxyHandler.PRIORITY = 2000

function ProxyHandler:new(store, redis, config)
    ProxyHandler.super.new(self, "proxy-plugin")
    self.store = store
    self.redis = redis
    self.config = config
end

local function validateToken(env,urls,src,token,puid,account)
    if not src then return false end
    if not token then return false end
    if src ~= "c" and src ~= "b" then return false end
    if src == "c" and not puid then return false end
    if src == "b" and not account then return false end
    local url, host, path, schame, schame_host
    local query, param = "", {}
    if src == "c" then
        url = urls.validate_token_c
        if env ~= "prod" then
            url = (string_gsub(url,"{{puid}}",puid))
        end
        query = "puid=" .. puid .. "&ploginToken=" .. token
    elseif src == "b" then
        url = urls.validate_token_b
        query = "account=" .. account .. "&sessionToken=" .. token
    end

    local httpc = http.new()
    httpc:set_keepalive(60000, 10)
    httpc:set_timeout(5000)
    local uri = url .. "?" .. query
    local res, err = httpc:request_uri(uri)
    
    if res ~= nil then
        local body = cjson.decode(res.body)
        if src == "c" then
            if body and body.status and tonumber(body.status) == 200 then
                return true
            end
        elseif src == "b" then
            if body and body.status and tonumber(body.status) == 200 and  body.data == true then
                return true
            end
        end
    end
    return false
end

function makeMessage(returnCode, returnMsg, returnData)
    local result = {}
    
    result.status = returnCode
    result.message = returnMsg
    result.data = returnData
    
    return result
end

local function wait()  
   ngx.sleep(1)  
end 

function ProxyHandler:proxy(accessType)

    ProxyHandler.super.proxy(self)
    local ngx_var = ngx.var
    local ngx_var_uri = ngx_var.uri
    local ngx_var_host = ngx_var.http_host
    local ngx_var_scheme = ngx_var.scheme
    local ngx_var_args = ngx_var.args
    
    local host, port, uriId, newUrl = self.redis:queryHostByUri(ngx_var_uri)
    if not host then
        ngx.log(ngx.ERR, "[Proxy][ngx_var_uri:" .. tostring(ngx_var_uri) .. "]Error!")
        
        -- 404
        return responses.send(ngx.HTTP_NOT_FOUND, makeMessage(ngx.HTTP_NOT_FOUND, '接口不存在'))
    end
    
    ngx.log(ngx.INFO, "self.redis:queryHostByUri.result:".." host : " .. tostring(host) .. " port : " .. tostring(port) .. "uriId : " .. tostring(uriId) .. " newUrl : " .. tostring(newUrl))
    
    local method_type = ngx.req.get_method()
    local key = "API_VER_METHOD_MAP_"..uriId
    local res, err = self.redis:queryUriMethod(key, method_type)
    if err or not res then
        ngx.log(ngx.ERR, "[Proxy][self.redis:hget]Error!")
        
        -- 405
        return responses.send(ngx.HTTP_NOT_ALLOWED, makeMessage(ngx.HTTP_NOT_ALLOWED, '接口不支持该METHOD类型'))
    end

    local method = cjson.decode(res)
    
    -- 检查是否允许外网访问begin 0-不允许外网访问,1-允许外网访问
    local accessFlagSrc = method["accessFlag"]
    local accessFlag = accessFlagSrc
    if not accessFlag or type(accessFlag) ~= "number" or accessFlag ~= 1 then accessFlag = 0 end
    -- 访问类型,0-内网访问,1-外网访问
    local accessTypeSrc = accessType
    if not accessType or type(accessType) ~= "number" or accessType ~= 0 then accessType = 1 end
    if accessFlag == 0 and accessType == 1 then
        ngx.log(ngx.ERR, "[Proxy][" .. ngx_var_uri .. "][accessFlag:" .. tostring(accessFlagSrc) .. "][accessType:" .. tostring(accessTypeSrc) .. "]不允许外网访问!")
        
        -- 403
        return responses.send(ngx.HTTP_FORBIDDEN, makeMessage(ngx.HTTP_FORBIDDEN, '接口禁止外网访问'))
    end
    -- 检查是否允许外网访问end
    
    -- 限流代码块 开始
    
    
    local traffic_limit_flag = method["trafficLimitFlag"]
    if traffic_limit_flag and type(traffic_limit_flag) == "number" and  traffic_limit_flag == 1 then
      local expire_time = 1
      local rate_count
      if accessFlag == 0 then 
        rate_count = method["insideRate"]
      end 
      
      if accessFlag == 1 then
        rate_count = method["outsideRate"]
      end
      if rate_count > 0 then
        local rate_key = "rate_key_" .. uriId .. "_" .. method_type .. "_" .. accessType
      
        local limit_res, limit_err = self.redis:rate_limiting(rate_key,expire_time)
         if not limit_res then
            ngx.log(ngx.ERR, "[Proxy][self.redis:rate_limiting]Error!")
            return ngx.exit(ngx.HTTP_NOT_FOUND)
        end
        
        ngx.log(ngx.ERR, "limit_res:[" .. limit_res .. "], rate_count : [" .. rate_count .. "]" )
        if limit_res > rate_count then
            return ngx.exit(ngx.HTTP_FORBIDDEN)
        end 
       end
    end
    
    
    -- 限流代码块 结束
    
    -- 增加token校验begin
    local tokenFlag = method["tokenFlag"]
    if not tokenFlag or type(tokenFlag) ~= "number" or tokenFlag ~= 1 then tokenFlag = 0 end
    if tokenFlag == 0 then 
        local token = ngx.var.http_token
        local src = ngx.var.http_src
        local puid = ngx.var.http_puid
        local account = ngx.var.http_account
        local env = self.config.env
        local url = self.config.url
        
        local res = validateToken(env,url,src,token,puid,account)
        
        if not res then
            -- 401
            return responses.send(ngx.HTTP_UNAUTHORIZED, makeMessage(ngx.HTTP_UNAUTHORIZED, '接口鉴权失败'))
        end
    end
    -- 增加token校验end
    
    ngx.var.upstream_host = host .. ":" .. port
    -- 支持uri地址重写
    ngx.req.set_uri(newUrl)
    ngx.var.backend_proxy = host .. ":" .. port
end


return ProxyHandler

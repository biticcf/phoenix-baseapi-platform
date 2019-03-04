local ipairs = ipairs
local type = type
local tostring = tostring

local utils = require("orange.utils.utils")
local orange_db = require("orange.store.orange_db")
local BasePlugin = require("orange.plugins.base_handler")
local counter = require("orange.plugins.rate_limiting.counter")

local function get_current_stat(limit_key)
    return counter.get(limit_key)
end

local function incr_stat(limit_key, limit_type)
    counter.incr(limit_key, 1, limit_type)
end

local RateLimitingHandler = BasePlugin:extend()
RateLimitingHandler.PRIORITY = 1000

function RateLimitingHandler:new(store, redis, config)
    RateLimitingHandler.super.new(self, "rate-limiting-plugin")
    self.store = store
    self.redis = redis
    self.config = config
end

function RateLimitingHandler:access(conf)
    RateLimitingHandler.super.access(self)

    local ngx_var = ngx.var
    local ngx_var_uri = ngx_var.uri
    local ngx_var_host = ngx_var.http_host
    local ngx_var_scheme = ngx_var.scheme
    local ngx_var_args = ngx_var.args
    
    local host, port, uriId, newUrl = self.redis:queryHostByUri(ngx_var_uri)
    ngx.log(ngx.DEBUG, "self.redis:queryHostByUri.result:".." host : "..host.." port : "..port.."uriId : "..uriId)
    if not host then
        ngx.log(ngx.ERR, "[Proxy][ngx_var_uri:", ngx_var_uri, "]Error!")
        return ngx.exit(ngx.HTTP_NOT_FOUND)
    end
    
    
    local current_timetable = utils.current_timetable()
    local time_key = current_timetable["Second"]
    local limit_key = uriId .. "#" .. time_key
    local current_stat = get_current_stat(limit_key) or 0
    local limit_count = 10               
    local limit_type = "Second"               
    -- 暂时写死 后续从redis读取
    ngx.header["X-RateLimit-Limit" .. "-" .. limit_type] = limit_count                
    ngx.log(ngx.ERR,"============================================I'm here============================================")  
     ngx.log(ngx.INFO, " uri:", ngx_var_uri, " limit:", limit_count, " reached:", current_stat, " remaining:", 0)
                 
     if current_stat >= limit_count then
          -- ngx.log(ngx.INFO, " uri:", ngx_var_uri, " limit:", limit_count, " reached:", current_stat, " remaining:", 0)

          ngx.header["X-RateLimit-Remaining" .. "-" .. limit_type] = 0
          return ngx.exit(429)
      else
          ngx.header["X-RateLimit-Remaining" .. "-" .. limit_type] = limit_count - current_stat - 1
          incr_stat(limit_key, limit_type)

          -- only for test, comment it in production
          -- if handle.log == true then
          --     ngx.log(ngx.INFO, "[RateLimiting-Rule] ", rule.name, " uri:", ngx_var_uri, " limit:", handle.count, " reached:", current_stat + 1)
          -- end
      end
      
      return false
end

return RateLimitingHandler

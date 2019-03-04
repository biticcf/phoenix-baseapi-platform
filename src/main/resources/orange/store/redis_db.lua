local setmetatable = setmetatable
local redis = require("resty.redis")

local DB = {}

function DB:new(conf)
    local instance = {}
    instance.conf = conf
    setmetatable(instance, { __index = self})
    
    return instance
end

function DB:openRedis()
    local rds, err, ok
    rds, err = redis:new()
    if not rds or err then
        ngx.log(ngx.ERR, "[redis_db:open_redis()] failed to create: ", err)
        
        return nil, err
    end
    
    local conf = self.conf
    rds:set_timeout(conf.timeout)
    
    local connect_config = conf.connect_config
    local ok, err = rds:connect(connect_config.host, connect_config.port)
    if not ok or err then
       ngx.log(ngx.ERR, "[redis_db:open_redis()] failed to connect: ", err)
       return nil, err
    end
    
    return rds
end

function DB:get(key,...)
  local rds, err = self:openRedis()
  
  if not rds or err then
    ngx.log(ngx.ERR, "[redis_db:get()][" .. key .. "], error:", err)
    return nil
  end
  
  local res, err = rds:get(key,...)
  if not res or err or type(res) == 'userdata'  then
    ngx.log(ngx.ERR,"get:",err)
    self:close_redis(rds)
    return nil
  end
  self:close_redis(rds)
  
  return res, err
end

function DB:hget(key,...)
  local rds, err = self:openRedis()
  
  if not rds or err then
    ngx.log(ngx.ERR, "[redis_db:hget()][" .. key .. "], error:", err)
    return nil
  end
  
  local res, err = rds:hget(key,...)
  if not res or err or type(res) == 'userdata'  then
    ngx.log(ngx.ERR,"hget:", err)
    self:close_redis(rds)
    
    return nil
  end
  self:close_redis(rds)
  
  return res, err
end

function DB:set(key,value)
  local rds, err = self:openRedis()
  
  if not rds or err then
    ngx.log(ngx.ERR, "[redis_db:set()][key : " .. key .. ", value : " .. "], error:", err)
    return nil
  end
  
  local res, err = rds:set(key,value)
  self:close_redis(rds)
  return res, err
end

function DB:incr(key,step)
  local rds, err = self:openRedis()
  
  if not rds or err then
    ngx.log(ngx.ERR, "[redis_db:incr()][" .. key .. "], error:", err)
    return nil
  end
  
  local res, err = rds:incr(key,step)
  self:close_redis(rds)
  return res, err
end

function DB:expire(key,expire_time)
  local rds, err = self:openRedis()
  
  if not rds or err then
    ngx.log(ngx.ERR, "[redis_db:expire()][" .. key .. "], error:", err)
    return nil
  end
  
  local res, err = rds:expire(key,expire_time)
  self:close_redis(rds)
  return res, err
end

function DB:close_redis(rds)
    if not rds then
        return
    end
    --释放连接(连接池实现)
    local pool_max_idle_time = 10000 --毫秒
    local pool_size = 100 --连接池大小
    local ok, err = rds:set_keepalive(pool_max_idle_time, pool_size)

    if not ok or err then
       ngx.log(ngx.ERR,"set redis keepalive error: ", err)
    end
end
function DB:rate_limiting(key,expire_time)
  local rds, err = self:openRedis()
  if not rds or err then
     ngx.log(ngx.ERR, "[redis_db:rate_limiting()][" .. key .. "], error:", err)
     return nil
  end
  local res, err = rds:eval("local res, err = redis.call('incr',KEYS[1]) if res == 1 then local resexpire, err = redis.call('expire',KEYS[1],KEYS[2]) end return (res)",2,key,expire_time)  
  self:close_redis(rds)
  return res, err
end

return DB


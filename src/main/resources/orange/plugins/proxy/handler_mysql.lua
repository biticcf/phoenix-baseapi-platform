local ipairs = ipairs
local tonumber = tonumber
local string_find = string.find
local string_sub = string.sub
local string_len = string.len
local orange_db = require("orange.store.orange_db")
local judge_util = require("orange.utils.judge")
local extractor_util = require("orange.utils.extractor")
local handle_util = require("orange.utils.handle")
local BasePlugin = require("orange.plugins.base_handler")

local balancer = require "ngx.balancer"


local function filter_rules(sid, plugin, ngx_var_uri, ngx_var_host, ngx_var_scheme, ngx_var_args)
    local rules = orange_db.get_json(plugin .. ".selector." .. sid .. ".rules")
    if not rules or type(rules) ~= "table" or #rules <= 0 then
        return false
    end
    
    for j, rule in ipairs(rules) do
        if rule.enable == true then
            -- judge阶段
            local pass = judge_util.judge_rule(rule, plugin)
            -- extract阶段
            local variables = extractor_util.extract_variables(rule.extractor)
            
            -- handle阶段
            if pass then
                local handle = rule.handle
                if handle and handle.url_tmpl then
                    local to_redirect = handle_util.build_url(rule.extractor.type, handle.url_tmpl, variables)
                    if to_redirect and to_redirect ~= ngx_var_uri and string_len(to_redirect) > 8 and string_find(to_redirect, "http://") == 1 then
                        -- 解析被代理的host和port
                        -- http://test.com:8080/zz/xxx(从第3个/开始算)
                        local proxy_host_port
                        local f1, f2 = string_find(to_redirect, '/', 8)
                        if not f1 then
                            proxy_host_port = to_redirect
                        else
                            proxy_host_port = string_sub(to_redirect, 1, f1 - 1)
                        end
                        
                        local proxy_host, proxy_port
                        f1, f2 = string_find(proxy_host_port, ':', 8)
                        if not f1 then
                            proxy_host = proxy_host_port
                            proxy_port = 80
                        else
                            proxy_host = string_sub(proxy_host_port, 1, f1 - 1)
                            proxy_port = string_sub(proxy_host_port, f1 + 1)
                        end
                        -- 去掉 ‘http://’
                        proxy_host = string_sub(proxy_host, 8)
                        
                        ngx.log(ngx.INFO, "sucess to find proxy_host[" .. proxy_host .. "], proxy_port[" .. proxy_port .. "]. ")
                        
                        ngx.var.upstream_host = proxy_host
                        ngx.var.backend_proxy = proxy_host .. ":" .. proxy_port
                        
                        return true
                    end
                end
            end
        end
    end
    
    return false
end

local ProxyHandler = BasePlugin:extend()
ProxyHandler.PRIORITY = 2000

function ProxyHandler:new(store)
    ProxyHandler.super.new(self, "proxy-plugin")
    self.store = store
end

function ProxyHandler:proxy()
    ProxyHandler.super.proxy(self)
    
    local enable = orange_db.get("proxy.enable")
    local meta = orange_db.get_json("proxy.meta")
    local selectors = orange_db.get_json("proxy.selectors")
    local ordered_selectors = meta and meta.selectors
    
    if not enable or enable ~= true or not meta or not ordered_selectors or not selectors then
        return
    end
    
    local ngx_var = ngx.var
    local ngx_var_uri = ngx_var.uri
    local ngx_var_host = ngx_var.http_host
    local ngx_var_scheme = ngx_var.scheme
    local ngx_var_args = ngx_var.args

    for i, sid in ipairs(ordered_selectors) do
        ngx.log(ngx.INFO, "==[Proxy][PASS THROUGH SELECTOR:", sid, "]")
        local selector = selectors[sid]
        if selector and selector.enable == true then
            local selector_pass 
            if selector.type == 0 then -- 全流量选择器
                selector_pass = true
            else
                selector_pass = judge_util.judge_selector(selector, "proxy")-- selector judge
            end

            if selector_pass then
                if selector.handle and selector.handle.log == true then
                    ngx.log(ngx.INFO, "[Proxy][PASS-SELECTOR:", sid, "] ", ngx_var_uri)
                end

                local stop = filter_rules(sid, "proxy", ngx_var_uri, ngx_var_host, ngx_var_scheme, ngx_var_args)
                if stop then -- 不再执行此插件其他逻辑
                    return
                end
            else
                if selector.handle and selector.handle.log == true then
                    ngx.log(ngx.INFO, "[Proxy][NOT-PASS-SELECTOR:", sid, "] ", ngx_var_uri)
                end
            end

            -- if continue or break the loop
            if selector.handle and selector.handle.continue == true then
                -- continue next selector
            else
                break
            end
        end
    end
end

return ProxyHandler

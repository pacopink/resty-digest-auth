-- 如果能够在log_by_lua阶段执行是比较合适的，
-- 但是在那个context下，ngx.location.* 被disable了
-- 这个实际上没法用

local function purge_cache()
  ngx.location.capture_multi{
    {'/purge'..ngx.var.uri, {}},
    {'/purge'..ngx.var.uri, {args="metadata=1"}},
  }
end

local method = ngx.var.request_method
local status = ngx.status
if status>=200 and status<300 and method ~= 'GET' and method ~= 'HEAD' then 
  -- 如果是引发变更的合法请求，把cache给清理掉
  -- ngx.log(ngx.WARN, "status: "..status.." method: "..method.."  do purge")
  purge_cache()
end

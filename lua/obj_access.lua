--secrets = {
--    paco='ericsson123',
--    tell='123456'
--}
local expire=180 --3分钟超时间隔

local method = ngx.req.get_method()
local uri = ngx.var.uri
local headers = ngx.req.get_headers()

local user = headers["X-Auth-User"]
local ts = headers["X-Auth-TS"]
local token = headers["X-Auth-Token"]
local now = ngx.now()*1000


if user == nil or ts == nil or token == nil then
    ngx.log(ngx.WARN, "#1 invalid X-Auth-User, X-Auth-TS, X-Auth-Token")
    ngx.status = 403
    ngx.say("X-Auth-* headers invalid: #1")
    ngx.exit(403)
end

local function get_secret(user)
  local res = ngx.location.capture('/passwd?username='..user)
  if res and res.status==200 then
    local secret = string.sub(res.body, 1, string.len(res.body)-1)  -- get rid of '\r\n' ending
    ngx.log(ngx.WARN, "get secret:["..secret.."]")
    return secret
  else
    ngx.status = 503
    ngx.log(ngx.ERR, "Failed to get secret")
    ngx.exit(503)
    return nil
  end
end

local secret = get_secret(user)
if secret == nil or secret == ngx.null then
    ngx.log(ngx.WARN, "#2 X-Auth-User is not registered")
    ngx.status = 403
    ngx.say("X-Auth-* headers invalid: #2")
    ngx.exit(403)
end

if (now-ts)>expire*1000 or (now-ts)<-(expire*1000) then
    ngx.log(ngx.WARN, "#3 X-Auth-Ts expired")
    ngx.status = 403
    ngx.say("X-Auth-* headers invalid: #3")
    ngx.exit(403)
end

local md5=require 'resty.md5'
local str = require 'resty.string'
local m = md5:new()

local act_data_md5sum = '' --如果没有请求body，md5sum为空字符串
if method=="POST" or method == "PUT" then
  data_md5sum = headers["X-Auth-MD5"] --如果客户端送了md5sum，直接使用,内容的校验交给upstream处理
  if data_md5sum ~= nil then
    act_data_md5sum = data_md5sum
  else
    --必须显式读入body的数据，自己算一个md5sum
    ngx.req.read_body() 
    body = ngx.req.get_body_data()
    if body ~= nil then
      local ok = m:update(body)
      local digest = m:final()
      m:reset()
      act_data_md5sum = str.to_hex(digest)
    end
  end
end


local ok = m:update(ts..":"..user..":"..secret..":"..method..":"..uri..":"..act_data_md5sum)
local calc_token = ''
if ok then
    local digest = m:final()
    calc_token = str.to_hex(digest)
    --ngx.say("MD5: "..str.to_hex(digest)..'<br/>')
    if token ~= calc_token then
        ngx.log(ngx.WARN, "#4 X-Auth-Token is not matched")
        ngx.status = 403
        ngx.say("X-Auth-* headers invalid: #4")
        ngx.exit(403)
    end
end


-- 如果是引发变更的合法请求，把cache给清理掉
local function purge_cache()
  if (method ~= 'GET' and method ~= 'HEAD') then
    ngx.location.capture_multi{
      {'/purge'..ngx.var.uri, {}},
      {'/purge'..ngx.var.uri, {args="metadata=1"}},
    }
  end 
end

--判断token是否已经被使用，并记录一定的时长，避免重放攻击
local redis = require 'resty.redis'
local r = redis:new()
r:set_timeout(1000)
local ok, err = r:connect("127.0.0.1", 6379)
if ok then
    local token_key = "t:"..token
    local value, err = r:get(token_key)
    if value == 'used' then
        r:set_keepalive(300, 2)
        ngx.log(ngx.WARN, "#5 Detected token replay")
        ngx.status = 403
        ngx.say("X-Auth-* headers invalid: #5")
        ngx.exit(403)
    else
        -- 检查通过，把当前token记录到redis表示已经被使用了
        -- expire秒后这个记录失效被清除
        r:multi()
        r:set(token_key, 'used')
        r:expire(token_key, expire)
        r:exec()
        --清空缓存，可能存在问题，比如在清空后
        --但是执行更新之前，有并发的其他GET请求
        --会把旧的数据给写回缓存，这种情况
        --只能等待缓存expire了
        purge_cache()
    end
    r:set_keepalive(300, 16)
else
    ngx.status = 503
    ngx.log(ngx.ERR, "Failed to check token with redis error: "..err)
    ngx.exit(503)
end



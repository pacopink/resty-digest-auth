secrets = {
    paco='ericsson123',
    tell='123456'
}
expire=180 --3分钟超时间隔

headers = ngx.req.get_headers()

user = headers["X-Auth-User"]
ts = headers["X-Auth-TS"]
token = headers["X-Auth-Token"]
secret = secrets[user]
now = ngx.now()*1000

if user == nil or ts == nil or token == nil then
    ngx.say("invalid X-Auth-*")
    ngx.exit(403)
end

if secret == nil then
    ngx.say("invalid X-Auth-User")
    ngx.exit(403)
end

if (now-ts)>expire*1000 or (now-ts)<-(expire*1000) then
   ngx.say("invalid X-Auth-TS")
   ngx.exit(403)
end

local md5=require 'resty.md5'
local m = md5:new()
local ok = m:update(ts..":"..user..":"..secret)
local calc_token = ''
if ok then
    local digest = m:final()
    local str = require 'resty.string'
    calc_token = str.to_hex(digest)
    --ngx.say("MD5: "..str.to_hex(digest)..'<br/>')
    if token ~= calc_token then
        ngx.say(calc_token)
        ngx.say(token)
        ngx.say("invalid X-Auth-Token")
        --ngx.exit(403)
    end
end



--判断token是否已经被使用了，避免重放攻击
local redis = require 'resty.redis'
local r = redis:new()
r:set_timeout(1000)
local ok, err = r:connect("127.0.0.1", 6379)
if ok then
    local value, err = r:get(token)
    if value == 'used' then
        r:set_keepalive(300, 2)
        ngx.say(value)
        ngx.say(err)
        ngx.say("token used")
        ngx.exit(403)
    else
        r:multi()
        r:set(token, 'used')
        r:expire(token, expire)
        r:exec()
        r:set_keepalive(300, 2)
        ngx.say("auth valid")
        --r.expire(token, 120)
    end
else
    ngx.say("Redis err:"..err)
    ngx.exit(503)
end

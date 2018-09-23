realm = ngx.var.realm
nonce_expire_second = 3600

-- 产生WWW-Authenticate头的内容，用于401响应
local function gen_challenge(opaque)
  nonce = ngx.encode_base64(ngx.now(), true)
  return 'Digest nonce="'..nonce..'", realm="'..realm..'", opaque="'..opaque..'", qop="auth"'
  --  WWW-Authenticate: Digest nonce="af6e30219cccaca5", opaque="False", realm="__main__", qop="auth"
end

-- 根据传入字符串得到hex格式的md5 digest
local md5=require 'resty.md5'
local str = require 'resty.string'
local m = md5:new()
local function get_md5_digest(sss)
  m:reset()
  m:update(sss)
  digest = m:final()
  return str.to_hex(digest)
end

-- is nc increased 利用redis记录nc,确保请求的nc是递增的
local function is_nc_increased(username, nonce, nc)
  local result = nil
  local redis = require 'resty.redis'
  local r = redis:new()
  r:set_timeout(1000)
  local ok, err = r:connect("127.0.0.1", 6379)
  if ok then
    local key = username..":"..nonce
    ngx.log(ngx.WARN, key)
    local value, err = r:get(key)
    if value == ngx.null then
      --如果没有记录,则信任当前nc,并记录下来
      r:multi()
      r:set(key, nc)
      r:expire(key, nonce_expire_second)
      r:exec()
      result = "OK"
    else
      --如果有记录,则需要比较当前nc大于已有的,才信任并记录
      if value<nc then
        r:multi()
        r:set(key, nc)
        r:expire(key, nonce_expire_second)
        r:exec()
        result = "OK"
      end
    end
    r:set_keepalive(30000, 16)
  else
    ngx.log(ngx.ERR, "failed to connect redis:"..err)
  end
  if result ~= nil then
    ngx.log(ngx.WARN, "nc is increased") 
  else
    ngx.log(ngx.ERR, "nc is not increased")
  end
  return result
end

-- 获取用户的密码
local function get_passwd(username)
  db = {paco='ericsson', sam='123456'}
  return db[username]
end
-- 从Redis缓存的MySQL数据库获取用户密码
--local function get_passwd(username)
--  local res = ngx.location.capture('/passwd?username='..username)
--  if res and res.status==200 then
--    local secret = string.sub(res.body, 1, string.len(res.body)-1)  -- get rid of '\r\n' ending
--    --ngx.log(ngx.WARN, "get secret:["..secret.."]")
--    return secret
--  else
--    ngx.status = 503
--    ngx.log(ngx.ERR, "Failed to get secret")
--    ngx.exit(503)
--    return nil
--  end
--end


-- 获取用户的HA1
local function get_ha1(username)
  passwd = get_passwd(username)
  return get_md5_digest(username..":"..realm..":"..passwd)
end

-- 校验Authorization头部
local function validate(auth)
  if realm ~= auth.realm then
    ngx.log(ngx.WARN, "["..realm.."]<>["..auth.realm.."]")
    return 401, "realm not match"
  end
  if ngx.var.uri ~= auth.uri then
    ngx.log(ngx.WARN, ngx.var.uri.."<>"..auth.uri)
    return 401, "uri not match"
  end

  method = ngx.req.get_method()
  uri = auth.uri
  response = auth.response
  username = auth.username
  nonce = auth.nonce
  cnonce = auth.cnonce
  nc = auth.nc
  opaque = auth.opaque

  --处理超时,nonce实际是一个base64时间戳,如果超过时限,要求重新鉴权
  ts = tonumber(ngx.decode_base64(nonce))
  if ts == nil or ngx.now()-ts>nonce_expire_second then
    return 401, "invalid nonce or nonce expired"
  end

  HA1 = get_ha1(username)
  HA2 = get_md5_digest(method..":"..uri)
  x = HA1..":"..nonce..":"..nc..":"..cnonce..":auth:"..HA2
  RESPONSE = get_md5_digest(x)
  if response == RESPONSE then
    --处理nc单调递增
    if is_nc_increased(username, nonce, nc) == nil then
      return 401, "nc not increased"
    else
      return 200, "OK"
    end
  else
    return 401, "response not match x:"..x..", resp:"..RESPONSE..", HA1:"..HA1..", HA2:"..HA2
  end
end

-- 响应401和WWW-Authenticate头，挑战客户端，触发浏览器弹出输入用户密码
local function challenge(msg)
  ngx.status = 401
  ngx.header["WWW-Authenticate"]=gen_challenge("")
  if msg ~= nil then
    ngx.say(msg)
  end
  ngx.exit(401)
end


-- 如果请求不带Authorization，响应一个challenge
headers = ngx.req.get_headers()
authorization = headers.Authorization
if authorization == nil then
  challenge(nil)
end
-- 处理Authorization头，用正则表达式拆分出字段，填到table
auth = {}
auth_str = string.match(authorization, "%s*[Dd]igest%s*(.*)$")
if auth_str == nil then
  challenge(nil)
end
for k,v in string.gmatch(auth_str, "(%w+)%s*=%s*\"?([%w./=:_?&-]+)\"?") do
  auth[k]=v
end

-- 校验，如果不成功，再响应挑战
local code, msg = validate(auth)
if code ~= 200 then
  challenge(msg)
end

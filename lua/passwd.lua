local function get_secret_from_db(username)
  local quated_username = ngx.quote_sql_str(username)
  local mysql = require "resty.mysql"
  local db, err = mysql:new()
  local result = {}
  if not db then
    result.code = 404
    result.msg = "DB FAILED: "..err
    return result
  end

  db:set_timeout(1000)
  local ok, err, errno, sqlstate = db:connect {
    host="127.0.0.1",
    port=3306,
    database = "paco",
    user = "paco",
    password = "123456",
    max_package_size = 1024
  }
  if not ok then
    result.code = 404
    result.msg = "DB FAILED TO Query: "..err.." :"..errno.." :"..sqlstate
    return result
  else
    res, err, errno, sqlstate = db:query("select secret from user_secret where username="..quated_username)
    if not res then
      result.code=404
      result.msg = "DB FAILED TO Query: "..err.." :"..errno.." :"..sqlstate
      return result
    end

    if err == nil then
      ok, err = db:set_keepalive(300000, 16)
    else
      db:close()
    end

    local cjson = require "cjson"
  --  ngx.say(cjson.encode(res))
    if not res[1] or not res[1]['secret'] then
      result.code = 404
      result.msg = "user not found"
      return result
    else
      result.code = 200
      result.msg = "OK"
      result.secret = res[1]['secret']
      return result
    end
  end 
end

-- get from redis
local function get_secret_from_redis(username)
  local redis = require 'resty.redis'
  local r = redis:new()
  r:set_timeout(1000)
  local ok, err = r:connect("127.0.0.1", 6379)
  if ok then
      local value, err = r:get(username)
      if err == nil then
        r:set_keepalive(30000, 16)
      end
      if value ~= ngx.null  then
        return value
      else
        return nil
      end
  else
    ngx.log(ngx.WARN, "failed to get cache secret from redis: ", err)
  end
end

-- save to redis
local function set_secret_to_redis(username, secret, ttl)
  local redis = require 'resty.redis'
  local r = redis:new()
  r:set_timeout(1000)
  local ok, err = r:connect("127.0.0.1", 6379)
  if ok then
    r:multi()
    r:set(username, secret)
    r:expire(username, ttl)
    r:exec()
    r:set_keepalive(30000, 16)
  else
    ngx.log(ngx.WARN, "failed to cache secret to redis: ", err)
  end
end

-- 主流程
local username = ngx.unescape_uri(ngx.var.arg_username)
if username ~= nil then
  local redis_key = "s:"..username
  local secret = get_secret_from_redis(redis_key) --先尝试从redis取
  secret = nil -- for test
  if secret ~= nil then
    ngx.say(secret)
  else
    local res = get_secret_from_db(username)
    if not res then
      ngx.exit(503)
    else
      if res.code == 200 and res.secret ~= nil then
        set_secret_to_redis(redis_key, res.secret, 3600) --缓存1小时
        ngx.say(res.secret)
      else
        ngx.status = res.code
        ngx.say(res.msg)
        ngx.exit(res.code)
      end
    end
  end
else
  ngx.status=404
  ngx.say("username not provided")
  ngx.exit(404)
end

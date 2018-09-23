local server = require "resty.websocket.server"
local wb, err = server:new{
  timeout=100000,
  max_payload_len = 65535,
}

if not wb then
  ngx.log(ngx.ERR, "failed to new websocket: ", err)
  return ngx.exit(444)
end

local function wait_from_redis(sub_key, wb)
  local redis = require 'resty.redis'
  local cjson = require 'cjson'
  local r = redis:new()
  r:set_timeout(120000)
  local ok, err = r:connect("127.0.0.1", 6379)
  if ok then
    local res, err = r:subscribe(sub_key)
    repeat
      local val, err = r:read_reply()
      if val and err == nil then
        bytes, err = wb:send_text(cjson.encode(val))
        if not bytes then
          ngx.log(ngx.ERR, "failed to send a text frame: ", err)
          return ngx.exit(444)
        end
      end
    until false
    r:set_keepalive(30000, 16)
  else
    ngx.log(ngx.WARN, "failed to get cache secret from redis: ", err)
  end
end

local function msg_loop(wb)
  local data, typ, err= wb:recv_frame()
 
  if wb.fatal then
    ngx.log(ngx.ERR, "failed to receive a frame: ", err)
    return ngx.exit(444)
  end

  if  typ == "close" then
    -- send a close frame back
    local bytes, err = wb:send_close(1000, "enough!")
    if not bytes then
      ngx.log(ngx.ERR, "failed to send the close frame: ", err)
    else
      local code =err
      ngx.log(ngx.WARN, "closing with status code ", code, " and message ", data)
    end
    return ngx.exit(444)
  end

  if typ == "ping" then
    -- send a pong frame back:
    local bytes, err = wb:send_pong(data)
    if not bytes then
      ngx.log(ngx.ERR, "failed to send frame: ", err)
      return
    end
  elseif typ == "pong" then
    -- do nothing
  elseif typ == "text" then
    wait_from_redis(data, wb)
  else
    ngx.log(ngx.INFO, "received a frame of type ", typ, " and payload ", data)
  end
end

repeat
  msg_loop(wb)
until 1==0

local bytes, err = wb:send_close(1000, "finished!")
if not bytes then 
  ngx.log(ngx.ERR, "failed to send the close frame: ", err)
end
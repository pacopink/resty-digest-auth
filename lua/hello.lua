ngx.say('<body>')
ngx.say('<p>Hello Lua</p>')
method = ngx.req.get_method()
args = ngx.req.get_uri_args()
headers = ngx.req.get_headers()
ngx.say("uri:"..ngx.var.uri..'<br/>')
ngx.say("METHOD: "..method..'<br/>')

ngx.say(type(ngx.var)..'<br/>')
ngx.say(ngx.var)
ngx.say('<br/>')
ngx.say("foo: "..ngx.var.foo..'<br/>')
for k,v in pairs(ngx.var) do
  ngx.say('VAR: '..k..'='..type(v)..'<br/>')
  --if type(v)=="string" then
  --  ngx.say('VAR: '..k..'='..v..'<br/>')
  --end
end

for k,v in pairs(args) do
    ngx.say('ARG: '..k..'='..v..'<br/>')
end

for k,v in pairs(headers) do
    ngx.say("HEADER: "..k..'='..v..'<br/>')
end

ngx.req.read_body() --必须显式读入
body = ngx.req.get_body_data()
if body~=nil then
    local cjson=require('cjson')
    local json = cjson.new()
    local cjson_safe=require('cjson.safe')
    ngx.say("BODY: "..body..'<br/>')
    local body_table = json.decode(body)
    for k,v in pairs(body_table) do
        ngx.say("JSON: "..k..'='..tostring(v)..'<br/>')
    end
end
local md5=require 'resty.md5'
local m = md5:new()
local ok = m:update("abcdefg")
if ok then
    local digest = m:final()
    local str = require 'resty.string'
    ngx.say("MD5: "..str.to_hex(digest)..'<br/>')
end
require 'resty.core.base64'
local encoded_str = ngx.encode_base64("abcdefg", false)
ngx.say(encoded_str)
ngx.say('<br/>')
ngx.say(ngx.decode_base64(encoded_str))
ngx.say('<br/>')
ngx.say(ngx.now())
ngx.say('<br/>')
ngx.say(ngx.time())
ngx.say('<br/>')
ngx.say(ngx.http_time(ngx.time()))

local redis = require 'resty.redis'
local r = redis:new()
r:set_timeout(1000)
local ok, err = r:connect("127.0.0.1", 6379)
if ok then
  local key = args['key']
  ngx.say("key ="..key..'<br/>')
  if key~=nil then
    local val, err = r:get(key)
    if not val then
      ngx.say(key..": null， "..err.."<br/>")
    else 
      if val ~= ngx.null then
        ngx.say(key..":"..val..'<br/>')
      else
        ngx.say(key..": null<br/>")
      end
    end
  end
end
ngx.say('</body>')

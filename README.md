# resty-digest-auth

This project provides lua implemetation of HTTP Digest access control using out-of-box OpenResty compenents only, and strives to minimize the dependency of 3pp middlewares, only Redis and MySQL is optionally required. You can take out MySQL if you don't need to store username-password in RMDBS, You can even compromise the anti-replay-attack feature to get rid of Redis, although it is HIGHLY not recommended.
Tested under OpenResty 1.13.6.2

## lua/digest_access.lua
A partial implementation of HTTP digest access authentitcation according to RFC2617.
Use base64 encoded timestamp ngx.now() as nonce, so that server can expire a session
after nonce_expire_second (configurable variable in the script, by default it iset to 3600 seconds).

Depend on Redis to cache the latest nc with the key [username]:[nonce], this will ensure the nc in request to be increasing, so that replay attacks can be denied.

The defualt version of get_password functioion just use a Lua table to hold username and password. The commented out version calls a internal URL to get password, which are stored in MySQL and cached by Redis, refer to 'lua/passwd.lua' for details.

## lua/passwd.lua
A content_by_lua_file script to get passwd by username, the infomation should be stored in MySQL and cached by Redis.

## lua/obj_access.lua
A private access control implementation, using some extended HTTP headers to carry authorization information, works in a digest-like way, client should sign on the request content, to keep the request information from man-in-the-middle alteration.

## lua/purge_cache.lua
nginx.conf is configured to cache GET result in Redis, this script is used to purge the cache if needed, for example, if a POST/PUT/DELETE to a cached resource, the stale cache should be purged.
 

## conf/nginx.conf
Sample nginx.conf to demo the lua scripts

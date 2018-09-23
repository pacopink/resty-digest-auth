#!/bin/env python
# coding:utf8
# 模拟客户端计算token, 对应access.lua的token校验

import hashlib
import time
import os, sys

user='paco'
secret='ericsson123'
ts = "%d"%int(time.time()*1000)
uri = '/obj/paco/test.txt'

method = 'GET'
content = ''
content_type = "text/plain"
filename = None
if len(sys.argv)!=4 or sys.argv[1].upper() not in ['GET', 'PUT', 'POST', 'DELETE']:
    print "usage: %s [method] [uri] [content or filepath]"%sys.argv[0]
    sys.exit(1)
method = sys.argv[1].upper()
uri = sys.argv[2]
if os.path.isfile(sys.argv[3]):
    filename = sys.argv[3]
else:
    content = sys.argv[3]

# 计算内容摘要
content_digest = ''
if method in ['PUT', 'POST']:
    md5 = hashlib.md5()
    if filename is not None:
        with open(input_file, 'r') as f:
            READ_MAX=1024*1024
            while True:
                x = f.read(READ_MAX)
                md5.update(x)
                if len(x)<READ_MAX:
                    break
            content_digest = md5.hexdigest()
    else:
        md5.update(content)
        content_digest = md5.hexdigest()

# 计算数字签名 
md5 = hashlib.md5()
md5.update(ts+":"+user+":"+secret+":"+method+":"+uri+":"+content_digest)
token = md5.hexdigest()

if method in ['PUT', 'POST']:
    if filename is None:
        tmp="""curl -v -X{} -H "Content-Type: {}" -H "X-Auth-User: {}" -H "X-Auth-Ts: {}" -H "X-Auth-Token: {}" localhost:28081{} -d "{}" """
        print tmp.format(method, content_type, user, ts, token, uri, content)
    else:
        tmp="""curl -v -X{} -F"file=@{}" -H "X-Auth-User: {}" -H "X-Auth-Ts: {}" -H "X-Auth-MD5: {}" -H "X-Auth-Token: {}" localhost:28081{} """
        print tmp.format(method, filename, user, ts, content_digest, token, uri)
else:
    tmp = """curl -v -X{} -H "X-Auth-User: {}" -H "X-Auth-Ts: {}" -H "X-Auth-Token: {}" localhost:28081{}   """
    print tmp.format(method, user, ts, token, uri)


import requests
import subprocess
import redis
import os
from datetime import datetime, timedelta, time

#github_token = os.environ["CI_TOKEN"]
url = os.environ['URL']
#headers = {"Authorization": "token %s" % github_token}
data = {"ref":"main","inputs":{"environment":"12345678"}}
#response = requests.post(url,json=data,headers=headers)
print(response)
print(datetime.now())
redis = redis.StrictRedis(host='platform.redis.test-headout.com', port=6379,ssl=True)
print(redis.get('test'))
data = {"text":"Test1"}
response = requests.post(os.environ["URL"],json=data)

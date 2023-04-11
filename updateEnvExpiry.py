import redis
import os
import sys
from datetime import datetime, timedelta, time
from pytz import timezone
import time

def update_expiry():
    print(sys.argv[1])
    if sys.argv[1] == "update":
        print("Updating redis key")
    if sys.argv[1] == "delete":
        print("Deleting redis key")
    try:
        redis_password = os.environ["EXPIRY_REDIS_PASSWORD"]
        print(redis_password)
        ondemand_env = os.environ["DEPLOY_NAMESPACE"]
        redisClient = redis.StrictRedis(host='platform.redis.test-headout.com', port=6379,ssl=True,password=redis_password)
        new_expiry = str(datetime.now(timezone("Asia/Kolkata"))+timedelta(days=3))
        #redisClient.set(ondemand_env,new_expiry)
        #msg = redisClient.get(ondemand_env)
        print(f"Namepace: {ondemand_env}\nExpiry: {new_expiry}")
        print("Successfully updated expiry date")
    except Exception as e:
        print("Expiry date update failed")
        print(e)


if __name__ == '__main__':
    update_expiry()

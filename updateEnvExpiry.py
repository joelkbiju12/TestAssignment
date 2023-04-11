import redis
import os
import sys
from datetime import datetime, timedelta, time
from pytz import timezone

#Updating or removing redis key value for expiry of ondemand environment
def update_expiry():
    redis_password = os.environ["EXPIRY_REDIS_PASSWORD"]
    ondemand_env = os.environ["DEPLOY_NAMESPACE"]
    redisClient = redis.StrictRedis(host='platform.redis.test-headout.com', port=6379,ssl=True,password=redis_password)
    new_expiry = str(datetime.now(timezone("Asia/Kolkata"))+timedelta(days=3))
    if sys.argv[1] == "update":
        redisClient.set(ondemand_env,new_expiry)
        print(f"Namepace: {ondemand_env}\nExpiry: {new_expiry}")
        print("Successfully updated expiry date")
    elif sys.argv[1] == "delete":
        redisClient.delete(ondemand_env)
        print("Deleted expiry date key")

if __name__ == '__main__':
    update_expiry()

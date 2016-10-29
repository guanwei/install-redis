#### Note: This tiny script has been hardcoded specifically for RHEL/CentOS/AWS EC2 ####
----------

## Get script help

```bash
# sh ./install-redis/install_redis.sh -h
```

## Install Redis

- If CLUSTER_NAME = redis-cluster
- If MASTER_IP = 10.10.10.1
- If REDIS_AUTH = admin

### Install Redis (master)

```bash
# sh ./install-redis/install_redis.sh -i -c redis-cluster -m 10.10.10.1 -a admin -t master
```

### Install Redis (slave)

```bash
# sh ./install-redis/install_redis.sh -i -c redis-cluster -m 10.10.10.1 -a admin -t slave
```

## Remove Redis

```bash
# sh ./install-redis/install_redis.sh -e
```

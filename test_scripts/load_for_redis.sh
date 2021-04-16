#!/bin/bash

redis_ip="redis_ip"
redis_password="redis_password"
redis_port="redis_port"

redis-cli -h $redis_ip -p $redis_port -a $redis_password -r 100000 set test test

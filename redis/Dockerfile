FROM redis:6.2.1

RUN mkdir ./redis_logs
RUN chmod -R 777 /redis_logs

COPY redis.conf /usr/local/etc/redis/redis.conf

CMD [ "redis-server", "/usr/local/etc/redis/redis.conf" ]

# Настройка связки DataDog + Redis

[DataDog](https://www.datadoghq.com/) - система мониторинга состояния сервера, обладающая широким спектром возможностей.
Данная система является клиент-серверной, т.е. на контролируемом сервере устанавливается ТОЛЬКО агент, который отсылает метрики на сервера DataDog.

---

## Подготовка

1. [Регистрация](https://app.datadoghq.com/signup) (создание личного кабинета на стороне DataDog, откуда и осуществляется мониторинг)
2. [Получение API-ключа](https://app.datadoghq.eu/account/settings#api)

---

## 1. Подключение Docker-интеграции

Данная интеграция позволяет мониторить состояние запущенных на сервере контейнеров (на достаточно высоком уровне абстракции: CPU, RAM, I/O и т.д.), не анализируя специфичные для запущенных в контейнерах приложений метрики.

***./docker-compose.yml:***

```yaml
version: '3.3'
services:
    ...other services...

    datadog-agent:
        image: datadog/agent:7.26.0-jmx
        env_file:
            - ./datadog/.env
        volumes:
            - /var/run/docker.sock:/var/run/docker.sock:ro  # с помощью вольюмов осуществляется
            - /proc/:/host/proc/:ro                         # сбор метрик с контейнеров/сервера
            - /sys/fs/cgroup/:/host/sys/fs/cgroup:ro

    ...more other services...
```

***./datadog.env:***

```yaml
DD_API_KEY=<YOUR_DATADOG_API_KEY>
DD_SITE=<YOUR_DATADOG_DOMEN>

DD_PROCESS_AGENT_ENABLED=true   # позволяет просматривать процессы сервера/контейнеров в DataDog
```

Результаты настроек доступны по [ссылке](https://app.datadoghq.eu/containers):

*Ссылки*:

1. [Документация](https://docs.datadoghq.com/integrations/faq/compose-and-the-datadog-agent/) по базовой настройке связки DataDog/Docker/Docker Compose;
2. Базовая [документация](https://docs.datadoghq.com/agent/docker/?tab=standard) по Datadog Agent.

<br>

## 2. Подключение Redis-интеграции

Данная интеграция позволяет отслеживать специфичные для Redis метрики (количество команд в секунду, количество используемой памяти и т.д.) и его логи.

***./docker-compose.yml:***

```yaml
version: '3.3'
services:
    ...other services...

    redis:
        build:                          # кастомный образ необходим для задания
            context: ./redis            # Redis кастомного файла настроек
            dockerfile: ./Dockerfile
        ports:
            - 6379:6379
        volumes:
            - ./redis_logs:/redis_logs  # вольюм для хранения папки (файла) с логами
        labels:
            com.datadoghq.ad.check_names: '["redisdb"]'    # на основе этого лейбла DataDog определяет, какое приложение работает в контейнере (не менять!)
            com.datadoghq.ad.init_configs: '[{}]'   # инициализирующие настройки для взаимодействия DataDog и Redis (не менять!)
            com.datadoghq.ad.instances: >-  # основной блок настройки соединения DataDog и Redis
                [{
                    "host": "%%host%%", # вместо этой шаблонной переменной DataDog подставляет IP-адрес контейнера с Redis
                    "port": "%%port%%",   # порт Redis
                    "password": "%%env_REDIS_PASSWORD%%"   # пароль от Redis
                    "collect_client_metrics": "true", # разрешение сбора метрик от Redis-команды CLIENT
                    "command_stats": "true"     # разрешает сбор INFO COMMANDSTATS Redis

                }]
            com.datadoghq.ad.logs: >-
                [{
                    "type": "file", # тип источника логов
                    "source": "redis", # название интеграции (не менять!)
                    "service": "redis",  # имя сервиса для отображение в UI DataDog
                    "path": "/redis_logs/redis.log",  # путь до файла с логами (внутри контейнера DataDog-агента!)
                    "log_processing_rules": [{  # блок правил обработки логов
                        "type": "multi_line",   # сообщение DataDog`у о том, что логи могут быть многострочными
                        "name": "logs",
                        "pattern" : "\\d{1}:\\w{1}\\s{1" # паттерн начала унарного лог-сообщения
                    }]
                }]

    datadog-agent:
        image: datadog/agent:7.26.0-jmx
        env_file:
            - ./datadog.env
        volumes:
            - /var/run/docker.sock:/var/run/docker.sock:ro
            - /proc/:/host/proc/:ro
            - /sys/fs/cgroup/:/host/sys/fs/cgroup:ro
            - /opt/datadog-agent/run:/opt/datadog-agent/run:rw  # вольюм позволяет сохранять логи локально на случай непредвиденных ситуаций
            - ./redis_logs:/redis_logs    # вольюм прокидывает логи Redis-контейнера в DataDog-контейнер

    ...more other services...
```

***./redis/Dockerfile:***

```Dockerfile
FROM redis:6.2.1

RUN mkdir ./redis_logs          # создание директории
RUN chmod -R 777 /redis_logs    # для лог-файла с необходимыми правами

COPY redis.conf /usr/local/etc/redis/redis.conf     # копирование кастомного конфиг-файла для Redis

CMD [ "redis-server", "/usr/local/etc/redis/redis.conf" ]
```

***./redis/redis.conf:***

```configuration
...other configs...

requirepass <REDIS_PASSWORD>
loglevel debug
logfile "/redis_logs/redis.log"     # путь до лог-файла
# bind 127.0.0.1    # разрешает прослушивать все интерфейсы на сервере Redis

...more other configs...
```

***./datadog.env:***

```yaml
DD_API_KEY=<DATADOG_API_KEY>
DD_SITE=<DATADOG_DOMEN>

REDIS_PASSWORD=<REDIS_PASSWORD>   # пароль от Redis (такой же, как и в конфиге Redis)

DD_PROCESS_AGENT_ENABLED=true   # позволяет DataDog-агенту просматривать процессы сервера/контейнеров в DataDog
DD_LOGS_ENABLED=true    # позволяет DataDog-агенту собирать логи с сервера/контейнеров
DD_LOGS_CONFIG_CONTAINER_COLLECT_ALL=true   # включает у DataDog-агента сбор логов со всех контейнеров
```

./test_scripts/load_for_redis.sh -- скрипт для создания тестовой нагрузки на Redis для проверки корректности произведенных настроек.

Ссылки:

1. Базовая [документация](https://docs.datadoghq.com/integrations/redisdb/?tab=docker) по настройке Redis-интеграции в Docker;
2. Примеры [redis.conf](https://redis.io/topics/config) с подробным описанием настроек;
3. [Статья](https://docs.datadoghq.com/agent/docker/log/?tab=dockercompose) по настройке логирования DataDog-агентом;
4. [Статья](https://docs.datadoghq.com/agent/docker/integrations/?tab=docker) по настройке автообнаружения интеграций DataDog-агентом;
5. [Параметры](https://github.com/DataDog/integrations-core/blob/master/redisdb/datadog_checks/redisdb/data/conf.yaml.example) настройки Redis в Datadog;
6. [Документация](https://docs.datadoghq.com/agent/faq/template_variables/) по шаблонным переменным.

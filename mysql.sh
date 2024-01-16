#!/bin/bash
docker run --name mysql8.0 -e MYSQL_ROOT_PASSWORD=smd013012 -d -i -p 3306:3306 mysql:latest --lower-case-table-names=1
docker run -d --name myredis -p 6379:6379 redis --requirepass "smd013012"

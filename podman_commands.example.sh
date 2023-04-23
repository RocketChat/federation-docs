#!/bin/sh

podman run --name postgres --network rocketchat -d --restart always -e POSTGRES_PASSWORD=27e3786b1d5c8985af8eff61230dd11893626b58bc79efbb -e POSTGRES_USER=matrix -e POSTGRES_DB=rocketchat -e POSTGRES_INITDB_ARGS=--encoding='UTF8' --lc-collate='C' --lc-ctype='C' -e UID=1000 -e GID=1000 -v postgres:/var/lib/postgresql/data docker.io/postgres:14

podman run --name redis --network rocketchat -d --restart always docker.io/redis:latest

podman run --name matrix --network rocketchat -d --restart always -v /home/ubuntu/federation-airgap/conf/registration.yaml:/registration.yaml:z,ro -v /home/ubuntu/federation-airgap/data:/data:z -v /home/ubuntu/federation-airgap/ca2.crt:/ca/ca2.crt.pem:ro,z -v /home/ubuntu/federation-airgap/ca3.crt:/ca/ca3.crt.pem:ro,z -v /home/ubuntu/federation-airgap/ca.crt:/ca/ca.crt.pem:ro,z -e UID=1000 -e GID=1000 docker.io/matrixdotorg/synapse:v1.78.0

podman run --name mongodb --network rocketchat -d --restart always -e ALLOW_EMPTY_PASSWORD=yes -e MONGODB_REPLICA_SET_MODE=primary -e MONGODB_REPLICA_SET_NAME=rs0 -e MONGODB_PORT_NUMBER=27017 -e MONGODB_INITIAL_PRIMARY_HOST=mongodb -e MONGODB_INITIAL_PRIMARY_PORT_NUMBER=27017 -e MONGODB_ADVERTISED_HOSTNAME=mongodb docker.io/bitnami/mongodb:5.0

podman run --name rocketchat --network rocketchat -d --restart always -e ROOT_URL=https://rocketchat.shop -e PORT=3000 -e MONGO_URL=mongodb://mongodb:27017/rocketchat?replicaSet=rs0 -e MONGO_OPLOG_URl=mongodb://mongodb:27017/local?replicaSet=rs0 -v /home/ubuntu/federation-airgap/conf/registration.yaml:/app/matrix-federation-config/registration.yaml:z,ro --expose 3000 docker.io/rocketchat/rocket.chat:6.0.0

podman run --name proxy --network rocketchat -d --restart always -v /home/ubuntu/federation-airgap/cert.pem:/tls/rocketchat.shop.pem:z,ro -v /home/ubuntu/federation-airgap/private.key:/tls/rocketchat.shop.key:z,ro -v /home/ubuntu/federation-airgap/conf/nginx.conf:/etc/nginx/conf.d/rocketchat.conf:z,ro -p 80:80 -p 443:443 docker.io/nginx:latest

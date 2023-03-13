services:
  proxy:
    image: ${NGINX_IMAGE}
    container_name: ${NGINX_CONTAINER}
    ports:
      - 80:80
      - 443:443
    volumes:
      - ${DOMAIN_CERTIFICATE_PATH}:/tls/${DOMAIN}.pem:z,ro
      - ${DOMAIN_KEY_PATH}:/tls/${DOMAIN}.key:z,ro

      - ./conf/nginx.conf:/etc/nginx/conf.d/rocketchat.conf:z,ro

  rocketchat:
    image: ${ROCKETCHAT_IMAGE}
    container_name: ${ROCKETCHAT_CONTAINER}
    environment:
      ROOT_URL: https://${DOMAIN}
      PORT: 3000
      MONGO_URL: mongodb://mongodb:27017/rocketchat?replicaSet=rs0
      MONGO_OPLOG_URL: mongodb://mongodb:27017/local?replicaSet=rs0
    expose:
      - 3000
  mongodb:
    image: ${MONGO_IMAGE}
    container_name: ${MONGO_CONTAINER}
    restart: on-failure
    volumes:
      - ${MONGODB_VOLUME}:/bitnami/mongodb
    environment:
      MONGODB_REPLICA_SET_MODE: primary
      MONGODB_REPLICA_SET_NAME: ${MONGODB_REPLICA_SET_NAME:-rs0}
      MONGODB_PORT_NUMBER: ${MONGODB_PORT_NUMBER:-27017}
      MONGODB_INITIAL_PRIMARY_HOST: ${MONGODB_INITIAL_PRIMARY_HOST:-mongodb}
      MONGODB_INITIAL_PRIMARY_PORT_NUMBER: ${MONGODB_INITIAL_PRIMARY_PORT_NUMBER:-27017}
      MONGODB_ADVERTISED_HOSTNAME: ${MONGODB_ADVERTISED_HOSTNAME:-mongodb}
      MONGODB_ENABLE_JOURNAL: ${MONGODB_ENABLE_JOURNAL:-true}
      ALLOW_EMPTY_PASSWORD: ${ALLOW_EMPTY_PASSWORD:-yes}

  matrix:
    image: ${SYNAPSE_IMAGE}
    container_name: ${SYNAPSE_CONTAINER}
    environment:
      SYANPSE_SERVER_NAME: ${MATRIX_DOMAIN}
    volumes:
      - ${MATRIX_VOLUME}:/data:z
      - ${CA_CERTIIFICATE_PATH}:/ca_certificate.pem:z,ro

      - ./conf/registration.yaml:/registration.yaml:z,ro
  postgres:
    image: ${POSTGRES_IMAGE}
    container_name: ${POSTGRES_CONTAINER}
    restart: always
    environment:
      POSTGRES_USER: matrix
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
      POSTGRES_DB: rocketchat
      POSTGRES_INITDB_ARGS: "--encoding='UTF8' --lc-collate='C' --lc-ctype='C'"
    volumes:
      - ${POSTGRES_VOLUME}:/var/lib/postgresql/data
  redis:
    image: ${REDIS_IMAGE}
    container_name: ${REDIS_CONTAINER}
    restart: always


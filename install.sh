#!/usr/bin/env bash

set -Eeuo pipefail

readonly rocketchat_container_name="${ROCKETCHAT_CONTAINER:-rocketchat}"
readonly mongodb_container_name="${MONGO_CONTAINER:-mongodb}"
readonly matrix_container_name="${MATRIX_CONTAINER:-matrix}"
readonly proxy_container_name="${PROXY_CONTAINER:-proxy}"
readonly postgres_container_name="${POSTGRES_CONTAINER:-postgres}"
readonly redis_container_name="${REDIS_CONTAINER:-redis}"

declare -A volumes=(["matrix"]="$PWD/data" ["postgres"]="rocketchat_matrix_postgres" ["mongodb"]="rocketchat_mongodb")

help() {
    cat <<EOF
Usage: ./install.sh --ca-certificate [path to ca cert] --certificate [path to cert] --private key [path to private key] --domain [domain] [...args]

       --ca-certificate         path (relative or absolute) to your CA certificate
       --domain                 your room domain, or on which domain your Rocket.Chat instance will live
       --certificate            path to your CA signed certificate
       --private-key            path to your certificate's private key

[Optional]

        --ca-private-key        private key of your CA, used to auto generate a certificate (don't pass certificate or private key if using this)
        --matrix-subdomain      subdomain on which your matrix server will live (defaults to "matrix")
        --mongo-version         mongodb version (defaults to 5.0)
        --rocketchat-version    defaults to 6.0.0
        --synapse-version       defaults to v1.78.0
        --podman-compose        use podman-compose instead of podman commands
EOF
}

error() {
    echo "[ERROR] $*" >&2
    exit 1
}

info() {
    echo "[INFO] $*"
}

command_exists() {
    command -v "$1" &>/dev/null
}

init() {
    info "Creating usable configs from templates"
    find conf -type f -iname "*.tpl" -exec sh -c '\cp -f ${1} ${1%.*}' -- {} \; # remove the .tpl
    command_exists "podman"
    if ((podman_compose)); then
        command_exists "podman-compose"
        for volume in "${!volumes[@]}"; do
            if [[ ${volumes[$volume]} =~ ^/ ]]; then
                info "Creating ${volumes[$volume]} for ${volume}'s storage"
                [[ -d "${volumes[$volume]}" ]] || mkdir "${volumes[$volume]}"
                continue
            fi
        done
        return
    fi
    podman network exists rocketchat || podman network create rocketchat
    for volume in "${!volumes[@]}"; do
        info "Creating volume for $volume ${volumes[$volume]}"
        if [[ ${volumes[$volume]} =~ ^/ ]]; then
            info "Creating ${volumes[$volume]} for ${volume}'s storage"
            [[ -d "${volumes[$volume]}" ]] || mkdir "${volumes[$volume]}"
            continue
        fi
        if podman volume exists "${volumes[$volume]}"; then
            read -p "a volume named ${volumes[$volume]} aready exists, exter a different name: " vol
            volumes[$volume]=$vol
        fi
        podman volume create "${volumes[$volume]}" >/dev/null
    done
}

podman_run() {
    local name="${1?}"
    shift
    podman run --name "$name" --network rocketchat \
        -d --restart always "$@"
}

podman_compose_run() {
    podman-compose -f conf/podman-compose.yaml up -d "$@"
}

replace_in_file() {
    # @params file, to replace, value
    local file="${1?}"
    local to_replace="${2?}"
    local value="${3?}"
    sed -iE "s/${to_replace//\//\\\/}/${value//\//\\\/}/g" "$file"
}

template_put() {
    # @params file, to replace, value
    local file="${1?}"
    local to_replace="${2?}"
    local value="${3?}"
    sed -iE "s/%%${to_replace//\//\\\/}%%/${value//\//\\\/}/g" "$file"
}

add_environment() {
    # @params variable, value
    if ! [[ -f ./conf/.env ]]; then touch ./conf/.env; fi
    local variable="${1?}"
    local value="${2?}"
    if grep -qE "^$variable" ./conf/.env; then
        local curr_value="$(bash -c "source ./conf/.env; eval echo \$$variable")"
        if [[ "$value" == "$curr_value" ]]; then return; fi
        replace_in_file ./conf/.env "$curr_value" "$value"
        return
    fi
    printf "%s=%s\n" "$variable" "$value" >>./conf/.env
}

add_dotenv_seperator() {
    echo >>./conf/.env
}

verify_certificate() {
    local cert="${1?certificate path required}"
    shift
    [[ -f "$cert" ]] || error "$cert not found"
    readarray -t names < <(openssl x509 -noout -ext subjectAltName -in "$cert" | grep -E '^ *DNS' | sed 's/^[[:space:]]*//; s/,//; s/ /\n/; s/DNS://g')
    local domain
    for domain in "$@"; do
        if ! [[ "${names[*]}" =~ [[:blank:]]?${domain}[[:blank:]]? ]]; then
            error "$domain not found in cetificare SANs"
        fi
    done
}

_setup_mongodb() {
    if ((podman_compose)); then
        add_environment MONGO_IMAGE "$mongo_image"
        add_environment MONGO_CONTAINER "$mongodb_container_name"
        add_environment MONGO_VOLUME "${volumes[mongodb]}"
        add_dotenv_seperator
        podman_compose_run mongodb
        return
    fi
    podman_run \
        "$mongodb_container_name" \
        -e ALLOW_EMPTY_PASSWORD=yes -e MONGODB_REPLICA_SET_MODE=primary \
        -e MONGODB_REPLICA_SET_NAME=rs0 -e MONGODB_PORT_NUMBER=27017 \
        -e MONGODB_INITIAL_PRIMARY_HOST="$mongodb_container_name" -e MONGODB_INITIAL_PRIMARY_PORT_NUMBER=27017 \
        -e MONGODB_ADVERTISED_HOSTNAME="$mongodb_container_name" "$mongo_image"
}

setup_rocketchat() {
    # @params domain_root
    local domain="${1?}"
    _setup_mongodb "$mongo_version"
    if ((podman_compose)); then
        add_environment ROCKETCHAT_IMAGE "$rocketchat_image"
        add_environment ROCKETCHAT_CONTAINER "$rocketchat_container_name"
        add_environment DOMAIN "$domain"
        podman_compose_run rocketchat
        add_dotenv_seperator
        return
    fi
    podman_run \
        "$rocketchat_container_name" \
        -e ROOT_URL="https://$domain" -e PORT=3000 \
        -e MONGO_URL=mongodb://mongodb:27017/rocketchat?replicaSet=rs0 \
        -e MONGO_OPLOG_URl=mongodb://mongodb:27017/local?replicaSet=rs0 \
        -v "$PWD/conf/registration.yaml:/app/matrix-federation-config/registration.yaml:z,ro" \
        --expose 3000 "$rocketchat_image" # TODO
}

setup_matrix() {
    # @params homeserver domain, ca certificate path
    local domain="${1?}"
    local ca_certificate="${2?}"

    info "Generating tokens for app service"
    local homeserver_token="$(openssl rand -hex 24)"
    local appservice_token="$(openssl rand -hex 24)"
    local unique_id="$(openssl rand -hex 8)"
    template_put ./conf/registration.yaml unique_id "$unique_id"
    template_put ./conf/registration.yaml homeserver_token "$homeserver_token"
    template_put ./conf/registration.yaml appservice_token "$appservice_token"
    template_put ./conf/registration.yaml rocketchat_container "$rocketchat_container_name"
    template_put ./conf/registration.yaml matrix_container "$matrix_container_name"
    template_put ./conf/registration.yaml matrix_domain "$domain"
    local maybe=
    while ! [[ ${maybe,,} =~ ^true|false$ ]]; do read -p "Would you like to share typing events between two federated instances? (it may affect performance [true|false]): " maybe; done
    template_put ./conf/registration.yaml share_ephemeral_updates "$maybe"

    info "Generating postgresql password"
    local postgres_password="$(openssl rand -hex 24)"
    template_put ./conf/homeserver.append.yaml synapse_password "$postgres_password"
    template_put ./conf/homeserver.append.yaml postgres_container "$postgres_container_name"
    template_put ./conf/homeserver.append.yaml redis_container "$redis_container_name"

    info "Generating synapse default config"
    # generate in volume
    podman run --rm \
        -v "${volumes[matrix]}:/data:z" \
        -e SYNAPSE_SERVER_NAME="$domain" -e SYNAPSE_REPORT_STATS="yes" \
        -e UID="$(id -u)" -e GID="$(id -g)" \
        "$synapse_image" generate

    info "Appending default homeserver.yaml"
    echo >>./data/homeserver.yaml
    \cat conf/homeserver.append.yaml >>./data/homeserver.yaml
    if ((podman_compose)); then
        info "Using podman-compose to manage matrix containers"
        add_environment POSTGRES_PASSWORD "$postgres_password"
        add_environment CA_CERTIFICATE_PATH "$ca_certificate"
        add_environment POSTGRES_IMAGE "$postgres_image"
        add_environment POSTGRES_CONTAINER "$postgres_container_name"
        add_environment REDIS_CONTAINER "$redis_container_name"
        add_environment REDIS_IMAGE "$redis_image"
        add_environment SYNAPSE_CONTAINER "$matrix_container_name"
        add_environment SYNAPSE_IMAGE "$synapse_image"
        add_environment MATRIX_VOLUME "${volumes[matrix]}"
        add_environment POSTGRES_VOLUME "${volumes[postgres]}"
        add_dotenv_seperator
        podman_compose_run redis postgres matrix
        return
    fi
    info "Using podman cli to manage matrix containers"
    podman_run "$postgres_container_name" \
        -e POSTGRES_PASSWORD="$postgres_password" -e POSTGRES_USER=matrix \
        -e POSTGRES_DB=rocketchat -e POSTGRES_INITDB_ARGS="--encoding='UTF8' --lc-collate='C' --lc-ctype='C'" \
        -e UID="$(id -u)" -e GID="$(id -g)" \
        -v "${volumes[postgres]}:/var/lib/postgresql/data" "${postgres_image}"
    podman_run "$redis_container_name" "$redis_image"
    podman_run "$matrix_container_name" \
        -e UID="$(id -u)" -e GID="$(id -g)" \
        -v "$ca_certificate:/ca_certificate.pem:z,ro" \
        -v "$PWD/conf/registration.yaml:/registration.yaml:z,ro" \
        -v "${volumes[matrix]}:/data:z" "$synapse_image"
}

setup_proxy() {
    # @params domain, matrix subdomain, certificate, key
    local domain="${1?}"
    local matrix_subdomain="${2?}"
    local certificate="${3?}"
    local key="${4?}"

    template_put ./conf/nginx.conf domain "$domain"
    template_put ./conf/nginx.conf rocketchat_container "$rocketchat_container_name"
    template_put ./conf/nginx.conf matrix_container "$matrix_container_name"
    template_put ./conf/nginx.conf matrix_subdomain "$matrix_subdomain"

    if ((podman_compose)); then
        add_environment DOMAIN_CERTIFICATE_PATH "$(realpath "$certificate")"
        add_environment DOMAIN_KEY_PATH "$(realpath "$key")"
        add_environment NGINX_IMAGE "$nginx_image"
        add_environment NGINX_CONTAINER "$proxy_container_name"
        add_dotenv_seperator
        podman_compose_run proxy
        return
    fi
    # this needs to start last or else nginx will fail to resolve the container names on the
    podman_run "$proxy_container_name" \
        -v "$(realpath "$certificate"):/tls/$domain.pem:z,ro" \
        -v "$(realpath "$key"):/tls/$domain.key:z,ro" \
        -v "$PWD/conf/nginx.conf:/etc/nginx/conf.d/rocketchat.conf:z,ro" \
        -p 80:80 -p 443:443 "$nginx_image"
}

_generate_certs() {
    #@params ca, ca private key, domains
    local ca="${1?}"
    local ca_private_key="${2}"
    shift 2

    local subject_alt_names=

    local domain
    local idx=0
    for domain in "$@"; do
        subject_alt_names+="DNS.$idx = $domain"$'\n'
        : $((idx++))
    done

    openssl genrsa -out private.key 2048
    openssl req -new -key private.key -subj "/C=IN/CN=$1" -out req.csr
    cat <<EOF >"/tmp/$1.ext"
authorityKeyIdentifier=keyid,issuer
basicConstraints=CA:FALSE
keyUsage = digitalSignature, nonRepudiation, keyEncipherment, dataEncipherment
subjectAltName = @alt_names

[alt_names]
$subject_alt_names
EOF
    openssl x509 -req -in req.csr -CA "$ca" -CAkey "$ca_private_key" -CAcreateserial \
        -out cert.pem -days 365 -extfile "/tmp/$1.ext"
    # overwrite the existing values
    certificate="$(realpath cert.pem)"
    private_key="$(realpath private.key)"
}

main() {
    local \
        domain \
        certificate \
        private_key \
        matrix_subdomain \
        ca_cert \
        ca_private_key \
        mongo_version \
        rocketchat_version \
        synapse_version

    declare -g podman_compose=0

    if [[ "$*" =~ --help ]]; then
        help
        exit 0
    fi

    while [[ -n "${1:-}" ]]; do
        case "$1" in
            --ca-certificate)
                ca_cert="$(realpath "$2")"
                shift 2
                ;;
            --ca-private-key)
                ca_private_key="$(realpath $2)"
                shift 2
                ;;
            --certificate)
                certificate="$(realpath $2)"
                shift 2
                ;;
            --private-key)
                private_key="$(realpath $2)"
                shift 2
                ;;
            --domain)
                domain="$2"
                shift 2
                ;;
            --matrix-subdomain)
                matrix_subdomain="$2"
                shift 2
                ;;
            --podman-compose)
                podman_compose=1
                shift
                ;;
            --mongo-version)
                mongo_version="$2"
                shift 2
                ;;
            --rocketchat-version)
                rocketchat_version="$2"
                shift 2
                ;;
            --synapse-version)
                synapse_version="$2"
                shift 2
                ;;
            *)
                echo "[ERROR] unknown argument $1" >&2
                help
                ;;
        esac
    done

    #"${certificate?must pass a certificate}" \
    : \
        "${mongo_version:=5.0}" \
        "${matrix_subdomain:=matrix}" \
        "${domain?domain value is required}" \
        "${ca_cert?ca certificate path must be passed}" \
        "${rocketchat_version:=6.0.0}" \
        "${synapse_version:=v1.78.0}"

    local domains=("$domain" "$matrix_subdomain.${domain}")

    if [[ -z "${certificate:-}" ]]; then
        _generate_certs "$ca_cert" "${ca_private_key?ca private key required if a certificate is not passed}" "${domains[@]}"
    else : "${private_key?private key must be passed with a certificate or omit both}"; fi

    init

    declare -g rocketchat_image="${ROCKETCHAT_IMAGE:-docker.io/rocketchat/rocket.chat:${rocketchat_version}}"
    declare -g mongo_image="${MONGO_IMAGE:-docker.io/bitnami/mongodb:${mongo_version}}"
    declare -g synapse_image="${SYNAPSE_IMAGE:-docker.io/matrixdotorg/synapse:${synapse_version}}"
    declare -g nginx_image="${NGINX_IMAGE:-docker.io/nginx:latest}"
    declare -g postgres_image="${POSTGRES_IMAGE:-docker.io/postgres:14}"
    declare -g redis_image="${REDIS_IMAGE:-docker.io/redis:latest}"

    setup_matrix "$domain" "$ca_cert"
    setup_rocketchat "$domain"
    setup_proxy "$domain" "$matrix_subdomain.$domain" "$certificate" "$private_key"
}

main "$@"

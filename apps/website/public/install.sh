#!/bin/bash

install_dokploy() {
    HTTP_PORT=${HTTP_PORT:-80}
    HTTPS_PORT=${HTTPS_PORT:-443}
    APP_PORT=${APP_PORT:-3000}

    if [ "$(id -u)" != "0" ]; then
        echo "This script must be run as root" >&2
        exit 1
    fi

    # check if is Mac OS
    if [ "$(uname)" = "Darwin" ]; then
        echo "This script must be run on Linux" >&2
        exit 1
    fi

    # check if is running inside a container
    if [ -f /.dockerenv ]; then
        echo "This script must be run on Linux" >&2
        exit 1
    fi

    # check if something is running on HTTP_PORT (default 80)
    if ss -tulnp | grep ":$HTTP_PORT " >/dev/null; then
        echo "Error: something is already running on port $HTTP_PORT" >&2
        exit 1
    fi

    # check if something is running on HTTPS_PORT (default 443)
    if ss -tulnp | grep ":$HTTPS_PORT " >/dev/null; then
        echo "Error: something is already running on port $HTTPS_PORT" >&2
        exit 1
    fi

    if ss -tulnp | grep ":$APP_PORT " >/dev/null; then
        echo "Error: something is already running on port $APP_PORT" >&2
        exit 1
    fi

    command_exists() {
      command -v "$@" > /dev/null 2>&1
    }

    if command_exists docker; then
      echo "Docker already installed"
    else
      curl -sSL https://get.docker.com | sh
    fi

    docker swarm leave --force 2>/dev/null

    get_ip() {
        # Try to get IPv4
        local ipv4=$(curl -4s https://ifconfig.io 2>/dev/null)

        if [ -n "$ipv4" ]; then
            echo "$ipv4"
        else
            # Try to get IPv6
            local ipv6=$(curl -6s https://ifconfig.io 2>/dev/null)
            if [ -n "$ipv6" ]; then
                echo "$ipv6"
            fi
        fi
    }

    advertise_addr="${ADVERTISE_ADDR:-$(get_ip)}"

    docker swarm init --advertise-addr $advertise_addr
    
     if [ $? -ne 0 ]; then
        echo "Error: Failed to initialize Docker Swarm" >&2
        exit 1
    fi

    echo "Swarm initialized"

    docker network rm -f dokploy-network 2>/dev/null
    docker network create --driver overlay --attachable dokploy-network

    echo "Network created"

    mkdir -p /etc/dokploy

    chmod 777 /etc/dokploy

    docker pull dokploy/dokploy:latest

    # Installation
    docker service create \
      --name dokploy \
      --replicas 1 \
      --network dokploy-network \
      --mount type=bind,source=/var/run/docker.sock,target=/var/run/docker.sock \
      --mount type=bind,source=/etc/dokploy,target=/etc/dokploy \
      --mount type=volume,source=dokploy-docker-config,target=/root/.docker \
      --publish published=$HTTP_PORT,target=80,mode=host \
      --publish published=$HTTPS_PORT,target=443,mode=host \
      --publish published=$APP_PORT,target=3000,mode=host \
      --update-parallelism 1 \
      --update-order stop-first \
      --constraint 'node.role == manager' \
      -e ADVERTISE_ADDR=$advertise_addr \
      -e TRAEFIK_SSL_PORT=$HTTPS_PORT \
      -e TRAEFIK_PORT=$HTTP_PORT \
      dokploy/dokploy:latest

    GREEN="\033[0;32m"
    YELLOW="\033[1;33m"
    BLUE="\033[0;34m"
    NC="\033[0m" # No Color

    format_ip_for_url() {
        local ip="$1"
        if echo "$ip" | grep -q ':'; then
            # IPv6
            echo "[${ip}]"
        else
            # IPv4
            echo "${ip}"
        fi
    }

    formatted_addr=$(format_ip_for_url "$advertise_addr")
    echo ""
    printf "${GREEN}Congratulations, Dokploy is installed!${NC}\n"
    printf "${BLUE}Wait 15 seconds for the server to start${NC}\n"
    printf "${YELLOW}Please go to http://${formatted_addr}:${APP_PORT}${NC}\n\n"
}

update_dokploy() {
    echo "Updating Dokploy..."
    
    # Pull the latest image
    docker pull dokploy/dokploy:latest

    # Update the service
    docker service update --image dokploy/dokploy:latest dokploy

    echo "Dokploy has been updated to the latest version."
}

# Main script execution
if [ "$1" = "update" ]; then
    update_dokploy
else
    install_dokploy
fi

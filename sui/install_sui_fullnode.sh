#!/bin/bash

DOCKER_COMPOSE_VERSION="v2.17.0"

# Install gum
if [[ ! -x "$(command -v gum)" ]]; then
  sudo mkdir -p /etc/apt/keyrings
  curl -fsSL https://repo.charm.sh/apt/gpg.key | sudo gpg --dearmor -o /etc/apt/keyrings/charm.gpg
  echo "deb [signed-by=/etc/apt/keyrings/charm.gpg] https://repo.charm.sh/apt/ * *" | sudo tee /etc/apt/sources.list.d/charm.list
  sudo apt update && sudo apt install -y gum > /dev/null
fi

# Title
gum style --foreground 4 --border-foreground 4 --border double --bold --align center --width 50 --margin "2 20" --padding "1 1" 'SUI NODE INSTALLER' 'by Darksiders Staking'

# Choose option
USER_PICK=$(gum choose --cursor.foreground=4 "Install fullnode" "Install fullnode + monitoring")


# Install docker
if [[ ! -x "$(command -v docker)" ]]; then
  sudo apt-get update > /dev/null
  gum style --foreground 4 --align left --margin "1 1" "Docker not installed. Installing..."
  sudo apt-get remove docker docker-engine docker.io containerd runc > /dev/null
  sudo apt-get install -y curl > /dev/null
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
  echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
  sudo apt-get update > /dev/null
  sudo apt-get install -y docker-ce docker-ce-cli containerd.io > /dev/null
  gum style --foreground 4 --align left --margin "1 1" "Done! $(docker --version)"
else
  gum style --foreground 4 --align left --margin "1 1" "Docker installed. $(docker --version)"
fi


# Install docker-compose
if [[ ! -x "$(command -v docker-compose)" ]]; then
  gum style --foreground 4 --align left --margin "2 2" "Installing docker-compose..."
  curl -sL https://github.com/docker/compose/releases/download/$DOCKER_COMPOSE_VERSION/docker-compose-linux-x86_64 -o docker-compose
  chmod +x docker-compose
  sudo mv docker-compose /usr/local/bin
  gum style --foreground 4 --align left --margin "1 1" "Done! Docker-compose version: $(docker-compose --version | cut -d ' ' -f 4)"
else
  gum style --foreground 4 --align left --margin "1 1" "Docker-compose installed. Docker-compose version: $(docker-compose --version | cut -d ' ' -f 4)"
fi


# Create config files
if [[ -d $HOME/.sui ]]; then
  cd $HOME/.sui
  docker-compose down
else
  mkdir $HOME/.sui
fi
cd $HOME/.sui


# Create docker-compose file
echo 'version: "3.9"

volumes:
  suidb:
  prometheus_data:
  grafana_data:

networks:
  sui-net:
    driver: bridge

services:
  fullnode:
    image: lexprime/sui:latest
    container_name: sui-node
    restart: on-failure
    ports:
      - "8084:8084/udp"
      - "9000:9000"
      - "9184:9184"
    expose:
      - 9000
    networks:
      - sui-net
    volumes:
      - ./fullnode-template.yaml:/sui/fullnode.yaml:ro
      - ./genesis.blob:/sui/genesis.blob:ro
      - suidb:/sui/db:rw
    command: ["/usr/local/bin/sui-node", "--config-path", "fullnode.yaml"]

  prometheus:
    image: prom/prometheus
    container_name: prometheus
    restart: on-failure
    expose:
      - 9090
    networks:
      - sui-net
    volumes:
      - ./prometheus:/etc/prometheus
      - prometheus_data:/prometheus
    command:
      - "--config.file=/etc/prometheus/prometheus.yml"
      - "--storage.tsdb.path=/prometheus"
      - "--web.console.libraries=/etc/prometheus/console_libraries"
      - "--web.console.templates=/etc/prometheus/consoles"
      - "--storage.tsdb.retention.time=200h"
      - "--web.enable-lifecycle"

  node-exporter:
    image: prom/node-exporter
    container_name: node-exporter
    restart: on-failure
    volumes:
      - /proc:/host/proc:ro
      - /sys:/host/sys:ro
      - /:/rootfs:ro
    command:
      - "--path.procfs=/host/proc"
      - "--path.rootfs=/rootfs"
      - "--path.sysfs=/host/sys"
      - "--collector.filesystem.ignored-mount-points=^/(sys|proc|dev|host|etc)($$|/)"
    expose:
      - 9100
    networks:
      - sui-net

  grafana:
    image: grafana/grafana
    container_name: grafana
    volumes:
      - grafana_data:/var/lib/grafana
      - ./grafana/provisioning:/etc/grafana/provisioning
    environment:
      - GF_SECURITY_ADMIN_USER=${GRAFANA_USER:-admin}
      - GF_SECURITY_ADMIN_PASSWORD=${GRAFANA_PASSWORD:-admin}
      - GF_USERS_ALLOW_SIGN_UP=false
      - GF_SECURITY_DISABLE_BRUTE_FORCE_LOGIN_PROTECTION=true
    restart: on-failure
    expose:
      - 3000
    ports:
      - "3555:3000"
    networks:
      - sui-net

  cadvisor:
    image: gcr.io/cadvisor/cadvisor
    container_name: cadvisor
    volumes:
      - /:/rootfs:ro
      - /var/run:/var/run:rw
      - /sys:/sys:ro
      - /var/lib/docker:/var/lib/docker:ro
      - /cgroup:/cgroup:ro
    restart: on-failure
    expose:
      - 8080
    networks:
      - sui-net' > $HOME/.sui/docker-compose.yaml


# Create docker-compose.monitoring file
echo '
volumes:
  prometheus_data:
  grafana_data:

services:
  prometheus:
    image: prom/prometheus
    container_name: prometheus
    restart: on-failure
    expose:
      - 9090
    networks:
      - sui-net
    volumes:
      - ./prometheus:/etc/prometheus
      - prometheus_data:/prometheus
    command:
      - "--config.file=/etc/prometheus/prometheus.yml"
      - "--storage.tsdb.path=/prometheus"
      - "--web.console.libraries=/etc/prometheus/console_libraries"
      - "--web.console.templates=/etc/prometheus/consoles"
      - "--storage.tsdb.retention.time=200h"
      - "--web.enable-lifecycle"

  node-exporter:
    image: prom/node-exporter
    container_name: node-exporter
    restart: on-failure
    volumes:
      - /proc:/host/proc:ro
      - /sys:/host/sys:ro
      - /:/rootfs:ro
    command:
      - "--path.procfs=/host/proc"
      - "--path.rootfs=/rootfs"
      - "--path.sysfs=/host/sys"
      - "--collector.filesystem.ignored-mount-points=^/(sys|proc|dev|host|etc)($$|/)"
    expose:
      - 9100
    networks:
      - sui-net

  grafana:
    image: grafana/grafana
    container_name: grafana
    volumes:
      - grafana_data:/var/lib/grafana
    environment:
      - GF_SECURITY_ADMIN_USER=${GRAFANA_USER:-admin}
      - GF_SECURITY_ADMIN_PASSWORD=${GRAFANA_PASSWORD:-admin}
      - GF_USERS_ALLOW_SIGN_UP=false
      - GF_SECURITY_DISABLE_BRUTE_FORCE_LOGIN_PROTECTION=true
    restart: on-failure
    expose:
      - 3000
    ports:
      - "3555:3000"
    networks:
      - sui-net

  cadvisor:
    image: gcr.io/cadvisor/cadvisor
    container_name: cadvisor
    volumes:
      - /:/rootfs:ro
      - /var/run:/var/run:rw
      - /sys:/sys:ro
      - /var/lib/docker:/var/lib/docker:ro
      - /cgroup:/cgroup:ro
    restart: on-failure
    expose:
      - 8080
    networks:
      - sui-net' > $HOME/.sui/docker-compose.monitoring.yaml


# Create docker-compose.indexer file
echo 'version: "3.9"
volumes:
  postgres_db:

networks:
  sui-net:
    driver: bridge

  postgres:
    image: postgres:15
    container_name: postgres
    restart: on-failure
    environment:
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: postgres
      POSTGRES_DB: sui_indexer_db
    expose:
      - 5432
    networks:
      - sui-net
    volumes:
      - postgres_db:/var/lib/postgresql/data:rw
    command: ["postgres", "-cshared_preload_libraries=pg_stat_statements"]

  indexer:
    image: lexprime/sui:latest
    container_name: sui-indexer
    restart: on-failure
    networks:
      - sui-net
    volumes:
      - ./start_indexer.sh:/sui/start_indexer.sh:ro
    tty: true
    command: ["/bin/bash"]' > $HOME/.sui/docker-compose.indexer.yaml


# Create fullnode config file
tee $HOME/.sui/fullnode-template.yaml > /dev/null <<EOF
# Update this value to the location you want Sui to store its database
db-path: "/sui/db"
network-address: "/dns/localhost/tcp/8084/http"
metrics-address: "0.0.0.0:9184"
# this address is also used for web socket connections
json-rpc-address: "0.0.0.0:9000"
enable-event-processing: true

genesis:
  # Update this to the location of where the genesis file is stored
  genesis-file-location: "/sui/genesis.blob"

authority-store-pruning-config:
  num-latest-epoch-dbs-to-retain: 3
  epoch-db-pruning-period-secs: 3600
  num-epochs-to-retain: 1
  max-checkpoints-in-batch: 200
  max-transactions-in-batch: 1000
  use-range-deletion: true

p2p-config:
  listen-address: "0.0.0.0:8084"
  external-address: "/ip4/$(curl -s ifconfig.me)/udp/8084"
  seed-peers:
   - address: "/dns/sui-rpc-pt.testnet-pride.com/udp/8084"
   - address: "/dns/sui-rpc-testnet.bartestnet.com/udp/8084"
   - address: "/ip4/162.55.84.47/udp/8084"
   - address: "/dns/wave-3.testnet.n1stake.com/udp/8084"
   - address: "/ip4/38.242.197.20/udp/8080"
   - address: "/ip4/178.18.250.62/udp/8080"
EOF


# Get genesis
gum style --foreground 4 --align left --margin "1 1" "Downloading genesis..."
curl -Ls https://github.com/MystenLabs/sui-genesis/raw/main/testnet/genesis.blob > $HOME/.sui/genesis.blob
gum style --foreground 4 --align left --margin "1 1" "Done! Genesis shasum $(sha256sum $HOME/.sui/genesis.blob | cut -d ' ' -f 1)"


# Build docker compose and start
gum style --foreground 4 --align left --margin "1 1" "Creating services..."
if [[ $USER_PICK == "Install fullnode" ]]; then
  docker-compose up -d fullnode
else
  if [[ ! -d $HOME/.sui/prometheus ]]; then
    mkdir $HOME/.sui/prometheus
    mkdir -p $HOME/.sui/grafana/provisioning/dashboards
    curl -Ls https://grafana.com/api/dashboards/18297/revisions/1/download > $HOME/.sui/grafana/provisioning/sui_node.json
    echo 'ApiVersion: 1
datasources:
  - access: proxy
    editable: true
    name: Prometheus
    orgId: 1
    type: prometheus
    url: http://prometheus:9090/
    version: 1' > $HOME/.sui/grafana/provisioning/datasources/prometheus.yml
  fi
  echo "global:
    scrape_interval:     15s
    evaluation_interval: 15s

# Load and evaluate rules in this file every 'evaluation_interval' seconds.
rule_files:
  - "alert.rules"

# A scrape configuration containing exactly one endpoint to scrape.
scrape_configs:
  - job_name: 'node-exporter'
    scrape_interval: 5s
    static_configs:
      - targets: ['node-exporter:9100']

  - job_name: 'cadvisor'
    scrape_interval: 5s
    static_configs:
      - targets: ['cadvisor:8080']

  - job_name: 'prometheus'
    scrape_interval: 10s
    static_configs:
      - targets: ['localhost:9090']

  - job_name: 'sui-node'
    scrape_interval: 10s
    metrics_path: /metrics
    static_configs:
      - targets: ['fullnode:9184']

  - job_name: 'grafana'
    scrape_interval: 5s
    static_configs:
      - targets: ['grafana:3000']" > $HOME/.sui/prometheus/prometheus.yml
  docker-compose up -d
fi

# Complete
gum style --foreground 4 --align left --margin "1 1" "Setup complete!"
gum style --foreground 4 --align left --margin "1 1" "Check logs with docker logs -f sui-node"

# Credits
gum style --foreground 4 --border-foreground 4 --border double --bold --align center --width 50 --margin "2 20" --padding "1 1" 'Created by Lex_Prime from Darksiders Staking' 'Please follow me on' 'Github: https://github.com/LexPrime' 'Twitter: https://twitter.com/Lex__Prime' 'Medium: https://medium.com/@lexprime'

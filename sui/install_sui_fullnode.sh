#!/bin/bash

DOCKER_COMPOSE_VERSION="v2.17.0"

# Install docker
sudo apt-get update > /dev/null
if [[ ! -x "$(command -v docker)" ]]; then
  echo -e "Docker not installed. Installing..."
  sudo apt-get remove docker docker-engine docker.io containerd runc > /dev/null
  sudo apt-get install -y curl
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
  echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
  sudo apt-get update > /dev/null
  sudo apt-get install -y docker-ce docker-ce-cli containerd.io > /dev/null
  echo -e "Done! $(docker --version)"
else
  echo -e "Docker installed. $(docker --version)"
fi


# Install docker-compose
if [[ ! -x "$(command -v docker)" ]]; then
  echo -e "Installing docker-compose..."
  curl -sL https://github.com/docker/compose/releases/download/$DOCKER_COMPOSE_VERSION/docker-compose-linux-x86_64 -o docker-compose
  chmod +x docker-compose
  sudo mv docker-compose /usr/local/bin
  echo -e "Done! Docker-compose version: $(docker-compose --version | cut -d ' ' -f 4)"
else
  echo -e "Docker-compose installed. Docker-compose version: $(docker-compose --version | cut -d ' ' -f 4)"
fi


# Create config files
if [[ -d $HOME/.sui ]]; then
  echo -e "Sui folder exist"
else
  mkdir $HOME/.sui
fi

echo '
version: "3.9"
services:
  fullnode:
    image: lexprime/sui:latest
    container_name: sui-node
    ports:
      - "8084:8084/udp"
      - "9000:9000"
      - "9184:9184"
    volumes:
      - ./fullnode-template.yaml:/sui/fullnode.yaml:ro
      - ./genesis.blob:/sui/genesis.blob:ro
      - suidb:/sui/db:rw
    command: ["/usr/local/bin/sui-node", "--config-path", "fullnode.yaml"]
volumes:
  suidb:' > $HOME/.sui/docker-compose.yaml


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
echo -e "Downloading genesis..."
curl -Ls https://github.com/MystenLabs/sui-genesis/raw/main/testnet/genesis.blob > $HOME/.sui/genesis.blob
echo -e "Done! Genesis shasum $(sha256sum $HOME/.sui/genesis.blob)"


# Start sui-node
cd $HOME/.sui
docker-compose up -d
echo -e "Setup complete! Check logs with docker logs -f sui-node"

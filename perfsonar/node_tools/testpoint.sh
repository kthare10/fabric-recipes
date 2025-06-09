#!/bin/bash

# Check arguments
if [ $# -ne 3 ]; then
    echo "Usage: $0 <NODE1_ADDR> <TOKEN> <FREQUENCY_IN_HOURS>"
    exit 1
fi

NODE1_ADDR="$1"
TOKEN="$2"
FREQUENCY_IN_HOURS="$3"

# Step 1: Clone the repository
if [ ! -d "perfsonar-extensions" ]; then
    git clone https://github.com/kthare10/perfsonar-extensions.git || {
        echo "Failed to clone repository." >&2
        exit 1
    }
fi

cd perfsonar-extensions || exit 1

# Step 2: Configure environment
cat <<EOF > .env
HOST_IP=${NODE1_ADDR}
HOSTS=${NODE1_ADDR}
URL=http://${NODE1_ADDR}:8000/api/save/
AUTH_TOKEN=${TOKEN}
CRON_EXPRESSION=0 */${FREQUENCY_IN_HOURS} * * *
EOF

# Step 3: Launch the perfsonar-testpoint container using Docker Compose
docker compose up -d perfsonar-testpoint || {
    echo "Docker compose failed to start perfsonar-testpoint." >&2
    exit 1
}

# Step 4: Run the bootstrap cron script and verify crontab
docker exec perfsonar-testpoint /bin/bash /etc/cron.hourly/bootstrap_cron.sh

docker exec perfsonar-testpoint crontab -l

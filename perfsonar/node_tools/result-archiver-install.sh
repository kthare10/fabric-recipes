#!/bin/bash

set -e


# Step 2: Clone the pscheduler-result-archiver repo
git clone https://github.com/kthare10/pscheduler-result-archiver.git

# Step 3: Run docker compose
cd pscheduler-result-archiver && docker compose up -d

cd pscheduler-result-archiver && pip install -r requirements.txt


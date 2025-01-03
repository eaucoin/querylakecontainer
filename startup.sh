#!/bin/bash

# Start the database in the background
docker run \
  --name querylake_db \
  -e POSTGRES_USER="querylake_access" \
  -e POSTGRES_PASSWORD="querylake_access_password" \
  -e POSTGRES_DB="querylake_database" \
  -v querylake_database_volume:/var/lib/postgresql/data/ \
  -d \
  paradedb/paradedb:latest &

# Wait for the database to be ready
# You might need a more robust check here
sleep 10

# Start the Ray Serve application
serve run server:deployment &

# Start the Next.js frontend
cd /app/frontend
npm run start
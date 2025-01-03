#!/bin/bash

# Set environment variables (replace with your actual values)
RESOURCE_GROUP="FMOL-BIS-CustomProgramming"
LOCATION="southcentralus"
ENVIRONMENT_NAME="my-environment" # Choose a name for your environment
CONTAINER_APP_NAME="querylake-app" # Choose a name for your container app
REGISTRY_NAME="querylake"
# Image name is important, as it must match with the image name used in the azd up command
IMAGE_NAME="${REGISTRY_NAME}.azurecr.io/querylake:latest"
# Generate a strong secret key for OAUTH_SECRET_KEY
OAUTH_SECRET_KEY=$(openssl rand -base64 32)

# Log in to Azure
az login

# Build and push the Docker image
docker build -t $IMAGE_NAME .
az acr login --name $REGISTRY_NAME
docker push $IMAGE_NAME

# Create the Container Apps environment if it doesn't exist
az containerapp env show --name $ENVIRONMENT_NAME --resource-group $RESOURCE_GROUP || \
az containerapp env create \
  --name $ENVIRONMENT_NAME \
  --resource-group $RESOURCE_GROUP \
  --location "$LOCATION" \
  --enable-workload-profiles

# Create the Container App using 'az containerapp create' for more control
az containerapp create \
  --name $CONTAINER_APP_NAME \
  --resource-group $RESOURCE_GROUP \
  --environment $ENVIRONMENT_NAME \
  --image $IMAGE_NAME \
  --target-port 3001 \
  --ingress external \
  --env-vars \
    POSTGRES_USER=querylake_access \
    POSTGRES_PASSWORD=querylake_access_password \
    POSTGRES_DB=querylake_database \
    NEXT_PUBLIC_APP_URL=http://localhost:8001 \
    OAUTH_SECRET_KEY=secretref:oauth-secret-key \
    "CONFIG_FILE=$(cat ./backend/config.json | base64)" \
  --secrets oauth-secret-key=$OAUTH_SECRET_KEY \
  --workload-profile-name "Consumption-GPUNC8as-T4" \
  --min-replicas 1 \
  --max-replicas 1

echo "Application deployed. Access it at: $(az containerapp show --resource-group $RESOURCE_GROUP --name $CONTAINER_APP_NAME --query properties.configuration.ingress.fqdn -o tsv)"
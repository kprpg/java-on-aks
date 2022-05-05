az login -t 72f988bf-86f1-41af-91ab-2d7cd011db47 --use-device-code -o table
az account set -s '0c378775-d18a-45bb-b426-3627de556dd1'  ## sub1
az account set -s 'ce8e7a90-6ff0-4074-8417-a55e6cac276f'  ## sub2
echo "Defining variables..."

source .scripts/setup-env-variables-azure.sh

# Create a Resource Group
az group create --name ${RESOURCE_GROUP} \
    --location ${REGION}

# Create a Cosmos DB account
az cosmosdb create --kind MongoDB \
    --resource-group ${RESOURCE_GROUP} \
    --name ${MONGODB_USER}
# Get Cosmos DB connection strings  
az cosmosdb list-connection-strings --resource-group ${RESOURCE_GROUP} \
    --name ${MONGODB_USER} 


# https://docs.bitnami.com/azure/infrastructure/rabbitmq/get-started/understand-default-config/
az vm open-port --port 5672 --name ${RABBITMQ_VM_NAME} \
    --resource-group ${RABBITMQ_RESOURCE_GROUP}
az vm open-port --port 15672 --name ${RABBITMQ_VM_NAME} \
    --resource-group ${RABBITMQ_RESOURCE_GROUP} --priority 1100


## ACCOUNT_SERVICE_PASSWORD# Create a Resource Group, if you have not created one
az group create --name ${RESOURCE_GROUP} \
    --location ${REGION}
    
# Create Azure Container Registry
az acr create --name ${CONTAINER_REGISTRY} \
    --resource-group ${RESOURCE_GROUP} \
    --sku basic --location ${REGION}
    
# Log into Azure Container Registry
az acr login -n ${CONTAINER_REGISTRY}

## AKS_CLUSTER
az aks create --name ${AKS_CLUSTER} \
    --resource-group ${RESOURCE_GROUP} \
    --location ${REGION} \
    --attach-acr ${CONTAINER_REGISTRY} \
    --node-vm-size Standard_DS3_v2 \
    --node-count 5

## AKS Creds
az aks get-credentials --name ${AKS_CLUSTER} \
    --resource-group ${RESOURCE_GROUP}


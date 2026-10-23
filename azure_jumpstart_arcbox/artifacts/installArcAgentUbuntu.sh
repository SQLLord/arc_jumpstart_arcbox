#!/bin/sh

# Block Azure IMDS
sudo ufw --force enable
sudo ufw deny out from any to 169.254.169.254
sudo ufw default allow incoming

# Download the installation package and install the hybrid agent, retrying transient download failures
for attempt in 1 2 3; do
    if wget https://aka.ms/azcmagent -O ~/install_linux_azcmagent.sh && bash ~/install_linux_azcmagent.sh; then
        break
    fi
    echo "Installing the Azure Connected Machine agent failed (attempt $attempt of 3)"
    if [ "$attempt" -lt 3 ]; then sleep $((30 * attempt)); fi
done

ArcServerResourceName=$(hostname |sed -e "s/\b\(.\)/\u\1/g")

# Run connect command
azcmagent connect --access-token $accessToken --resource-group $resourceGroup --tenant-id $tenantId --location $Azurelocation --subscription-id $subscriptionId --resource-name "${ArcServerResourceName}" --cloud $azureCloud --correlation-id "d009f5dd-dba8-4ac7-bac9-b54ef3a6671a"

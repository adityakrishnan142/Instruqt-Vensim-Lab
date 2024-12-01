#!/bin/bash

# Function to validate the Org ID (should be 7 numbers)
validate_org_id() {
    if [[ $1 =~ ^[0-9]{7}$ ]]; then
        return 0
    else
        return 1
    fi
}

# Function to validate the API User (should start with api_ and followed by 17 alphanumeric characters)
validate_api_user() {
    if [[ $1 =~ ^api_[a-zA-Z0-9]{17}$ ]]; then
        return 0
    else
        return 1
    fi
}

# Function to validate the API Secret (should be 64 alphanumeric characters)
validate_api_secret() {
    if [[ $1 =~ ^[a-zA-Z0-9]{64}$ ]]; then
        return 0
    else
        return 1
    fi
}

# Get Org ID and validate
while true; do
    read -p "Enter Org ID (7 digits): " ORG_ID
    if validate_org_id "$ORG_ID"; then
        break
    else
        echo "Invalid Org ID. Please enter a 7-digit number."
    fi
done

# Get API User and validate
while true; do
    read -p "Enter API User (starts with 'api_' followed by 17 alphanumeric characters): " API_USER
    if validate_api_user "$API_USER"; then
        break
    else
        echo "Invalid API User. It should start with 'api_' and be followed by 17 alphanumeric characters."
    fi
done

# Get API Secret and validate
while true; do
    read -sp "Enter API Secret (64 alphanumeric characters): " API_SECRET
    echo
    if validate_api_secret "$API_SECRET"; then
        break
    else
        echo "Invalid API Secret. It should be exactly 64 alphanumeric characters."
    fi
done

# Add PCE Configuration
echo -e "\n### Adding Workloader PCE Configuration ###"
./workloader pce-add -a --name default --fqdn poc3.illum.io --port 443 --api-user "$API_USER" --api-secret "$API_SECRET" --org "$ORG_ID" --disable-tls-verification true

# Deletion Operations
echo -e "\n### Starting Deletion Operations ###"
./workloader ven-export --excl-containerized --headers wkld_href --output-file unpair_vens.csv && \
./workloader unpair --href-file unpair_vens.csv --include-online --update-pce --no-prompt

./workloader pairing-profile-export --output-file delete_pp.csv && \
./workloader delete delete_pp.csv --header href --update-pce --no-prompt --provision

./workloader ruleset-export --output-file delete_ruleset.csv && \
./workloader delete delete_ruleset.csv --header href --update-pce --no-prompt --provision --continue-on-error 

./workloader deny-rule-export --output-file delete_deny.csv && \
./workloader delete delete_deny.csv --header href --update-pce --no-prompt --provision --continue-on-error

./workloader labelgroup-export --output-file delete_lbg.csv && \
./workloader delete delete_lbg.csv --header href --update-pce --no-prompt --provision --continue-on-error

./workloader wkld-export --output-file delete_umwl.csv && \
./workloader delete delete_umwl.csv --header href --update-pce --no-prompt --provision --continue-on-error 

./workloader svc-export --compressed --output-file delete_svc.csv && \
./workloader delete delete_svc.csv --header href --update-pce --no-prompt --provision --continue-on-error

./workloader ipl-export --output-file delete_ipl.csv && \
./workloader delete delete_ipl.csv --header href --update-pce --no-prompt --provision --continue-on-error 

./workloader label-export --output-file delete_labels.csv && \
./workloader delete delete_labels.csv --header href --update-pce --no-prompt --provision

./workloader label-dimension-export --output-file delete_label_dimension.csv && \
./workloader delete delete_label_dimension.csv --header href --update-pce --no-prompt --provision

./workloader adgroup-export --output-file delete_ad.csv && \
./workloader delete delete_ad.csv --header href --update-pce --no-prompt --provision --continue-on-error

echo -e "\n### Deletion Operations Completed ###"

# Generate Pairing Keys
echo -e "\n### Generating Pairing Keys ###"
./workloader get-pk --profile Default-Servers --create --ven-type server -f server_pp
./workloader get-pk --profile Default-Endpoints --create --ven-type endpoint -f endpoint_pp

# Activate VENSim
echo -e "\n### Activating VENSim ###"
SERVER_PK=$(cat server_pp)
ENDPOINT_PK=$(cat endpoint_pp)

./vensim activate -c vens.csv -p processes.csv -m poc3.illum.io:443 -a "$SERVER_PK" -e "$ENDPOINT_PK"

# Create and Import Resources
echo -e "\n### Creating and Importing Resources ###"
./workloader label-dimension-import label-dimensions.csv --update-pce --no-prompt
./workloader wkld-import wklds.csv --umwl --update-pce --no-prompt
./workloader svc-import svcs.csv --update-pce --no-prompt && \
./workloader svc-import svcs-meta.csv --meta --update-pce --no-prompt --provision
./workloader ipl-import ipls.csv --update-pce --no-prompt --provision
./vensim post-traffic -c vens.csv -t traffic.csv -d "2023-07-26"

echo -e "\n### Script Execution Completed Successfully ###"

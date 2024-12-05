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
    read -p "Enter API Secret (64 alphanumeric characters): " API_SECRET
    echo
    if validate_api_secret "$API_SECRET"; then
        break
    else
        echo "Invalid API Secret. It should be exactly 64 alphanumeric characters."
    fi
done

# Add PCE Configuration
echo -e "\n### Adding Workloader PCE Configuration ###"
workloader pce-add -a --name default --fqdn poc3.illum.io --port 443 --api-user "$API_USER" --api-secret "$API_SECRET" --org "$ORG_ID" --disable-tls-verification true


echo -e "\n### Starting Deletion Operations ###"

#--- unpair vens-----

workloader ven-export --excl-containerized --headers wkld_href --output-file unpair_vens.csv

sed -i 's/workloads/vens/g' unpair_vens.csv

workloader unpair --href-file unpair_vens.csv --include-online --update-pce --no-prompt

#--- dd pairing profile ------
workloader pairing-profile-export --output-file delete_pp.csv
workloader delete delete_pp.csv --header href --update-pce --no-prompt --provision

#----dd ruleset -------
workloader ruleset-export --output-file delete_ruleset.csv
workloader delete delete_ruleset.csv --header href --update-pce --no-prompt --provision --continue-on-error 


#--- dd deny rules -----
workloader deny-rule-export --output-file delete_deny.csv && workloader delete delete_deny.csv --header href --update-pce --no-prompt --provision --continue-on-error

#---dd lbg-----
workloader labelgroup-export --output-file delete_lbg.csv && workloader delete delete_lbg.csv --header href --update-pce --no-prompt --provision --continue-on-error

#--dd umwl-----
workloader wkld-export --output-file delete_umwl.csv && workloader delete delete_umwl.csv --header href --update-pce --no-prompt --provision --continue-on-error 

#--dd svc-----
workloader svc-export --compressed --output-file delete_svc.csv && workloader delete delete_svc.csv --header href --update-pce --no-prompt --provision --continue-on-error

#--dd ipl-----
workloader ipl-export --output-file delete_ipl.csv && workloader delete delete_ipl.csv --header href --update-pce --no-prompt --provision --continue-on-error 

#---dd label---
workloader label-export --output-file delete_labels.csv && workloader delete delete_labels.csv --header href --update-pce --no-prompt --provision

#--dd label dimension----
workloader label-dimension-export --output-file delete_label_dimension.csv && workloader delete delete_label_dimension.csv --header href --update-pce --no-prompt --provision

#--dd ad-----
workloader adgroup-export --output-file delete_ad.csv && workloader delete delete_ad.csv --header href --update-pce --no-prompt --provision --continue-on-error

echo -e "\n### Deletion Operations Completed ###"

# Generate Pairing Keys
echo -e "\n### Generating Pairing Keys ###"
workloader get-pk --profile Default-Servers --create --ven-type server -f server_pp
workloader get-pk --profile Default-Endpoints --create --ven-type endpoint -f endpoint_pp

# Activate VENSim
echo -e "\n### Activating VENSim ###"
SERVER_PK=$(cat server_pp)
ENDPOINT_PK=$(cat endpoint_pp)

vensim activate -c Instruqt-Vensim-Lab/vens.csv -p Instruqt-Vensim-Lab/processes.csv -m poc3.illum.io:443 -a "$SERVER_PK" -e "$ENDPOINT_PK"

# Create and Import Resources
echo -e "\n### Creating and Importing Resources ###"
workloader label-dimension-import Instruqt-Vensim-Lab/labeldimensions.csv --update-pce --no-prompt
workloader wkld-import Instruqt-Vensim-Lab/wklds.csv --umwl --update-pce --no-prompt
workloader svc-import Instruqt-Vensim-Lab/svcs.csv --update-pce --no-prompt && workloader svc-import Instruqt-Vensim-Lab/svcs-meta.csv --meta --update-pce --no-prompt --provision
workloader ipl-import Instruqt-Vensim-Lab/iplists.csv --update-pce --no-prompt --provision
vensim post-traffic -c Instruqt-Vensim-Lab/vens.csv -t Instruqt-Vensim-Lab/traffic.csv -d "2023-07-26"

echo -e "\n### Script Execution Completed Successfully ###"

# Crontab setup
echo -e "\n### Setting up Crontab ###"

if [[ $EUID -ne 0 ]]; then
  echo "This script requires root privileges to set crontab for another user. Run with sudo if needed."
  exit 1
fi

CRON_CONFIG=$(cat <<'EOF'
# Make sure vensim is in path
PATH=/usr/local/bin:/usr/bin:/usr/local/sbin:/usr/sbin:/home/centos/.local/bin:/home/centos/bin

# Make sure vensim is in path
PATH=/usr/local/bin:/usr/bin:/usr/local/sbin:/usr/sbin:/home/centos/.local/bin:/home/centos/bin

# Set variables
TARGET_DIR=/root
PCE=poc3.illum.io:443
WORKLOAD_FILE=Instruqt-Vensim-Lab/vens.csv
TRAFFIC_FILE=Instruqt-Vensim-Lab/traffic.csv
PROCESS_FILE=Instruqt-Vensim-Lab/processes.csv

# Update workload running processes once a day at 6 AM
0 6 * * * cd $TARGET_DIR && vensim update-processes -c $WORKLOAD_FILE -p $PROCESS_FILE >/dev/null 2>&1

# Post traffic every 10 minutes
*/10 * * * * cd $TARGET_DIR && vensim post-traffic -c $WORKLOAD_FILE -t $TRAFFIC_FILE -d today >/dev/null 2>&1

# Heartbeat every 5 minutes
*/5 * * * * cd $TARGET_DIR && vensim heartbeat -c $WORKLOAD_FILE >/dev/null 2>&1

# Mimic event service by getting policy every 15 seconds.
* * * * * cd $TARGET_DIR && vensim get-policy -c $WORKLOAD_FILE >/dev/null 2>&1
* * * * * sleep 15 && cd $TARGET_DIR && vensim get-policy -c $WORKLOAD_FILE >/dev/null 2>&1
* * * * * sleep 30 && cd $TARGET_DIR && vensim get-policy -c $WORKLOAD_FILE >/dev/null 2>&1
* * * * * sleep 45 && cd $TARGET_DIR && vensim get-policy -c $WORKLOAD_FILE >/dev/null 2>&1

# Remove the vensim log every hour
0 * * * * cd $TARGET_DIR && rm -f vensim.log
EOF
)

echo "$CRON_CONFIG" | crontab -

echo "Crontab applied successfully!"

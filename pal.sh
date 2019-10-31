#!/bin/bash
###############################################################
# Loop through subscriptions for foreign tenants 
# and Lighthouse delegations and check PAL is assigned
###############################################################

verbose=true
incr=true


error()
{
  printf "ERROR: ${@:-Exiting.}\n" >> $PAL_LOGFILE
  tput setaf 1
  printf "ERROR: ${@:-Exiting.}\n" >&2 
  tput sgr0
  exit 1
}

info()
{
  printf "$@\n" >> $PAL_LOGFILE
  $verbose || return

  tput setaf 6
  printf "$@\n" >&2 
  tput sgr0
  return
}

# Define log file
ts=$(date '+%Y%m%d-%H%M')
export PAL_LOGFILE=~/.pal/logs/$ts.log

# Create the .pal folder if it doesn't already exist
umask 022
[[ ! -d ~/.pal ]] && mkdir -m 755 ~/.pal
[[ ! -d ~/.pal/logs ]] && mkdir -m 755 ~/.pal/logs
[[ ! -d ~/.pal/creds ]] && mkdir -m 755 ~/.pal/creds
info "Starting $(basename $0) on $(date +%F) at $(date +%R)"
 

# Check that az and jq are installed and ensure that the managementpartners extension has been added

[[ -x /usr/bin/az ]] || error "Azure CLI must be installed: <https://aka.ms/GetTheAzureCLI>"
[[ -x /usr/bin/jq ]] || error "jq must be installed"

# Read in the mpnId file to get the default MPN - allow getopts switches to be added later
if [ -z "$mpnId" -a -r ~/.pal/mpnId -a -s ~/.pal/mpnId ]
then
  mpnId=$(cat < ~/.pal/mpnId)
  info "MPN ID $mpnId pulled from ~/.pal/mpnId"
else
  echo -n "Please enter the MPN ID: "
  read mpnId
  [[ -z "$mpnId" ]] && error "Empty MPN ID"
  re='^[0-9]+$'
  [[ $mpnId =~ $re ]] || error "MPN ID is not numeric"
fi

# Grab the list of tenantIds and subscriptionIds
[[ -z "$tenants" ]] && tenants=$(az account list --query "[].[tenantId]" --output tsv | sort -u)

for tenant in $tenants
do
  info "\nChecking tenant $tenant"

  tenantFile=~/.pal/creds/$tenant
  if [ $incr -a -s $tenantFile ] 
  then
    principalId=$(find ~/.pal/creds -lname $tenant -exec basename {} \;)
    info "  principalId:    $principalId"
    info "  mpnId:          $(cat $tenantFile) (from file)"
    continue
  fi

  # Check that we have the extension

  if [[ -n "$AZ_EXTENSION" ]]
  then : # For speed
  elif az extension show --name managementpartner > /dev/null 2>&1 
  then 
    AZ_EXTENSION=true
  else
    info "Adding the missing managementpartner CLI extension" 
    az extension add --name managementpartner && AZ_EXTENSION=true
  fi

  # PAL needs to be associated per tenant, or more specifically per set of credentials for this user (1:1)
  # Switch context to the first subscription for the tenant
  subscriptionId=$(az account list --query "[?tenantId == '$tenant'].id | sort(@)[0]" --output tsv)
  az account set --subscription $subscriptionId || error "Could not switch subscription to $subscriptionId"  

  # Work out who we are logged on as and the tenantId in case tenant is a string rather vthan a GUID
  principalId=$(az ad signed-in-user show --query userPrincipalName --output tsv)
  tenantId=$(az ad signed-in-user show --query '"odata.metadata"' --output tsv | cut -d/ -f4)
  idSymLink=$(dirname $tenantFile)/$principalId

  info "  tenantId:       $tenantId"
  info "  subscriptionId: $subscriptionId"
  info "  principalId:    $principalId"

  if existingPartnerId=$(az managementpartner show --query partnerId --output tsv 2>/dev/null)
  then 
    info "  mpnId:          $existingPartnerId (existing)"
    echo "$existingPartnerId" > $tenantFile && ln -s $(basename $tenantFile) $idSymLink
  else
    if az managementpartner create --partner-id $mpnId > /dev/null 
    then
      info "  mpnId:          $mpnId"
      echo "$mpnId" > $tenantFile && ln -s $(basename $tenantFile) $idSymLink
    else
      error "Failed to link $principalId to MPN ID $mpnId."
    fi
  fi
done

# Save the MPN ID

if [[ ! -f ~/.pal/mpnId ]]
then 
  echo "$mpnId" > ~/.pal/mpnId
  info "Saved $mpnId to ~/.pal/mpnId file."
elif [[ "x$(cat ~/.pal/mpnId)" != "x${mpnId}" ]]
then
  echo "$mpnId" > ~/.pal/mpnId
  info "Replaced $(cat ~/.pal/mpnId) with $mpnId in ~/.pal/mpnId file."
fi


# Remove log files older than 28 days
find ~/.pal/logs -name "*.log" -type f -mtime +28 -exec rm -f {} \;

# End
info "\nComplete."
exit 0

#!/bin/bash
###############################################################
# Loop through subscriptions for foreign tenants 
# and Lighthouse delegations and check PAL is assigned
###############################################################

verbose=true
incr=true


error()
{
  tput setaf 1
  printf "ERROR: ${@:-Exiting.}\n" >&2
  tput sgr0
  exit 1
}

warn()
{
  tput setaf 3
  printf "$@\n" >&2
  tput sgr0
  return
}

info()
{
  $verbose || return
  tput setaf 6
  printf "$@\n" >&2
  tput sgr0
  return
}

umask 022

# Check that az and jq are installed and ensure that the managementpartners extension has been added

[[ -x /usr/bin/az ]] || error "Azure CLI must be installed: <https://aka.ms/GetTheAzureCLI>"
[[ -x /usr/bin/jq ]] || error "jq must be installed"
if az extension show --name managementpartner > /dev/null 2>&1 
then :
else
  warn "Adding the missing managementpartner CLI extension" | yellow
  az extension add --name managementpartner
fi

# Get the users home tenantId so that we can skip those

signedInUser=$(az ad signed-in-user show --output json)
jq -r .userPrincipalName <<< $signedInUser | grep -q "#EXT#" && error "Switch to a subscription in your home tenant and rerun"
# myTenantId=$(az ad signed-in-user show --output tsv --query '"odata.metadata"' | cut -d/ -f4)
myTenantId=$(jq -r '."odata.metadata"' <<< $signedInUser | cut -d/ -f4)
info "Home tenantID is $myTenantId"


# Create the .pal folders if they don't already exist
[[ ! -d ~/.pal ]] && mkdir -m 755 ~/.pal
[[ ! -d ~/.pal/lighthouse ]] && mkdir -pm 755 ~/.pal/lighthouse
[[ ! -d ~/.pal/legacy ]] && mkdir -pm 755 ~/.pal/legacy

# Read in the mpnId file to get the default MPN - allow getopts switches to be added later
if [ -z "$mpnId" -a -r ~/.pal/mpnId -a -s ~/.pal/mpnId ]
then
  mpnId=$(cat < ~/.pal/mpnId)
  info "MPN ID $mpnId pulled from ~/.pal/mpnId"
fi

# Get list of foreign subscriptions, i.e. those in another tenancy accessed using legacy B2B or "guest" access
# Note that this does not include Lighthouse projections which do not show the original tenancy
# Check legacy folder if incremental mode is enabled

foreignSubs=$(az account list --query "[?tenantId != "\'$myTenantId\'" ].id" --output tsv)
[[ -z "$foreignSubs" ]] && info "No legacy subscription access" 

for sub in $foreignSubs
do
  subFile=~/.pal/legacy/$sub
  if [ $incr -a -s $subFile ] 
  then
    info "Found $subFile - skipping"
    continue
  fi

  az account set --subscription $sub || error "Could not switch subscription to $sub"  
  if az managementpartner show 2>/dev/null 
  then :
  else
    if az managementpartner create --partner-id $mpnId > /dev/null 
    then
      info "$sub linked to $mpnId"
      echo "$mpnId" > $subFile && info "Created $subFile"
    fi
  fi
done

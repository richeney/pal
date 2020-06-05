#!/bin/bash
###############################################################
# Loop through subscriptions for foreign tenants
# and Lighthouse delegations and check PAL is assigned
#
# Recommendation: All admins should link their IDs to MPN IDs if they have either
#
# * authorisations within Lighthouse projected customer subscriptions
# * Guest User access to customer tenants
#
###############################################################


error()
{
  tput setaf 1
  printf "ERROR: ${@:-Exiting.}\n" >&2
  tput sgr0

  # Revert back to default subscription
  [[ -n "$defaultSubscriptionId" ]] && az account set --subscription $defaultSubscriptionId
  exit 1
}

info()
{
  tput setaf 6
  if [[ -n "$@" ]]
  then printf "$@\n" >&2
  else cat /dev/stdin
  fi
  tput sgr0
  return
}


#=======================================================================================================

umask 077
[[ ! -d ~/.pal ]] && mkdir -m 700 ~/.pal
export PALFILE=~/.pal/mpnid

# Check that az and jq are installed and ensure that the managementpartners extension has been added

[[ -x /usr/bin/jq ]] || error "jq must be installed"
[[ -x /usr/bin/az ]] || error "Azure CLI must be installed: <https://aka.ms/GetTheAzureCLI>"

if [ -r $PALFILE -a -s $PALFILE ]
then
  source $PALFILE
fi

# MPNID=${MPNID:-1234567} # Change the default value 1234567 to your company's MPN ID and uncomment

if ${AZEXT:-false}
then : # For speed
elif az extension show --name managementpartner > /dev/null 2>&1
then
  AZEXT=true
else
  info "Adding the missing managementpartner CLI extension"
  az extension add --name managementpartner && AZEXT=true
fi

#=======================================================================================================

echo
read -e -i "$MPNID" -p "Enter your Microsoft Partner Network (MPN) ID: " MPNID

info "\n         Started at : $(date +%T)"

# Remember where we started
originalSignedInUser=$(az ad signed-in-user show --output json)
originalTenantId=$(jq -r '."odata.metadata"' <<< $originalSignedInUser | cut -d/ -f4)
originalUserPrincipalName=$(jq -r .userPrincipalName <<< $originalSignedInUser)
originalObjectId=$(jq -r .objectId <<< $originalSignedInUser)

currentTenantId=$originalTenantId
currentObjectId=$originalObjectId
homeUserPrincipalName=$originalUserPrincipalName

# Grab the list of tenantIds and subscriptionIds, determine default. Use jq for speed.
# defaultSubscriptionId=$(az account list --output tsv --query "[?isDefault].id")
# [[ -z "$tenants" ]] && tenants=$(az account list --query "[].[tenantId]" --output tsv | sort -u)

accounts=$(az account list --output json) || error "Not logged in?"
originalSubscriptionId=$(jq -r '.[]|select(.isDefault).id' <<< $accounts)
non_user_accounts=$(jq -r '[.[]|select(.user.type != "user")]' <<< $accounts)
user_accounts=$(jq -r '[.[]|select(.user.type == "user")]' <<< $accounts)


#=======================================================================================================

# Loop through the list, check for existing link or create a new one

cat - <<EOF

STAGE 1: Looping through tenants visible to your user account:

EOF

for tenant in $(jq -r '.[]|.tenantId' <<< $user_accounts | sort -u)
do
  # PAL needs to be associated per tenant, or more specifically per set of credentials for this user (1:1)
  # Switch context to the first subscription for the tenant
  subscriptionId=$(jq -r '[.[]|select(.tenantId == "'$tenant'")][0].id' <<< $user_accounts)
  az account set --subscription $subscriptionId || error "Could not switch subscription to $subscriptionId"

  # Work out who we are logged on as and the tenantId in case tenant is a string rather vthan a GUID
  currentSignedInUser=$(az ad signed-in-user show --output json)
  currentTenantId=$(jq -r '."odata.metadata"' <<< $currentSignedInUser | cut -d/ -f4)
  currentUserPrincipalName=$(jq -r .userPrincipalName <<< $currentSignedInUser)
  currentObjectId=$(jq -r .objectId <<< $currentSignedInUser)

  info "  userPrincipalName : $currentUserPrincipalName"
  info "           tenantId : $currentTenantId"
  info "           objectId : $currentObjectId"

  if existingPartnerId=$(az managementpartner show --query partnerId --output tsv 2>/dev/null)
  then info "              mpnId : $existingPartnerId (existing link)"
  else
    if az managementpartner create --partner-id $MPNID > /dev/null
    then echo "              mpnId : $MPNID (newly linked)"
    else error "Failed to link $currentUserPrincipalName to MPN ID $MPNID."
    fi
  fi

  if grep -q "#EXT#" <<< $currentUserPrincipalName
  then :
  else
    info "               note : Home tenant linked to recognise any Lighthouse projected resources"
    homeUserPrincipalName=$currentUserPrincipalName
  fi

  echo
done


#=======================================================================================================

# Loop through any visible service principals.
# I think they only pop in the list if that is the only way a subscription has been accessed.

cat - <<EOF

STAGE 2: Looping through tenants where you only have access via a service principal:

EOF

info <<EOF

 Warning: This script can only link service principals if they are visible within
          this user's account list and is therefore expected to be far from exhaustive.
          Ensure all known service principals in customer tenants are linked manually, e.g.

EOF

cat - <<EOF
          az login --service-principal --username <servicePrincipalName> --tenant <tenantId>
          az managementpartner create --partner $MPNID

EOF

service_principal_tenants=$(jq -r '.[]|.tenantId' <<< $non_user_accounts | sort -u)
logged_in_as_sp=false

for tenantId in "$service_principal_tenants"
do
  [[ ! -d ~/.pal/service_principals ]] && mkdir -m 700 ~/.pal/service_principals

  for service_principal in $(jq -r '[.[]|select(.tenantId == "'$tenantId'")]|.[].user.name' <<< $non_user_accounts | sort -u)
  do
    SPFILE=~/.pal/service_principals/$tenantId-${service_principal#http://}

    # Skip this swervice principal if we have a file.
    if [[ -f $SPFILE && "$(cat $SPFILE)" == $MPNID ]]
    then
      info "  Found $SPFILE. Skipping...\n"
      continue
    elif [[ -f $SPFILE && "$(cat $SPFILE)" != $MPNID ]]
    then
      # Could incorporate logic to automate this, but I doubt it will crop up.
      info "  $SPFILE found, but ${service_principal#http://} is linked to MPN ID $(cat file)."
      info "  To change, run: az managementpartner update --partner-id $MPNID"
    fi

    # Log on as each service principal, prompting for password,  and link
    echo "  Logging into tenant $tenantId as service principal ${service_principal#http://}"
    read -s -p "  Enter password, or leave blank to skip: " password

    if [[ -n "$password" ]]
    then
      if az login --service-principal --username "$service_principal" --tenant $tenantId --password $password --allow-no-subscriptions >/dev/null
      then
        logged_in_as_sp=true
                echo
      else error "Login failure."
      fi
    else
      continue
    fi

    # Work out who we are logged on as and the tenantId in case tenant is a string rather vthan a GUID
    currentServicePrincipal=$(az ad sp show --id "$service_principal" --output json)
    currentTenantId=$(jq -r '."odata.metadata"' <<< $currentServicePrincipal | cut -d/ -f4)
    currentAppId=$(jq -r .appId <<< $currentServicePrincipal)
    currentObjectId=$(jq -r .objectId <<< $currentServicePrincipal)

    echo
    info "   servicePrincipal : $service_principal"
    info "           tenantId : $currentTenantId"
    info "              appId : $currentAppId"
    info "           objectId : $currentObjectId"

    if existingPartnerId=$(az managementpartner show --query partnerId --output tsv 2>/dev/null)
    then
      info "              mpnId : $existingPartnerId (existing link)"
      echo $existingPartnerId > $SPFILE
    else
      if az managementpartner create --partner-id $MPNID > /dev/null
      then
        echo "              mpnId : $MPNID (newly linked)"
        echo $MPNID > $SPFILE
      else
        error "Failed to link $principalId to MPN ID $MPNID."
      fi
    fi
  done
  echo
done

if [[ -z "$service_principal_tenants" ]]
then info "  No service principals found in list."
fi


#=======================================================================================================


# Save the MPN ID

cat > $PALFILE << EOF
MPNID=$MPNID
AZEXT=true
EOF

# De we need to log back in?

if $logged_in_as_sp
then
  info "Please log back in as $homeUserPrincipalName..."
  az login --tenant $originalTenantId --allow-no-subscriptions >/dev/null
fi

# Revert back to default subscription
az account set --subscription $originalSubscriptionId > /dev/null


# End
info "       Completed at : $(date +%T)"

exit 0


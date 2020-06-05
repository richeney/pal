# TO BE UPDATED

# Automated PAL linking script

This script can be called from ~/.bashrc to automate Partner Admin Link for a signed in user.  It will efficiently check that all visible tenancies are linked so that it does not unnecessarily slow down user logon times.

## Background

[Partner Admin Link](https://aka.ms/partneradminlink) is used by service providers to gain recognition for their managed services in customer subscriptions and the resulting influence in helping to drive Azure Consumed Revenue (ACR). The service provider will have access via one of four methods:

1. Guest Users, i.e. Azure Active Directory Business to Business (AAD B2B) access
1. Service Principals (including Managed Identities)
1. Directory Accounts, i.e. "guest" accounts created in the customer tenancy
1. Azure Lighthouse authorizations

These various routes differ slightly, so refer to the [access methods](#access-methods) section below for more detail.

The _managementpartner_ extension for Azure CLI is used to query and set the Partner Admin Link, which links the signed in user's userPrincipalId to their MPN ID.  The MPN ID can be any location based MPN ID, but it cannot be the virtual organization MPN ID.

## Installation

You can use the following command to download the script:

```bash
curl -H 'Cache-Control: no-cache' -sSL https://raw.githubusercontent.com/richeney/pal/master/pal.sh > pal.sh
chmod 755 pal.sh
```

You script should first be run interactively.

```bash
./pal.sh
```

You will be prompted for the MPN ID which will be saved to the ~/.pal folder.

After the initial run then you can add a line to your profile e.g.

```bash
cat >> ~/.bashrc << EOF

## Link the signed-in-user to the MPN ID in ~/.pal/mpnId
~/pal.sh 2>/dev/null
EOF
```

The current version is simple, but future versions will have additional switches to control the verbosity, refresh, set alternate MPN IDs, or to define a reduced tenancy list.

## ~/.pal

The ~/.pal hidden folder is created for speed of execution. The MPN ID is stored here, and four weeks of log files are retained.

The files and symlinks in the ~/.pal/creds folder are used to store user principal to MPN ID information per tenant. This is both for existing links that are discovered and for newly created links.

## Access Methods

### Guest Users

Included.

AAD B2B guest users will result in the subscription being listed in `az account list` with the original customer tenancy. The script will switch to the first subscription in that tenancy and establish the link.

The signed in user will in the `richeney_microsoft.com#EXT#@azurecitadel.onmicrosoft.com` format.  In this example, richeney@microsoft.com has been added as a guest user to the azurecitadel.com directory.

### Service Principals

Excluded.

Service principals are separate security principals to your user principal.

Sign in as the service principal, specifying the tenant then you can link manually using the `az managementpartner create --partner-id <mpnId>` command.

The `az login --help` shows examples for both service principals and managed identities.

### Directory Accounts

Excluded.

The creation of "guest" accounts in the customer's tenancy is not the preferred method of access. AAD provides the functionality for centralised identity and strong security with conditional access and MFA. Creating multiple accounts in multiple tenancies goes against those principles.

As per the service principal, you will need to log in as the directory account and link manually using `az managementpartner create --partner-id <mpnId>`.

### Azure Lighthouse

Included.

Interestingly, the Lighthouse projected subscriptions will be listed as if they belong to the service provider's tenancy. This actually makes it a little tricky to see which subscriptions are native to the service provider, and which are projected from a foreign tenancy. It is expected that the product group will add additional key value pairs into the `az account list` output to make it easier to query.

The good news is that it will be using the service provider signed in user principal, so as soon as that user principal is linked to the MPN ID then all future projections should also come into the PAL totals, even for new customers.

The downside is that you will not be able to specify different MPN IDs for different Lighthouse customers if they are serviced by the same team, but that is hopefully a rare requirement.

If you are in a Lighthouse projected subscription then you can see details for you delegations using `az managedservices assignment list --include-definition true`, including the manageeTenantId and manageeTenantName.

You can also see the scope points for the assignments using:

```bash
az managedservices assignment list --query [].id --output tsv | sed 's!/providers/Microsoft.ManagedServices/.*$!!'
```

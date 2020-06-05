# Automated PAL linking script

This script can be called from ~/.bashrc to automate some Partner Admin Link activities for a signed in user.

## Background

[Partner Admin Link](https://aka.ms/partneradminlink) is used by service providers to gain recognition for their managed services in customer subscriptions and the resulting influence in helping to drive Azure Consumed Revenue (ACR). The service provider will have access via one of four methods:

1. Guest Users, i.e. Azure Active Directory Business to Business (AAD B2B) access
1. Service Principals (including Managed Identities)
1. Directory Accounts, i.e. standard user principals created in the customer tenancy and provided to the partner
1. Azure Lighthouse authorizations

These various routes differ slightly, so refer to the [access methods](#access-methods) section below for more detail.

The _managementpartner_ extension for Azure CLI is used to query and set the Partner Admin Link, which links the signed in user's userPrincipalId to their MPN ID.  The MPN ID can be any location based MPN ID, but it cannot be the virtual organization MPN ID.

## Installation

You can use the following command to download the script:

```bash
curl -H 'Cache-Control: no-cache' -sSL https://raw.githubusercontent.com/richeney/pal/master/pal.sh > pal.sh
chmod 755 pal.sh
```

The script requires both az and jq. It can be run in the Cloud Shell which includes both commands.

## Execution

Run the script interactively:

```bash
./pal.sh
```

You will be prompted for the MPN ID which will be saved to the ~/.pal folder.

It will loop through the tenants listed in the `az account list` output and will link in each of those, unless an existing link exists. The script covers:

1. Guest Users
1. Azure Lighthouse authorizations (i.e. home tenant)

It will also loop through any service principals that are visible in the az account list, and prompt for the secret to authenticate into that context and link. It will check for (and report on) existing links. If successful then a file will be stored in the ~/.pal area and subsequent executions of the command will skip past for speed. (Delete the relevant files in ~/.pal/service_principals if you want to refresh.)

## Limitations

This is a script to be run by each admin user. It cannot loop through and impersonate other users. Link multiple admin IDs for coverage.

It does not currently handle

1. Service Principals, except those visible in the `az account list` output
1. Directory Accounts, i.e. standard user principals created in the customer tenancy and provided to the partner

See [Access Methods](access-methods) below for more detail.

## Future plans

It is planned to:

* Allow JSON inputs of additional directory accounts and service principals to link
* Authenticate interactively, or provide passwords or secrets via protected files (700) or Key Vault Secrets
* Create a set of JSON output files containing upn, objectId, tenantId etc.
* Publish the files into Cosmos DB to allow reporting of linked IDs

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

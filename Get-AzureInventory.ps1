<#
.SYNOPSIS
    Get an inventory of your Azure environment
.DESCRIPTION
    The script exports your Azure inventory as CSV files. It builds different CSV files 
    for each subscription with resources, including deployment URLs for Azure Web Apps. 
.EXAMPLE
    PS C:\> .\Get-AzureInventory.ps1
    Gets all resources in all available subscriptions and exports them to CSV files

.EXAMPLE
    PS C:\> .\Get-AzureInventory.ps1 -SubscriptionId <subscription-id>
    Gets all resources in a particular subscription and exports them to CSV files

.PARAMETER SubscriptionId
    (optional) Specifies the subscription.

.LINK
    https://github.com/cloudchristoph/AzureInventory
#>
[CmdletBinding()]
param (
    # (optional) Specifies the subscription.
    [Parameter()]
    [string]$SubscriptionId = ""
)

Write-Verbose -Message "Getting subscriptions"
try {
    if ($SubscriptionId.Length -eq 0) {
        # If no SubscriptionId is provided, get all subscriptions
        $subscriptions = Get-AzSubscription
    } else {
        # Otherwise, get the specified subscription by SubscriptionId
        $subscriptions = Get-AzSubscription -SubscriptionId $SubscriptionId
    }    
}
catch { 
    Write-Warning -Message "You're not connected. Connecting now."
    Connect-AzAccount
    if ($SubscriptionId.Length -eq 0) {
        $subscriptions = Get-AzSubscription -ErrorAction Stop
    } else {
        $subscriptions = Get-AzSubscription -SubscriptionId $SubscriptionId -ErrorAction Stop
    }    
}
Write-Verbose -Message "Found $($subscriptions.Length) subscription(s)"

# Export a list of your subscriptions
$subscriptions | Export-Csv -Path "./subscriptions.csv"

foreach ($subscription in $subscriptions) {
    # Construct file paths for inventory and marketplace resources for the current subscription
    $pathInventory = "./inventory_$($subscription.Id).csv"
    $pathMarketplace = "./marketplace_$($subscription.Id).csv"

    Write-Verbose -Message "Getting resources from subscription $($subscription.Name)"
    Select-AzSubscription -SubscriptionObject $subscription

    # Get all resources within the current subscription
    $ressources = Get-AzResource | Select-Object ResourceName, ResourceGroupName, ResourceType, Sku, Location,  @{Name='TagsString';Expression={if ($_.Tags) { ($_.Tags.GetEnumerator() | ForEach-Object {"$($_.Key)=$($_.Value)"}) -join ', ' } else { "None" }}}, @{Name='DeploymentUrl'; Expression={

        # If ResourceType is Azure Web App (Microsoft.Web/sites)...
        if ($_.ResourceType -like "Microsoft.Web/sites") { 
            $webAppProperties = Get-AzWebApp -ResourceGroupName $_.ResourceGroupName -Name $_.ResourceName

            # ...try to retrieve the deployment URL
            if ($webAppProperties.DefaultHostName) {
                "https://$($webAppProperties.DefaultHostName)"
            } else {
                '' # Return empty string if no URL found
            } 
        } else {
            '' # Return empty string for non-WebApp resources
        } 
    }} 

    if ($ressources.Length -gt 0) {
        Write-Verbose -Message "$($ressources.Length) resources found"
        $ressources | Export-Csv -Path $pathInventory

        # Filter and export marketplace resources separately
        $marketplaceItems = $ressources | Where-Object { $_.ResourceType -notlike "Microsoft.*" } 
        if ($marketplaceItems.Length -gt 0) {
            Write-Verbose -Message "$($marketplaceItems.Length) marketplace resources found"
            $marketplaceItems | Export-Csv -Path $pathMarketplace
        }
    }
}

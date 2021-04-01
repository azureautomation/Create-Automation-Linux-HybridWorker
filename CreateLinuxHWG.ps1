<#
.SYNOPSIS 
    This sample automation runbook onboards Azure VMs for Azure Automation Hybrid Worker.
    It can create a Azure VM or could use an exisiting VM to onboard as a Hybrid Worker.
    Since onboarding a VM to Automation Hybrid Worker requires a Log Analytics workspace, this script also gives the feasibility to the users to provide an already exisiting Log Analytics workspace or the script could also create one for the users.
    This Runbook needs to be run from the Automation account that you wish to connect the VM to.
    
    This script must be executed on a Run As Enabled Automation Account only.   
    This would require the following modules to be present in the Automation account :  
    Az.Accounts, Az.Resources, Az.Automation, Az.OperationalInsights, Az.Compute 
 
.DESCRIPTION

    This sample automation runbook onboards Azure VMs for Azure Automation Hybrid Worker.
    It can create a Azure VM or could use an exisiting VM to onboard as a Hybrid Worker.
    Since onboarding a VM to Automation Hybrid Worker requires a Log Analytics workspace, this script also gives the feasibility to the users to provide an already exisiting Log Analytics workspace or the script could also create one for the users.
    This Runbook needs to be run from the Automation account that you wish to connect the VM to.
    
    This script must be executed on a Run As Enabled Automation Account only.   
    This would require the following modules to be present in the Automation account :  
    Az.Accounts, Az.Resources, Az.Automation, Az.OperationalInsights, Az.Compute 
 
.PARAMETER Location
    Required. Location of the automation account in which the script is executed.
 
.PARAMETER ResourceGroupName
    Required. The name of the resource group of the automation account.
 
.PARAMETER AccountName
    Required. The name of the autmation account in which the script is executed.
 
.PARAMETER CreateLA 
    Required. True, creates a new LA Workspace with the given WorkspaceName in the given LALocation. False, Uses the given WorkspaceName for Hybrid worker registration.
 
.PARAMETER LAlocation
    Optional. The location in which the LA Workspace to be used is present in or the location in which a new LA workspace has to be created in. 
    If not provided the value will be used from the Location parameter.
 
.PARAMETER WorkspaceName
    Optional. The name of the LA workspace to be created or to be used for Hybrid worker registration.
 
.PARAMETER CreateVM 
    Required. True, creates a new VM with the given VMName in the given VMLocation. False, Uses the given VMName for Hybrid worker registration.

.PARAMETER VMName
    Optional. The name of the VM to be created or to be used to onboard as a Hybrid Worker.

.PARAMETER VMImage
    Optional. The name of the VM Image to be created.

.PARAMETER VMlocation
    Optional. The location in which the VM to be used is present in or the location in which a new VM has to be created in. 
    If not provided the value will be used from the Location parameter.

.PARAMETER RegisterHW
    Required. True, Registers the provided VM as a Hybrid Worker. False, Doesn't register the VM as a Hybrdid Worker.

.Example
    .\CreateLinuxHWG  -location <location> -ResourceGroupName <ResourceGroupName> `
     -AccountName <accountname> -CreateLA <$true/$false> -lalocation <lalocation> `
     -WorkspaceName <WorkspaceName> -CreateVM <$true/$false> -vmName <vmName> -vmImage <VMImage> `
     -RegisterHW <$true/$false> -vmlocation <vmlocation> -WorkerGroupName <HybridworkergroupName> 
 
.NOTES
    AUTHOR: Automation Team
    LASTEDIT: March 31, 2021 
#>


Param(
    [Parameter(Mandatory = $true)]
    [string] $location,  
    [Parameter(Mandatory = $true)]
    [string] $ResourceGroupName,
    [Parameter(Mandatory = $true)]
    [string] $AccountName,
    [Parameter(Mandatory = $true)]
    [bool] $CreateLA,
    [Parameter(Mandatory = $false)]
    [String] $lalocation,
    [Parameter(Mandatory = $false)]
    [string] $WorkspaceName,
    [Parameter(Mandatory = $true)]
    [bool] $CreateVM,
    [Parameter(Mandatory = $false)]
    [String] $vmName,
    [Parameter(Mandatory = $false)]
    [String] $vmImage,
    [Parameter(Mandatory = $true)]
    [bool] $RegisterHW,
    [Parameter(Mandatory = $false)]
    [String] $vmlocation,
    [Parameter(Mandatory = $false)]
    [String] $WorkerGroupName
)
 
$ErrorActionPreference = "Stop"
$guid_val = [guid]::NewGuid()
$script:guid = $guid_val.ToString()

$script:agentEndpoint = ""
$script:aaPrimaryKey = ""
$script:workspaceId = ""
$script:workspacePrimaryKey = ""

if ([String]::IsNullOrEmpty($vmlocation)) {
    $script:vmlocation = $location
}
if ([String]::IsNullOrEmpty($lalocation)) {
    $script:lalocation = $location
}

function Login-AzAccount {
    $connectionName = "AzureRunAsConnection"
    try {  
        Write-Output  "Logging in to Azure..." -verbose
        $servicePrincipalConnection = Get-AutomationConnection -Name $connectionName  
            
        Connect-AzAccount `
            -ServicePrincipal `
            -TenantId $servicePrincipalConnection.TenantId `
            -ApplicationId $servicePrincipalConnection.ApplicationId `
            -CertificateThumbprint $servicePrincipalConnection.CertificateThumbprint 
    }
    catch {
        Write-Error -Message $_.Exception
        throw $_.Exception
    }                                                                                                                                       
}

function Get-AutomationAccountDetails {
    #Get-Automation Account
    Write-Output  "Getting Automation Account....."

    try {
        ($Account = Get-AzAutomationAccount -Name $AccountName -ResourceGroupName $ResourceGroupName) | Out-Null 
        if ($Account.AutomationAccountName -like $AccountName) {
            ($accRegInfo = Get-AzAutomationRegistrationInfo -ResourceGroup $ResourceGroupName -AutomationAccountName  $AccountName) | Out-Null
            $script:agentEndpoint = $accRegInfo.Endpoint
            $script:aaPrimaryKey = $accRegInfo.PrimaryKey

            Write-Output "Automation Account details retrieved to be used for HW creation"
        } 
        else {
            Write-Error "HWG Creation :: Account retrieval failed"
        }
    }
    catch {
        Write-Error "HWG Creation :: Account retrieval failed"
    }
}

function New-LAWorkspace {
    ### Create an LA workspace
    Write-Output  "Creating LA Workspace...."
    if ($WorkspaceName -eq "LAWorkspaceForAutomationHW") {
        $workspace_guid = [guid]::NewGuid()
        $WorkspaceName = $WorkspaceName + $workspace_guid.ToString()
    }

    # Create a new Log Analytics workspace if needed
    try {
        #check if already exists
        $laworkspace = Get-AzResource -ResourceGroupName $ResourceGroupName -Name $WorkspaceName

        if ($null -eq $laworkspace) {
            Write-Output "Creating new workspace named $WorkspaceName in region $lalocation..."
            New-AzOperationalInsightsWorkspace -Location $lalocation -Name $WorkspaceName -Sku Standard -ResourceGroupName $ResourceGroupName
            Start-Sleep -s 60
        }
    } 
    catch {
        Write-Error "HWG Creation :: Error creating LA workspace : $_"
    }
}


function Get-LAWorkspaceDetails { 
    Write-Output "Enabling Automation for the created workspace...."
    (Set-AzOperationalInsightsIntelligencePack -ResourceGroupName $ResourceGroupName -WorkspaceName $WorkspaceName -IntelligencePackName "AzureAutomation" -Enabled $true) | Out-Null

    ($workspaceDetails = Get-AzOperationalInsightsWorkspace -ResourceGroupName $ResourceGroupName -Name $WorkspaceName)  | Out-Null
    $script:workspaceId = $workspaceDetails.CustomerId

    ($workspaceSharedKey = Get-AzOperationalInsightsWorkspaceSharedKey -ResourceGroupName $ResourceGroupName -Name $WorkspaceName) | Out-Null
    $script:workspacePrimaryKey = $workspaceSharedKey.PrimarySharedKey
}

function New-VM {
    
    $vm = Get-AzResource -ResourceGroupName $ResourceGroupName -Name $vmName 
    if ($null -ne $vm) {
        Write-Output "VM Already present. Skipping VM Creation."
        return
    }
    try {
        $vmNetworkName = "VMVnet" + $guid.SubString(0, 4)
        $subnetName = "VMSubnet" + $guid.SubString(0, 4)
        $newtworkSG = "VMNetworkSecurityGroup" + $guid.SubString(0, 4)
    

        # Define a credential object$length = 12
        $User = "azureuser"
        $length = 12
        Add-Type -AssemblyName System.Web 
        $vmpassword = [System.Web.Security.Membership]::GeneratePassword($length, 2)
    
        $VMAccessingString = ConvertTo-SecureString $vmpassword -AsPlainText -Force
        $VMCredential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $User, $VMAccessingString


        # subnet config
        # Create a subnet configuration
        $subnetConfig = New-AzVirtualNetworkSubnetConfig `
            -Name $subnetName `
            -AddressPrefix 192.168.1.0/24

        # Create a virtual network
        $vnet = New-AzVirtualNetwork `
            -ResourceGroupName $ResourceGroupName `
            -Location $script:vmlocation `
            -Name $vmNetworkName `
            -AddressPrefix 192.168.0.0/16 `
            -Subnet $subnetConfig

        # Create a public IP address and specify a DNS name
        $pip = New-AzPublicIpAddress `
            -ResourceGroupName $ResourceGroupName `
            -Location $script:vmlocation `
            -AllocationMethod Static `
            -IdleTimeoutInMinutes 4 `
            -Name "mypublicdns$(Get-Random)"

        # Create an inbound network security group rule for port 22
        $nsgRuleSSH = New-AzNetworkSecurityRuleConfig `
            -Name $newtworkSG `
            -Protocol "Tcp" `
            -Direction "Inbound" `
            -Priority 1000 `
            -SourceAddressPrefix * `
            -SourcePortRange * `
            -DestinationAddressPrefix * `
            -DestinationPortRange 22 `
            -Access "Allow"

        # Create an inbound network security group rule for port 80
        $nsgRuleWeb = New-AzNetworkSecurityRuleConfig `
            -Name "myNetworkSecurityGroupRuleWWW"  `
            -Protocol "Tcp" `
            -Direction "Inbound" `
            -Priority 1001 `
            -SourceAddressPrefix * `
            -SourcePortRange * `
            -DestinationAddressPrefix * `
            -DestinationPortRange 80 `
            -Access "Allow"

        # Create a virtual network card and associate with public IP address and NSG
        $nic = New-AzNetworkInterface `
            -Name "myNic" `
            -ResourceGroupName $ResourceGroupName `
            -Location $script:vmlocation `
            -SubnetId $vnet.Subnets[0].Id `
            -PublicIpAddressId $pip.Id `
            -NetworkSecurityGroupId $nsg.Id

        # Create a network security group
        $nsg = New-AzNetworkSecurityGroup `
            -ResourceGroupName $ResourceGroupName `
            -Location $script:vmlocation `
            -Name $newtworkSG `
            -SecurityRules $nsgRuleSSH, $nsgRuleWeb

        # Create a virtual machine configuration
        $vmConfig = New-AzVMConfig `
            -VMName $vmName ` | `
            Set-AzVMOperatingSystem `
            -Linux `
            -ComputerName $vmName `
            -Credential $VMCredential `
            -DisablePasswordAuthentication | `
            Add-AzVMNetworkInterface `
            -Id $nic.Id



        $newfile = New-Item -Path ~/.ssh/id_rsa.pub -Force
        ssh-keygen -t rsa -f $(newfile.FullName) -P "TestPassPhrase" -Force

        # Configure the SSH key
        $sshPublicKey = cat $($newfile.FullName)
        Add-AzVMSshPublicKey `
            -VM $vmconfig `
            -KeyData $sshPublicKey `
            -Path "/home/azureuser/.ssh/authorized_keys"
        #Create a VM
        New-AzVM `
            -ResourceGroupName $ResourceGroupName `
            -Location $script:vmlocation -VM $vmConfig `
            -Image $vmImage 
    
    }
    catch {
        Write-Output "Error creating VM retrying in $vmlocation... $_"
    }
    
}

function RegisterLinuxHW {
    $filename = "AutoRegisterLinuxHW.py"
    $regsitrationScriptUri = "https://raw.githubusercontent.com/azureautomation/Create-Automation-Linux-HybridWorker/main/HelperScripts/AutoRegisterLinuxHW.py"

    $commandToExecute = "python $filename -e $agentEndpoint -k $aaPrimaryKey -g $WorkerGroupName -w $workspaceId -l $workspacePrimaryKey -r $location"

    $settings = @{"skipDos2Unix" = $false; "timestamp" = [int](Get-Random) };
    $protectedSettings = @{"fileUris" = @($regsitrationScriptUri); "commandToExecute" = $commandToExecute };

    $commandToExecute

    # Run Az VM Extension to download and register worker.
    Write-Output  "Running Az VM Extension...."
    Write-Output  "Command executing ... $commandToExecute"
    try {
        Set-AzVMExtension -ResourceGroupName $ResourceGroupName `
            -Location $vmlocation `
            -VMName $vmName `
            -Name "Register-HybridWorker" `
            -Publisher "Microsoft.Azure.Extensions"  `
            -ExtensionType  "CustomScript"  `
            -TypeHandlerVersion "2.1" `
            -Settings $settings `
            -ProtectedSettings $protectedSettings 

    }
    catch {
        Write-Error "HWG Creation :: Error running VM extension - $_"
    }


    Get-AzAutomationHybridWorkerGroup -AutomationAccountName $AccountName -ResourceGroupName $ResourceGroupName -Name $WorkerGroupName
    Write-Output "Creation of HWG Successful"
}


# Login-AzAccount

if ($CreateVM -eq $true) {
    #Create a VM
    try { 
        Write-Output "Creating a new $($vmImage) VM in $($vmlocation) with the provided details"
        New-VM
    }
    catch {
        Write-Error "HWG Creation :: Error creating VM : $_"
    }
}

if ($CreateLA -eq $true) {
    #Create an LA workspace
    try { 
        Write-Output "Creating a new LA Worksapce in $($lalocation) with the provided details"
        New-LAWorkspace
    }
    catch {
        Write-Error "HWG Creation :: Error creating LA Workspace : $_"
    }
}

if ($RegisterHW -eq $true) {
    try {
        Write-Output "Fetching the automation account details for HW registration"
        Get-AutomationAccountDetails

        
        Write-Output "Fetching the LA Workspace details for HW registration"
        Get-LAWorkspaceDetails

        Write-Output "Executing HW registration on the VM"
        RegisterLinuxHW
    }
    catch {
        Write-Error "Error registering the HW : $_"
    }
}




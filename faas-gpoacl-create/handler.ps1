function Handler {
  Param(
  [Parameter(Mandatory=$true)]
  [FunctionContext]$fnContext,
  [Parameter(Mandatory=$true)]
  [FunctionResponse]$fnResponse
  )

  $json = $fnContext.Body | Out-String | ConvertFrom-Json 

  $businessUnit = $json.businessUnit
  $application = $json.application
  $environment = $json.environment
  $group = $json.group
  $domain = $json.domain

  if ($domain -eq "contoso.com"){
    $servername = $env:PRODPSREMOTESERVER
    $username = $env:PRODSERVICEACCOUNT
    $basedn = $env:PRODBASEDN
    $password = Get-Content "/var/openfaas/secrets/prodldappassword" | ConvertTo-SecureString -AsPlainText -Force
  } else {
    $servername = $env:NONPRODPSREMOTESERVER
    $username = $env:NONPRODSERVICEACCOUNT
    $basedn = $env:NONPRODBASEDN
    $password = Get-Content "/var/openfaas/secrets/nonprodldappassword" | ConvertTo-SecureString -AsPlainText -Force
  }

  $cred = New-Object System.Management.Automation.PSCredential -ArgumentList ($username, $password)

  $sessionoptions = New-PSSessionOption -SkipCACheck -SkipCNCheck
  $session = New-PSSession -ComputerName $servername -ConfigurationName "SvcaLinuxAdminProfile" -SessionOption $sessionoptions -Credential $cred -Authentication "Negotiate"

  $output = Invoke-Command -Session $session -ArgumentList $businessUnit,$application,$environment,$group,$basedn -Scriptblock {
    param(
      $businessUnit,
      $application,
      $environment,
      $group,
      $basedn
    )
    $OUPath = "ou=" + $environment + ",ou=" + $application + ",ou=" + $businessunit + "," + $basedn

    $domain = [System.DirectoryServices.ActiveDirectory.Domain]::GetCurrentDomain()
    $domaincontext = New-Object System.DirectoryServices.ActiveDirectory.DirectoryContext -ArgumentList "Domain",$domain
    $domaincontroller = [System.DirectoryServices.ActiveDirectory.DomainController]::FindOne($domaincontext)

    Import-Module GroupPolicy –Global

    $newGPO_Name = "$businessUnit $application $environment ACL SSSD"
    try {
      $GPO = New-GPO -name $newGPO_Name -domain $domain -server $domaincontroller
      $GPO.GpoStatus = "UserSettingsDisabled"
      Set-GPPermission -Name $newGPO_Name -TargetName "ACL_LUX_Admins" -TargetType Group -PermissionLevel GpoEdit -server $domaincontroller | Out-Null
    }
    catch {
      Throw "GPO [$newGPO_Name] cannot be created"
    }
    $group | ForEach-Object {
      try {
          $group_sid = "*" + (New-Object System.Security.Principal.NTAccount($domain, $group)).Translate([System.Security.Principal.SecurityIdentifier])
      }
      catch {
          Throw "Subject $group could not be resolved"
      }
      [array]$group_sids = $group_sids + $group_sid
    }
    $all_group_sids = $group_sids -join ","

    # Construct the inf settings to enable RemoteInteractiveLogonRight
    $inf = @"
[Unicode]
Unicode=yes
[Version]
signature="`$CHICAGO`$"
Revision=1
[Privilege Rights]
SeRemoteInteractiveLogonRight = $all_group_sids
SeInteractiveLogonRight = $all_group_sids
"@
    $filepath = "\\$domaincontroller\sysvol\$domain\Policies\{$($GPO.Id)}\Machine\Microsoft\Windows NT\SecEdit" 
    if (!(Test-Path $filepath)) {
        md $filepath | Out-Null
    }
    $inf |Out-File (Join-Path $filepath 'GptTmpl.inf')

    New-GPLink -Name $newGPO_Name -Target $OUPath -Server $domaincontroller -Domain $domain -LinkEnabled 'Yes' -ErrorAction Stop | Out-Null
    Write-Host $newGPO_Name "linked to" $OUPath
    Write-Output $newGPO_Name
  }

  $fnResponse.Body = $output
  #$fnResponse.Body = $output | ConvertTo-Json -Compress
}
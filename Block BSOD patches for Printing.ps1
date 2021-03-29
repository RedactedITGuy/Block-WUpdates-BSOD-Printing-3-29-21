Function Hide-WUUpdate
{
  

    [OutputType('PSWindowsUpdate.WUList')]
    [CmdletBinding(
        SupportsShouldProcess=$True,
        ConfirmImpact="High"
    )]    
    Param
    (
        #Pre search criteria
        [ValidateSet("Driver", "Software")]
        [String]$UpdateType = "",
        [String[]]$UpdateID,
        [Int]$RevisionNumber,
        [String[]]$CategoryIDs,
        [Switch]$IsInstalled,
        [Switch]$IsHidden,
        [Switch]$IsNotHidden,
        [String]$Criteria,
        [Switch]$ShowSearchCriteria,        
        
        #Post search criteria
        [String[]]$Category="",
        [String[]]$KBArticleID,
        [String]$Title,
        
        [String[]]$NotCategory="",
        [String[]]$NotKBArticleID,
        [String]$NotTitle,    
        
        [Alias("Silent")]
        [Switch]$IgnoreUserInput,
        [Switch]$IgnoreRebootRequired,
        
        #Connection options
        [String]$ServiceID,
        [Switch]$WindowsUpdate,
        [Switch]$MicrosoftUpdate,
        [Switch]$HideStatus = $true,
        
        #Mode options
        [Switch]$Debuger,
        [parameter(ValueFromPipeline=$true,
            ValueFromPipelineByPropertyName=$true)]
        [String[]]$ComputerName
    )

    Begin
    {
        If($PSBoundParameters['Debuger'])
        {
            $DebugPreference = "Continue"
        } #End If $PSBoundParameters['Debuger']
        
        $User = [Security.Principal.WindowsIdentity]::GetCurrent()
        $Role = (New-Object Security.Principal.WindowsPrincipal $user).IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)

        if(!$Role)
        {
            Write-Warning "To perform some operations you must run an elevated Windows PowerShell console."    
        } #End If !$Role
    }

    Process
    {
        Write-Debug "STAGE 0: Prepare environment"
        ######################################
        # Start STAGE 0: Prepare environment #
        ######################################
        
        Write-Debug "Check if ComputerName in set"
        If($ComputerName -eq $null)
        {
            Write-Debug "Set ComputerName to localhost"
            [String[]]$ComputerName = $env:COMPUTERNAME
        } #End If $ComputerName -eq $null
        
        ####################################
        # End STAGE 0: Prepare environment #
        ####################################
        
        $UpdateCollection = @()
        Foreach($Computer in $ComputerName)
        {
            If(Test-Connection -ComputerName $Computer -Quiet)
            {
                Write-Debug "STAGE 1: Get updates list"
                ###################################
                # Start STAGE 1: Get updates list #
                ###################################

                If($Computer -eq $env:COMPUTERNAME)
                {
                    Write-Debug "Create Microsoft.Update.ServiceManager object"
                    $objServiceManager = New-Object -ComObject "Microsoft.Update.ServiceManager" #Support local instance only
                    Write-Debug "Create Microsoft.Update.Session object for $Computer"
                    $objSession = New-Object -ComObject "Microsoft.Update.Session" #Support local instance only
                } #End If $Computer -eq $env:COMPUTERNAME
                Else
                {
                    Write-Debug "Create Microsoft.Update.Session object for $Computer"
                    $objSession =  [activator]::CreateInstance([type]::GetTypeFromProgID("Microsoft.Update.Session",$Computer))
                } #End Else $Computer -eq $env:COMPUTERNAME
                
                Write-Debug "Create Microsoft.Update.Session.Searcher object for $Computer"
                $objSearcher = $objSession.CreateUpdateSearcher()

                If($WindowsUpdate)
                {
                    Write-Debug "Set source of updates to Windows Update"
                    $objSearcher.ServerSelection = 2
                    $serviceName = "Windows Update"
                } #End If $WindowsUpdate
                ElseIf($MicrosoftUpdate)
                {
                    Write-Debug "Set source of updates to Microsoft Update"
                    $serviceName = $null
                    Foreach ($objService in $objServiceManager.Services) 
                    {
                        If($objService.Name -eq "Microsoft Update")
                        {
                            $objSearcher.ServerSelection = 3
                            $objSearcher.ServiceID = $objService.ServiceID
                            $serviceName = $objService.Name
                            Break
                        }#End If $objService.Name -eq "Microsoft Update"
                    }#End ForEach $objService in $objServiceManager.Services
                    
                    If(-not $serviceName)
                    {
                        Write-Warning "Can't find registered service Microsoft Update. Use Get-WUServiceManager to get registered service."
                        Return
                    }#Enf If -not $serviceName
                } #End Else $WindowsUpdate If $MicrosoftUpdate
                ElseIf($Computer -eq $env:COMPUTERNAME) #Support local instance only
                {
                    Foreach ($objService in $objServiceManager.Services) 
                    {
                        If($ServiceID)
                        {
                            If($objService.ServiceID -eq $ServiceID)
                            {
                                $objSearcher.ServiceID = $ServiceID
                                $objSearcher.ServerSelection = 3
                                $serviceName = $objService.Name
                                Break
                            } #End If $objService.ServiceID -eq $ServiceID
                        } #End If $ServiceID
                        Else
                        {
                            If($objService.IsDefaultAUService -eq $True)
                            {
                                $serviceName = $objService.Name
                                Break
                            } #End If $objService.IsDefaultAUService -eq $True
                        } #End Else $ServiceID
                    } #End Foreach $objService in $objServiceManager.Services
                } #End Else $MicrosoftUpdate If $Computer -eq $env:COMPUTERNAME
                ElseIf($ServiceID)
                {
                    $objSearcher.ServiceID = $ServiceID
                    $objSearcher.ServerSelection = 3
                    $serviceName = $ServiceID
                }
                Else #End Else $Computer -eq $env:COMPUTERNAME If $ServiceID
                {
                    $serviceName = "default (for $Computer) Windows Update"
                } #End Else $ServiceID
                Write-Debug "Set source of updates to $serviceName"
                
                Write-Verbose "Connecting to $serviceName server. Please wait..."
                Try
                {
                    $search = ""
                    If($Criteria)
                    {
                        $search = $Criteria
                    } #End If $Criteria
                    Else
                    {
                        If($IsInstalled) 
                        {
                            $search = "IsInstalled = 1"
                            Write-Debug "Set pre search criteria: IsInstalled = 1"
                        } #End If $IsInstalled
                        Else
                        {
                            $search = "IsInstalled = 0"    
                            Write-Debug "Set pre search criteria: IsInstalled = 0"
                        } #End Else $IsInstalled
                        
                        If($UpdateType -ne "")
                        {
                            Write-Debug "Set pre search criteria: Type = $UpdateType"
                            $search += " and Type = '$UpdateType'"
                        } #End If $UpdateType -ne ""
                        
                        If($UpdateID)
                        {
                            Write-Debug "Set pre search criteria: UpdateID = '$([string]::join(", ", $UpdateID))'"
                            $tmp = $search
                            $search = ""
                            $LoopCount = 0
                            Foreach($ID in $UpdateID)
                            {
                                If($LoopCount -gt 0)
                                {
                                    $search += " or "
                                } #End If $LoopCount -gt 0
                                If($RevisionNumber)
                                {
                                    Write-Debug "Set pre search criteria: RevisionNumber = '$RevisionNumber'"    
                                    $search += "($tmp and UpdateID = '$ID' and RevisionNumber = $RevisionNumber)"
                                } #End If $RevisionNumber
                                Else
                                {
                                    $search += "($tmp and UpdateID = '$ID')"
                                } #End Else $RevisionNumber
                                $LoopCount++
                            } #End Foreach $ID in $UpdateID
                        } #End If $UpdateID

                        If($CategoryIDs)
                        {
                            Write-Debug "Set pre search criteria: CategoryIDs = '$([string]::join(", ", $CategoryIDs))'"
                            $tmp = $search
                            $search = ""
                            $LoopCount =0
                            Foreach($ID in $CategoryIDs)
                            {
                                If($LoopCount -gt 0)
                                {
                                    $search += " or "
                                } #End If $LoopCount -gt 0
                                $search += "($tmp and CategoryIDs contains '$ID')"
                                $LoopCount++
                            } #End Foreach $ID in $CategoryIDs
                        } #End If $CategoryIDs
                        
                        If($IsNotHidden) 
                        {
                            Write-Debug "Set pre search criteria: IsHidden = 0"
                            $search += " and IsHidden = 0"    
                        } #End If $IsNotHidden
                        ElseIf($IsHidden) 
                        {
                            Write-Debug "Set pre search criteria: IsHidden = 1"
                            $search += " and IsHidden = 1"    
                        } #End ElseIf $IsHidden

                        #Don't know why every update have RebootRequired=false which is not always true
                        If($IgnoreRebootRequired) 
                        {
                            Write-Debug "Set pre search criteria: RebootRequired = 0"
                            $search += " and RebootRequired = 0"    
                        } #End If $IgnoreRebootRequired
                    } #End Else $Criteria
                    
                    Write-Debug "Search criteria is: $search"
                    
                    If($ShowSearchCriteria)
                    {
                        Write-Output $search
                    } #End If $ShowSearchCriteria
            
                    $objResults = $objSearcher.Search($search)
                } #End Try
                Catch
                {
                    If($_ -match "HRESULT: 0x80072EE2")
                    {
                        Write-Warning "Probably you don't have connection to Windows Update server"
                    } #End If $_ -match "HRESULT: 0x80072EE2"
                    Return
                } #End Catch

                $NumberOfUpdate = 1
                $PreFoundUpdatesToDownload = $objResults.Updates.count
                Write-Verbose "Found [$PreFoundUpdatesToDownload] Updates in pre search criteria"                
                
                If($PreFoundUpdatesToDownload -eq 0)
                {
                    Continue
                } #End If $PreFoundUpdatesToDownload -eq 0
                
                Foreach($Update in $objResults.Updates)
                {    
                    $UpdateAccess = $true
                    Write-Progress -Activity "Post search updates for $Computer" -Status "[$NumberOfUpdate/$PreFoundUpdatesToDownload] $($Update.Title) $size" -PercentComplete ([int]($NumberOfUpdate/$PreFoundUpdatesToDownload * 100))
                    Write-Debug "Set post search criteria: $($Update.Title)"
                    
                    If($Category -ne "")
                    {
                        $UpdateCategories = $Update.Categories | Select-Object Name
                        Write-Debug "Set post search criteria: Categories = '$([string]::join(", ", $Category))'"    
                        Foreach($Cat in $Category)
                        {
                            If(!($UpdateCategories -match $Cat))
                            {
                                Write-Debug "UpdateAccess: false"
                                $UpdateAccess = $false
                            } #End If !($UpdateCategories -match $Cat)
                            Else
                            {
                                $UpdateAccess = $true
                                Break
                            } #End Else !($UpdateCategories -match $Cat)
                        } #End Foreach $Cat in $Category
                    } #End If $Category -ne ""

                    If($NotCategory -ne "" -and $UpdateAccess -eq $true)
                    {
                        $UpdateCategories = $Update.Categories | Select-Object Name
                        Write-Debug "Set post search criteria: NotCategories = '$([string]::join(", ", $NotCategory))'"    
                        Foreach($Cat in $NotCategory)
                        {
                            If($UpdateCategories -match $Cat)
                            {
                                Write-Debug "UpdateAccess: false"
                                $UpdateAccess = $false
                                Break
                            } #End If $UpdateCategories -match $Cat
                        } #End Foreach $Cat in $NotCategory
                    } #End If $NotCategory -ne "" -and $UpdateAccess -eq $true
                    
                    If($KBArticleID -ne $null -and $UpdateAccess -eq $true)
                    {
                        Write-Debug "Set post search criteria: KBArticleIDs = '$([string]::join(", ", $KBArticleID))'"
                        If(!($KBArticleID -match $Update.KBArticleIDs -and "" -ne $Update.KBArticleIDs))
                        {
                            Write-Debug "UpdateAccess: false"
                            $UpdateAccess = $false
                        } #End If !($KBArticleID -match $Update.KBArticleIDs)
                    } #End If $KBArticleID -ne $null -and $UpdateAccess -eq $true

                    If($NotKBArticleID -ne $null -and $UpdateAccess -eq $true)
                    {
                        Write-Debug "Set post search criteria: NotKBArticleIDs = '$([string]::join(", ", $NotKBArticleID))'"
                        If($NotKBArticleID -match $Update.KBArticleIDs -and "" -ne $Update.KBArticleIDs)
                        {
                            Write-Debug "UpdateAccess: false"
                            $UpdateAccess = $false
                        } #End If$NotKBArticleID -match $Update.KBArticleIDs -and "" -ne $Update.KBArticleIDs
                    } #End If $NotKBArticleID -ne $null -and $UpdateAccess -eq $true
                    
                    If($Title -and $UpdateAccess -eq $true)
                    {
                        Write-Debug "Set post search criteria: Title = '$Title'"
                        If($Update.Title -notmatch $Title)
                        {
                            Write-Debug "UpdateAccess: false"
                            $UpdateAccess = $false
                        } #End If $Update.Title -notmatch $Title
                    } #End If $Title -and $UpdateAccess -eq $true

                    If($NotTitle -and $UpdateAccess -eq $true)
                    {
                        Write-Debug "Set post search criteria: NotTitle = '$NotTitle'"
                        If($Update.Title -match $NotTitle)
                        {
                            Write-Debug "UpdateAccess: false"
                            $UpdateAccess = $false
                        } #End If $Update.Title -notmatch $NotTitle
                    } #End If $NotTitle -and $UpdateAccess -eq $true
                    
                    If($IgnoreUserInput -and $UpdateAccess -eq $true)
                    {
                        Write-Debug "Set post search criteria: CanRequestUserInput"
                        If($Update.InstallationBehavior.CanRequestUserInput -eq $true)
                        {
                            Write-Debug "UpdateAccess: false"
                            $UpdateAccess = $false
                        } #End If $Update.InstallationBehavior.CanRequestUserInput -eq $true
                    } #End If $IgnoreUserInput -and $UpdateAccess -eq $true

                    If($IgnoreRebootRequired -and $UpdateAccess -eq $true) 
                    {
                        Write-Debug "Set post search criteria: RebootBehavior"
                        If($Update.InstallationBehavior.RebootBehavior -ne 0)
                        {
                            Write-Debug "UpdateAccess: false"
                            $UpdateAccess = $false
                        } #End If $Update.InstallationBehavior.RebootBehavior -ne 0
                    } #End If $IgnoreRebootRequired -and $UpdateAccess -eq $true

                    If($UpdateAccess -eq $true)
                    {
                        Write-Debug "Convert size"
                        Switch($Update.MaxDownloadSize)
                        {
                            {[System.Math]::Round($_/1KB,0) -lt 1024} { $size = [String]([System.Math]::Round($_/1KB,0))+" KB"; break }
                            {[System.Math]::Round($_/1MB,0) -lt 1024} { $size = [String]([System.Math]::Round($_/1MB,0))+" MB"; break }  
                            {[System.Math]::Round($_/1GB,0) -lt 1024} { $size = [String]([System.Math]::Round($_/1GB,0))+" GB"; break }    
                            {[System.Math]::Round($_/1TB,0) -lt 1024} { $size = [String]([System.Math]::Round($_/1TB,0))+" TB"; break }
                            default { $size = $_+"B" }
                        } #End Switch
                    
                        Write-Debug "Convert KBArticleIDs"
                        If($Update.KBArticleIDs -ne "")    
                        {
                            $KB = "KB"+$Update.KBArticleIDs
                        } #End If $Update.KBArticleIDs -ne ""
                        Else 
                        {
                            $KB = ""
                        } #End Else $Update.KBArticleIDs -ne ""
                        
                        if($Update.IsHidden -ne $HideStatus)
                        {
                            if($HideStatus)
                            {
                                $StatusName = "Hide"
                            } #$HideStatus
                            else
                            {
                                $StatusName = "Unhide"
                            } #Else $HideStatus
                            
                            If($pscmdlet.ShouldProcess($Computer,"$StatusName $($Update.Title)?")) 
                            {
                                Try
                                {
                                    $Update.IsHidden = $HideStatus
                                }
                                Catch
                                {
                                    Write-Warning "You haven't privileges to make this. Try start an eleated Windows PowerShell console."
                                }
                                
                            } #$pscmdlet.ShouldProcess($Computer,"Hide $($Update.Title)?")
                        } #End $Update.IsHidden -ne $HideStatus
                        
                        $Status = ""
                        If($Update.IsDownloaded)    {$Status += "D"} else {$status += "-"}
                        If($Update.IsInstalled)     {$Status += "I"} else {$status += "-"}
                        If($Update.IsMandatory)     {$Status += "M"} else {$status += "-"}
                        If($Update.IsHidden)        {$Status += "H"} else {$status += "-"}
                        If($Update.IsUninstallable) {$Status += "U"} else {$status += "-"}
                        If($Update.IsBeta)          {$Status += "B"} else {$status += "-"} 
        
                        Add-Member -InputObject $Update -MemberType NoteProperty -Name ComputerName -Value $Computer
                        Add-Member -InputObject $Update -MemberType NoteProperty -Name KB -Value $KB
                        Add-Member -InputObject $Update -MemberType NoteProperty -Name Size -Value $size
                        Add-Member -InputObject $Update -MemberType NoteProperty -Name Status -Value $Status
                    
                        $Update.PSTypeNames.Clear()
                        $Update.PSTypeNames.Add('PSWindowsUpdate.WUList')
                        $UpdateCollection += $Update
                    } #End If $UpdateAccess -eq $true
                    
                    $NumberOfUpdate++
                } #End Foreach $Update in $objResults.Updates
                Write-Progress -Activity "Post search updates for $Computer" -Status "Completed" -Completed
                
                $FoundUpdatesToDownload = $UpdateCollection.count
                Write-Verbose "Found [$FoundUpdatesToDownload] Updates in post search criteria"
                
                #################################
                # End STAGE 1: Get updates list #
                #################################
                
            } #End If Test-Connection -ComputerName $Computer -Quiet
        } #End Foreach $Computer in $ComputerName

        Return $UpdateCollection
        
    } #End Process
    
    End{}        
}

Hide-WUUpdate -KBArticleID KB5000802 -Confirm:$false
Hide-WUUpdate -KBArticleID KB5000822 -Confirm:$false
Hide-WUUpdate -KBArticleID KB5000808 -Confirm:$false
Hide-WUUpdate -KBArticleID KB5000809 -Confirm:$false

$WindowsBuild = (Get-Item "HKLM:SOFTWARE\Microsoft\Windows NT\CurrentVersion").GetValue('ReleaseID')
IF ($WindowsBuild -eq 2004)
{Write-Host "Removing 5000802"
wusa /uninstall /kb:5000802 /quiet }
Else
{}
IF ($WindowsBuild -eq 1909)
{Write-Host "Removing 5000808"
wusa /uninstall /kb:5000808 /quiet }
Else
{}
IF ($WindowsBuild -eq 1809)
{Write-Host "Removing 5000822"
wusa /uninstall /kb:5000822 /quiet}
Else
{}
IF ($WindowsBuild -eq 1803)
{Write-Host "Removing 5000809"
wusa /uninstall /kb:5000809 /quiet}
Else
{}

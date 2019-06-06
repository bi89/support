Function Invoke-JCApi
{
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true, Position = 0)][ValidateNotNullOrEmpty()][string]$Url,
        [Parameter(Mandatory = $true, Position = 1)][ValidateNotNullOrEmpty()][string]$Method,
        [Parameter(Mandatory = $false, Position = 2)][ValidateNotNullOrEmpty()][ValidateRange(1, [int]::MaxValue)][int]$Limit = 100,
        [Parameter(Mandatory = $false, Position = 3)][ValidateNotNullOrEmpty()][ValidateRange(0, [int]::MaxValue)][int]$Skip = 0,
        [Parameter(Mandatory = $false, Position = 4)][ValidateNotNull()][array]$Fields = @(),
        [Parameter(Mandatory = $false, Position = 5)][ValidateNotNull()][string]$Body = '',
        [Parameter(Mandatory = $false, Position = 6)][ValidateNotNullOrEmpty()][bool]$Paginate = $false,
        [Parameter(Mandatory = $false, Position = 7)][ValidateNotNullOrEmpty()][switch]$ReturnCount
    )
    Begin
    {
        # Debug message for parameter call
        Invoke-Command -ScriptBlock:($ScriptBlock_DefaultDebugMessageBegin) -ArgumentList:($MyInvocation, $PsBoundParameters, $PSCmdlet) -NoNewScope
        #Set JC headers
        Write-Verbose 'Verifying JCAPI Key'
        If ($JCAPIKEY.length -ne 40) {Connect-JCOnline}
        Write-Verbose 'Populating API headers'
        $Headers = @{
            'Content-Type' = 'application/json'
            'Accept'       = 'application/json'
            'X-API-KEY'    = $JCAPIKEY
        }
        If ($JCOrgID)
        {
            $Headers.Add('x-org-id', "$($JCOrgID)")
        }
    }
    Process
    {
        Try
        {
            $Results = @()
            If ($Url -notlike ('*' + $JCUrlBasePath + '*'))
            {
                $Url = $JCUrlBasePath + $Url
            }
            If ($Url -like '*`?*')
            {
                $SearchOperator = '&'
            }
            Else
            {
                $SearchOperator = '?'
            }
            # Convert passed in body to json
            If ($Body)
            {
                $ObjectBody = $Body | ConvertFrom-Json
            }
            Else
            {
                $ObjectBody = ''
            }
            # Pagination
            Do
            {
                $QueryStrings = @()
                # Add fields
                If ($Fields)
                {
                    $JoinedFields = ($Fields -join ' ')
                    If ($ObjectBody.PSObject.Properties.name -eq 'fields')
                    {
                        $JoinedFields = $ObjectBody.fields
                    }
                    Else
                    {
                        $ObjectBody = $ObjectBody | Select-Object *, @{Name = 'fields'; Expression = {$JoinedFields}}
                    }
                    If ($Url -notlike '*fields*') {$QueryStrings += 'fields=' + $JoinedFields}
                }
                # Add limit
                If ($ObjectBody.PSObject.Properties.name -eq 'limit')
                {
                    $ObjectBody.limit = $Limit
                }
                Else
                {
                    $ObjectBody = $ObjectBody | Select-Object *, @{Name = 'limit'; Expression = {$Limit}}
                }
                If ($Url -notlike '*limit*') {$QueryStrings += 'limit=' + $Limit}
                # Add skip
                If ($ObjectBody.PSObject.Properties.name -eq 'skip')
                {
                    $ObjectBody.skip = $Skip
                }
                Else
                {
                    $ObjectBody = $ObjectBody | Select-Object *, @{Name = 'skip'; Expression = {$Skip}}
                }
                If ($Url -notlike '*skip*') {$QueryStrings += 'skip=' + $Skip}
                # Build url query string and body
                $ObjectBody = $ObjectBody | Select-Object -Property * -ExcludeProperty Length
                $Body = $ObjectBody | ConvertTo-Json -Depth:(10) -Compress | Sort-Object
                If ($QueryStrings)
                {
                    $Uri = $Url + $SearchOperator + (($QueryStrings | Sort-Object) -join '&')
                }
                Else
                {
                    $Uri = $Url
                }
                # Run request
                $UserAgent = Get-JCUserAgent
                [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
                Write-Verbose ('Connecting to: ' + $Uri)
                # PowerShell 5 won't let you send a GET with a body.
                If ($Method -eq 'GET')
                {
                    Write-Debug("[CallFunction]Invoke-WebRequest -Method:('$Method') -Headers:('" + ($Headers | ConvertTo-Json -Compress) + "') -Uri:('$Uri') -UserAgent:('$UserAgent')")
                    $RequestResult = Invoke-WebRequest -Method:($Method) -Headers:($Headers) -Uri:($Uri) -UserAgent:($UserAgent)
                }
                Else
                {
                    Write-Debug("[CallFunction]Invoke-WebRequest -Method:('$Method') -Headers:('" + ($Headers | ConvertTo-Json -Compress) + "') -Uri:('$Uri') -UserAgent:('$UserAgent') -Body:('$Body')")
                    $RequestResult = Invoke-WebRequest -Method:($Method) -Headers:($Headers) -Uri:($Uri) -UserAgent:($UserAgent) -Body:($Body)
                }
                If ($RequestResult)
                {
                    $Result = $RequestResult.Content | ConvertFrom-Json
                    $httpMetaData = $RequestResult | Select-Object -Property:('*') -ExcludeProperty:('Content')
                    If ($Result)
                    {
                        $ResultPopulated = $false
                        # Specific logic for v1 and v2 api specs
                        If ($Url -like '*/api/*' -and ($Url -notlike '*/api/v2/*' -and $Result.PSObject.Properties.name -eq 'results'))
                        {
                            $ResultCount = ($Result.results | Measure-Object).Count
                            If ($ResultCount -gt 0)
                            {
                                $ResultPopulated = $true
                                If ($ReturnCount)
                                {
                                    $ResultObjects = $Result
                                    $Paginate = $false
                                }
                                Else
                                {
                                    $ResultObjects = $Result.results
                                }
                            }
                        }
                        ElseIf ($Url -like '*/api/*' -and ($Url -like '*/api/v2/*' -or $Result.PSObject.Properties.name -ne 'results'))
                        {
                            $ResultCount = ($Result | Measure-Object).Count
                            If ($ResultCount -gt 0)
                            {
                                $ResultPopulated = $true
                                If ($ReturnCount)
                                {
                                    $ResultObjects = [PSCustomObject]@{'totalCount' = [int](($httpMetaData.Headers.'X-Total-Count') -join ','); 'results' = $Result; }
                                    $Paginate = $false
                                }
                                Else
                                {
                                    $ResultObjects = $Result
                                }
                            }
                        }
                        Else
                        {
                            Write-Error ('Url is not a valid JumpCloud V1 or V2 endpoint')
                        }
                        If ($ResultPopulated)
                        {
                            $Skip += $ResultCount
                            $Results += $ResultObjects
                        }
                    }
                    Else
                    {
                        If ($Paginate)
                        {
                            $ResultCount = ($Result | Measure-Object).Count
                        }
                    }
                }
                Write-Debug ('Paginate:' + [string]$Paginate + ';ResultsCount:' + [string]$ResultCount + ';Limit:' + [string]$Limit + ';')
            }
            While ($Paginate -and $ResultCount -eq $Limit)
            Write-Verbose ('Returned ' + [string]($Results | Measure-Object).Count + ' total results.')
        }
        Catch
        {
            Invoke-Command -ScriptBlock:($ScriptBlock_TryCatchError) -ArgumentList:($_, $true) -NoNewScope
        }
    }
    End
    {
        # List values to add to results
        $HiddenProperties = @('httpMetaData')
        # Append meta info to each result record
        Get-Variable -Name:($HiddenProperties) |
            ForEach-Object {
            $Variable = $_
            If ($Results)
            {
                $Results |
                    ForEach-Object {
                    Add-Member -InputObject:($_) -MemberType:('NoteProperty') -Name:($Variable.Name) -Value:($Variable.Value)
                }
            }
            Else
            {

                $Results += [PSCustomObject]@{
                    'NoContent'    = $null;
                    'httpMetaData' = $httpMetaData;
                }
            }
        }
        # Validate that all fields passed into the function exist in the output
        If ($Results)
        {
            # Validate results properties returned
            $Fields | ForEach-Object {
                If ($_ -notin ($Results | Get-Member).Name)
                {
                    Write-Warning ('API output does not contain the field "' + $_ + '". Please refer to https://docs.jumpcloud.com for API endpoint field names.')
                }
            }
        }
        # Set the meta info to be hidden by default
        Return Hide-ObjectProperty -Object:($Results) -HiddenProperties:($HiddenProperties)
    }
}

$GenericInvoke = '
[CmdletBinding()]
param({0})

$Types = @({3})
$Parameters = @({4})

Write-Warning "Invoke-Generic -Static -On [{1}] -Named {2} -Types $($Types -join "","") -WithArgs $($Parameters -join "","")"

Invoke-Generic -On {1} -Static -Named {2} -GenericArgumentTypes $Types -WithArgs $Parameters
'
# Invoke-Generic -On System.Linq.Enumerable -Static -Named Contains -GenericArgumentTypes object -WithArgs (ls), $f -Verbose

$NormalInvoke = '
param({0})
[{1}]::{2}.Invoke($PSBoundParameters.Values)
'


function Get-ExtensionMethod {
    <#
        .Synopsis
            Finds Extension Methods which target the specified type
        .Example
            Get-ExtensionMethod String

            Finds all extension methods which target strings
    #>
    [CmdletBinding()]
    param(
        # The type name to find Extension Methods for
        [Parameter(Mandatory=$false,Position=0)]
        [SupportsWildCards()]
        [String[]]$TargetTypeName,

        # A filter for the Extension Method name 
        [Parameter(Mandatory=$false)]
        [SupportsWildCards()]
        [String[]]$Name = "*",

        # The type to search for Extension Methods (defaults to search all types)
        [Parameter(Mandatory=$false,Position=99)]
        [SupportsWildCards()]
        [String[]]$TypeName = "*"
    )
    process {
        Get-Type -TypeName $TypeName -Attribute ExtensionAttribute | 
            Get-Method -Name $Name -BindingFlags "Static,Public,NonPublic" -Attribute ExtensionAttribute |
            ForEach-Object { 
                $Method = $_
                $ParameterType = $_.GetParameters()[0].ParameterType

                ForEach($T in $TargetTypeName) {
                    Write-Verbose "Is '$T' a '$ParameterType'?"
                    if($ParameterType.Name -eq $T -or $ParameterType.FullName -eq $T) {
                        Write-Verbose "The name '$T' matches '$ParameterType'"
                        Add-Member -Input $Method -Type NoteProperty -Name ParamBlock -Value (Get-MemberSignature $Method -ParamBlock) -Force
                        Write-Output $Method
                        continue
                    }
                   
                    if($ParameterType.IsGenericType) {
                        $interface = $null
                        if(Test-AssignableToGeneric $T $ParameterType -interface ([ref]$interface)) {
                            # if([GenericHelper]::IsAssignableToGenericType( $T, $ParameterType )) {
                            Write-Verbose "'$T' is a generic that's assignable to '$ParameterType'"
                            Add-Member -Input $Method -Type NoteProperty -Name Extends -Value $interface.Value -Force
                            Add-Member -Input $Method -Type NoteProperty -Name ParamBlock -Value (Get-MemberSignature $Method -GenericArguments $interface.GetGenericArguments() -ParamBlock) -Force
                            Write-Output $Method
                            continue
                        }
                    } else {
                        if($TT = $T -as [type]) {
                            if($ParameterType.IsAssignableFrom($TT)) {
                                Write-Verbose "'$ParameterType' is assignable from '$TT'"
                                Add-Member -Input $Method -Type NoteProperty -Name ParamBlock -Value (Get-MemberSignature $Method -ParamBlock) -Force
                                Write-Output $Method
                                continue
                            }
                        }
                    }
                }
            }
    }
}

function Import-ExtensionMethod {
    [CmdletBinding()]
    param(
        # The type name to find Extension Methods for
        [Parameter(Mandatory=$false,Position=0)]
        [SupportsWildCards()]
        [String[]]$TargetTypeName,

        # A filter for the Extension Method name 
        [Parameter(Mandatory=$false)]
        [SupportsWildCards()]
        [String[]]$Name = "*",

        # The type to search for Extension Methods (defaults to search all types)
        [Parameter(Mandatory=$false,Position=99)]
        [SupportsWildCards()]
        [String[]]$TypeName = "*"
    )

    foreach($Method in Get-ExtensionMethod @PSBoundParameters) {
        Write-Verbose ("[{0}]::{1}({2})" -f $Method.DeclaringType, $Method.Name, @($Method.GetParameters()).Length)

        $ParamBlock = $Method | Get-MemberSignature -ParamBlock -AsExtensionMethod
        $Script = $NormalInvoke -f $ParamBlock, $Method.DeclaringType, $Method.Name

        if($Method.IsGenericMethod) { 
            $Types = @()
            $ParamBlock = $Method | Get-MemberSignature -GenericArgumentTypes $TargetTypeName -ConcreteArguments ([ref]$Types) -ParamBlock -AsExtensionMethod
            $Parameters = @($ParamBlock -replace '(?:\[[^\]]*\])+\](\$\w+)[^[]*','$1,' -split ',' | Where { $_ })
            Write-Verbose ($Parameters -join ",")
            if($Parameters.Length -gt 1) {
                $Parameters = @($Parameters[-1]) + @($Parameters[0..($Parameters.Length-2)])
                $Parameters = $Parameters -join ","
            } else { 
                $Parameters = "," + $Parameters
            }

            $Types = $Types -join ","

            Write-Verbose "Parameters: $Parameters"
            Write-Verbose "Types: $Types"
            # NOTE: the magic regex is to pull the $paramName off the end of the [ParamType]

            
            $Script = $GenericInvoke -f $ParamBlock, $Method.DeclaringType, $Method.Name, $Types, $Parameters
        }

        $Script = [ScriptBlock]::Create($Script)

        foreach($type in $TargetTypeName) {
            $MemberName = $Method.Name
            $success = $false
            $i=1
            while(!$success) {
                try {
                    Write-Debug "Update-TypeData -TypeName $type -MemberName $MemberName -MemberType ScriptMethod -Value $Script`n"
                    Update-TypeData -TypeName $type -MemberName $MemberName -MemberType ScriptMethod -Value $Script -ErrorAction Stop
                    $success = $True
                } catch {
                    if($_.Exception.Message -match "The member .* is already present.") {
                        $MemberName = ($MemberName -replace "^(.*?)\d*$",'$1') + $i++
                        continue
                    } else {
                        throw
                    }
                }
            }
        }
    }

}
$GenericInvoke = '
param({2}, {1})

$Types = @({0})
foreach($i in $Types) {{
    $null = $PSBoundParameters.Remove($i)
}}

Invoke-Generic -Static -On [{3}] -Named {4} -Types $Types -WithArgs (@($this) + $PSBoundParameters.Values)
'

$NormalInvoke = '
param({2})
[{3}]::{4}.Invoke(@($this) + $PSBoundParameters.Values)
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
        Write-Verbose ("[{0}]::{1}" -f $Method.DeclaringType, $Method.Name)

        $Script = $NormalInvoke
        if($Method.IsGenericMethod) {
            $Script = $GenericInvoke
            $TypesBlock = $(foreach($arg in $Method.GetGenericArguments()) {
                "[Parameter(Mandatory=`$true)]`$$($Arg.Name)"
            }) -Join ","
            $Types = $(foreach($arg in $Method.GetGenericArguments()) { '$' + $Arg.Name }) -Join ","
        }
        $Script = $Script -f $Types, $TypesBlock, $Method.ParamBlock, $Method.DeclaringType, $Method.Name
        $Script = [ScriptBlock]::Create($Script)

        foreach($type in $TargetTypeName) {
            Write-Debug "Update-TypeData -TypeName $type -MemberName $($Method.Name) -MemberType ScriptMethod -Value $Script"
            Update-TypeData -TypeName $type -MemberName $Method.Name -MemberType ScriptMethod -Value $Script
        }
    }

}
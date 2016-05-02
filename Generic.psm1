function Invoke-Generic {
    #.Synopsis
    #  Invoke Generic method definitions via reflection:
    [CmdletBinding()]
    param(
        # The object or type the method is on....
        [Parameter(Position=0,Mandatory=$true,ValueFromPipelineByPropertyName=$true)]
        [Alias('On')]
        $InputObject,

        # The method to Invoke
        [Parameter(Position=1,ValueFromPipelineByPropertyName=$true)]
        [Alias('Named')]
        [string]$MethodName,

        # The argument/parameter values to pass to the method
        [Parameter(Position=4, ValueFromRemainingArguments=$true, ValueFromPipelineByPropertyName=$true)]
        [Object[]]$WithArgs,

        # The types to use to make the generic method concrete.
        # Can usually be determined from the arguments (so it's ok to leave this empty usually)
        [Parameter()]
        [Alias("Types","ParameterTypes")]
        [Type[]]$GenericArgumentTypes,

        # If set, the method must be static, and InputObject must be a Type
        [Switch]$Static
    )
    begin {
        if($Static) {
            $BindingFlags = [System.Reflection.BindingFlags]"IgnoreCase,Public,Static"
        } else {
            $BindingFlags = [System.Reflection.BindingFlags]"IgnoreCase,Public,Static,Instance"
        }
    }
    process {
        $Type = $InputObject -as [Type]
        if($Type -match "^\[.*\]$") {
            $Type = $InputObject -replace "^\[(.*)\]$", '$1' -as [Type]
        }
        if(!$Type) { $Type = $InputObject.GetType() }

        # If -Static, the InputObject must be a type...
        if($Static) { $InputObject = $Type }


        if($WithArgs -and -not $GenericArgumentTypes) {
            $GenericArgumentTypes = $withArgs | % { $_.GetType() }
        } elseif(!$GenericArgumentTypes) {
            $GenericArgumentTypes = [Type]::EmptyTypes
        }

        Write-Debug "Get Method $MethodName from $Type"
      
        try {
            $MemberInfo = $Type.GetMethod($MethodName, $BindingFlags)
        } catch {
            if($_.Exception.InnerException -is [System.Reflection.AmbiguousMatchException] ) {
                Write-Debug "More that one MemberInfo found with $BindingFlags"
            } else {
                Write-Debug "MemberInfo not found with $BindingFlags"
            }
        }

        if(!$MemberInfo) {
            Write-Debug "$MethodName Method not found, search by name ..."
            try {
                $Methods = @($Type.GetMethods($BindingFlags) | Where-Object { $_.Name -eq $MethodName })
            } catch {
                throw "Cannot find $MethodName on $Type"
            }
            if($Methods.Count -eq 0){
                throw "Found no $MethodName on $Type"
            } elseif($Methods.Count -eq 1){
                $MemberInfo = @($Methods)[0]
                Write-Debug "Found a single ${MethodName}: $MemberInfo"
            } else {
                Write-Debug "Choosing from $($Methods.Count) methods for $MethodName"
                :methods foreach($MI in $Methods){

                    [Array]$Parameters = $MI.GetParameters()
                    [Array]$GenericArguments = $MI.GetGenericArguments()
                    [Array]$GenericParameters = @([PSObject]) * $GenericArgument.Count

                    # Determine if there are any generic parameters not satisfied by the arguments.
                    

                    # The number of generic arguments should match the number provided
                    if($GenericArgumentTypes.Count -ne $GenericArguments.Count) { continue }
                    Write-Debug "$($GenericArgumentTypes.Count) GenericArgumentTypes -eq $($GenericArguments.Count) GenericArguments"

                    # The number of parameters should match the number provided
                    if($WithArgs.Count -ne $Parameters.Count) { continue }
                    Write-Debug "$($WithArgs.Count) WithArgs -eq $($Parameters.Count) Parameters"

                    # Check the parameters more carefully
                    for($i=0; $i -lt $Parameters.Count; $i++) {

                        $parameterType = $Parameters[$i].ParameterType
                        if($parameterType.IsGenericParameter) {
                            $index = [array]::IndexOf($GenericArguments, $parameterType)
                            $ConcreteType = $GenericArgumentTypes[ $index ]
                            $GenericParameters[$index] = $ConcreteType
                            Write-Debug "GenericParameter: $parameterType = $ConcreteType"
                            continue
                        }




                        if( $parameterType.IsGenericType ) {
                            # GenericTypes are like List<T> or Dictionary<TKey,TValue> so we have to make the generic arguments concrete..
                            Write-Debug "GenericType: $parameterType"
                            $GenericType = foreach($typeArg in $parameterType.GetGenericArguments()) {
                                $genericIndex = [array]::IndexOf($GenericArguments, $typeArg)
                                $GenericArgumentTypes[$genericIndex]
                            }
                            try {
                                $ConcreteType = $parameterType.GetGenericTypeDefinition().MakeGenericType( $GenericType )
                            } catch {}
                            # If that didn't work, maybe it's because of an array type?
                            if( !$ConcreteType.IsAssignableFrom($WithArgs[$i].GetType()) ) {
                                Write-Debug "Parameter $i of $ConcreteType is not assignable try unwrapping arrays..."
                                $GenericType = foreach($typeArg in $GenericType.GetGenericArguments()) {
                                    if($typeArg.IsArray) {
                                        $typeArg.GetElementType()
                                    } elseif($typeArg -eq [hashtable]){
                                        $typeArg
                                    }
                                }
                                try {
                                    $ConcreteType = $parameterType.GetGenericTypeDefinition().MakeGenericType( $GenericType )
                                } catch {}
                            }

                            # If this still didn't work, it's most likely because they didn't pass types by hand...
                            if( !$ConcreteType.IsAssignableFrom($WithArgs[$i].GetType()) ) {
                                Write-Debug "Parameter $i of $ConcreteType is not assignable from $($WithArgs[$i].GetType())"
                                continue methods
                            }

                        } 
                        Write-Debug "Parameter $i of type $ConcreteType"
                    }
                    $MemberInfo = $MI
                    break
                }
            }
        }
        if(!$MemberInfo) {
            throw "Cannot find a Method $MethodName on $Type with the right signature..."
        }
        Write-Verbose "Make Generic Method for $MemberInfo"

        # [Type[]]$GenericParameters = @()
        # [Array]$ConcreteTypes = @($MemberInfo.GetParameters() | Select -Expand ParameterType)
        # for($i=0;$i -lt $GenericArgumentTypes.Count;$i++){
        #     Write-Verbose "$($GenericArgumentTypes[$i]) ? $($ConcreteTypes[$i] -eq $GenericArgumentTypes[$i])"
        #     if($ConcreteTypes[$i] -ne $GenericArgumentTypes[$i]) {
        #         $GenericParameters += $GenericArgumentTypes[$i]
        #     }
        #     $GenericArgumentTypes[$i] = Add-Member -in $GenericArgumentTypes[$i] -Type NoteProperty -Name IsGeneric -Value $($ConcreteTypes[$i] -ne $GenericArgumentTypes[$i]) -Passthru
        # }

        # $GenericArgumentTypes | Where-Object { $_.IsGeneric }
        # Write-Verbose "$($GenericParameters -join ', ') generic parameters"

        # Because so many generic methods are IEnumerable...

        $ElementTypes = if($WithArgs) {
            foreach($GenericType in $GenericArgumentTypes) {
                if($GenericType.IsArray) {
                    $GenericType.GetElementType()
                } else {
                    $GenericType
                }
            }
        } else {
            $GenericArgumentTypes
        }

        try {
            $MemberInfo = $MemberInfo.MakeGenericMethod( $ElementTypes )
            $AlternateMemberInfo = $MemberInfo.MakeGenericMethod( $GenericArgumentTypes )
        } catch {
            $MemberInfo = $MemberInfo.MakeGenericMethod( $GenericArgumentTypes )
        }


        if($WithArgs) {
            [Object[]]$Arguments = @();
            foreach($arg in $withArgs) {
                $Arguments += ,($arg | %{ $_.PSObject.BaseObject })
            }
            Write-Verbose "Arguments: $($(foreach($arg in $withArgs) { $arg.GetType().Name }) -Join ', ')"
            $Global:MemberInfo = $MemberInfo
            $Global:Type = $InputObject
            $Global:Arguments = $Arguments
            try {
                $MemberInfo.Invoke( $InputObject, $Arguments )
            } catch {
                if($AlternateMemberInfo) {
                    $AlternateMemberInfo.Invoke( $InputObject, $Arguments )
                }
            }
        } else {
            $MemberInfo.Invoke( $InputObject )
        }
    } 
}

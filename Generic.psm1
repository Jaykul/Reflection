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

        $ParameterTypes = foreach($arg in $WithArgs) { $arg.GetType() }
      
        try {
            $MemberInfo = $Type.GetMethod($MethodName, $BindingFlags)
            $MemberInfo = Resolve-GenericMethod $MemberInfo $GenericArgumentTypes $ParameterTypes
        } catch {
            $MemberInfo = $null
            if($_.Exception.InnerException -is [System.Reflection.AmbiguousMatchException] ) {
                Write-Debug "More that one MemberInfo found with $BindingFlags"
            } else {
                Write-Debug "MemberInfo not found with $BindingFlags"
            }
        }

        if($null -eq $MemberInfo) {
            Write-Debug "$MethodName Method not found, search by name ..."
            try {
                $Methods = @($Type.GetMethods($BindingFlags) | Where-Object { $_.Name -eq $MethodName })
            } catch {
                throw "Cannot find $MethodName on $Type"
            }
            if($Methods.Length -eq 0){
                throw "Found no $MethodName on $Type"
            } elseif($Methods.Length -eq 1){
                $MemberInfo = Resolve-GenericMethod (@($Methods)[0]) $GenericArgumentTypes $ParameterTypes
                Write-Debug "Found a single ${MethodName}: $MemberInfo"
            } else {
                Write-Debug "Choosing from $($Methods.Length) methods for $MethodName"
                foreach($MemberInfo in $Methods){
                    # The number of parameters should match the number provided
                    if($WithArgs.Length -ne $MemberInfo.GetParameters().Length) { continue }

                    $MemberInfo = Resolve-GenericMethod $MemberInfo $GenericArgumentTypes $ParameterTypes
                    if($null -ne $MemberInfo) { break }
                }
            }
        }

        if($null -eq $MemberInfo) {
            throw "Cannot find a Method $MethodName on $Type with the right signature..."
        }

        if($WithArgs) {
            Write-Debug "Invoke: $MemberInfo with arguments: $($(foreach($arg in $withArgs) { $arg.GetType().Name }) -Join ', ')"
            $MemberInfo.Invoke( $InputObject, $withArgs )
        } else {
            Write-Debug "Invoke: $MemberInfo"
            $MemberInfo.Invoke( $InputObject )
        }
    } 
}


function Resolve-GenericMethod {
    #.Synopsis
    #   Resolve a GenericMethod with the given argument types
    [CmdletBinding()]
    param( 
        # The generic method you want to resolve
        $MethodInfo,

        # The types to be used for extra generic arguments
        [Array]$GenericArgumentTypes,

        # The types of the parameters you want to pass to the method
        [Type[]]$ParameterTypes
    )

    Write-Debug "Resolve Generic Arguments for $MethodInfo"

    [Array]$Parameters = $MethodInfo.GetParameters()
    # Determine if there are any generic parameters not satisfied by the arguments.
    $unresolvedCount = 0
    $GenericTypes = $(
        :generic foreach($Generic in $MethodInfo.GetGenericArguments()) {
            Write-Debug "Resolve Generic Type: $Generic"
            for($i=0; $i -lt $Parameters.Length; $i++) {
                $parameterType = $Parameters[$i].ParameterType
                $argumentType = $ParameterTypes[$i]
                # If this parameter is the same as the generic
                if($parameterType.IsGenericParameter -and $parameterType -eq $Generic) {
                    Write-Output $argumentType
                    # Then the type of the generic is the type of the argument
                    Write-Debug "Resolved Generic Type $Generic to $argumentType"
                    continue generic
                }
            }

            # If there aren't any parameters which are exact matches
            for($i=0; $i -lt $Parameters.Length; $i++) {
                $parameterType = $Parameters[$i].ParameterType
                $argumentType = $ParameterTypes[$i]

                # look at the generic values of generic parameters
                if( $parameterType.IsGenericType) {
                    if($argumentType.IsGenericType ) {
                        $TypeArguments = $parameterType.GetGenericArguments()
                        for($j=0; $j -lt $TypeArguments.Length; $j++) {
                            if($TypeArguments[0] -eq $Generic){
                                $concrete = $argumentType.GetGenericArguments()[$j]
                                Write-Output $concrete
                                # Then the type of the generic is the type of the argument
                                Write-Debug "Resolved Generic Type $Generic to $concrete"
                                continue generic
                            }
                        }
                    } elseif( $argumentType.IsArray ) {
                        $concrete = $argumentType.GetElementType()
                        Write-Output $concrete
                        # Then the type of the generic is the type of the argument
                        Write-Debug "Resolved Generic Type $Generic to $concrete"
                        continue generic
                    }
                }
            }
            if($GenericArgumentTypes.Length -gt $unresolvedCount) {
                $concrete = $GenericArgumentTypes[$unresolvedCount++]
                Write-Output $concrete
                Write-Debug "Using $concrete for generic Type $Generic"
                continue generic
            }
            Write-Debug "Insufficient GenericArgumentTypes"
            return $null
        }
    )

    Write-Debug "Resolve Generic Method for $MethodInfo with $GenericTypes"
    return $MethodInfo.MakeGenericMethod( $GenericTypes )
}
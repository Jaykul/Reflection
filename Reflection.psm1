#requires -version 2.0
# ALSO REQUIRES Autoload for some functionality (Latest version: http://poshcode.org/3173)
# You should create a Reflection.psd1 with the contents: 
#    @{ ModuleToProcess="Reflection.psm1"; RequiredModules = @("Autoload"); GUID="64b5f609-970f-4e65-b02f-93ccf3e60cbb"; ModuleVersion="4.5.0.0" }
#
Add-Type -TypeDefinition @"
   using System;
   using System.ComponentModel;
   using System.Management.Automation;
   using System.Collections.ObjectModel; 
   [AttributeUsage(AttributeTargets.Field | AttributeTargets.Property)]
   public class TransformAttribute : ArgumentTransformationAttribute {
      private ScriptBlock _scriptblock;
      private string _noOutputMessage = "Transform Script had no output."; 
      public override string ToString() {
         return string.Format("[Transform(Script='{{{0}}}')]", Script);
      } 
      public override Object Transform( EngineIntrinsics engine, Object inputData) {
         try {
            Collection<PSObject> output = 
               engine.InvokeCommand.InvokeScript( engine.SessionState, Script, inputData );          
            if(output.Count > 1) {
               Object[] transformed = new Object[output.Count];
               for(int i =0; i < output.Count;i++) {
                  transformed[i] = output[i].BaseObject;
               }
               return transformed;
            } else if(output.Count == 1) {
               return output[0].BaseObject;
            } else {
               throw new ArgumentTransformationMetadataException(NoOutputMessage);
            }
         } catch (ArgumentTransformationMetadataException) {
            throw;
         } catch (Exception e) {
            throw new ArgumentTransformationMetadataException(string.Format("Transform Script threw an exception ('{0}'). See `$Error[0].Exception.InnerException.InnerException for more details.",e.Message), e);
         }
      }    
      public TransformAttribute() {
         this.Script = ScriptBlock.Create("{`$args}");
      }    
      public TransformAttribute( ScriptBlock Script ) {
         this.Script = Script;
      } 
      public ScriptBlock Script {
         get { return _scriptblock; }
         set { _scriptblock = value; }
      }    
      public string NoOutputMessage {
         get { return _noOutputMessage; }
         set { _noOutputMessage = value; }
      }   
   }
"@ 

$ReflectionRoot = Get-Variable PSScriptRoot* -ErrorAction SilentlyContinue | 
   Where-Object { $_.Name -eq "PSScriptRoot" } | 
   ForEach-Object { $_.Value }
if(!$ReflectionRoot) {
    $ReflectionRoot = Split-Path $MyInvocation.MyCommand.Path -Parent
}

Import-Module "${ReflectionRoot}\Parameters.psm1" -Force
Import-Module "${ReflectionRoot}\Generic.psm1" -Force
Import-Module "${ReflectionRoot}\Accelerator.psm1" -Force
Import-Module "${ReflectionRoot}\AST.psm1" -Force
Import-Module "${ReflectionRoot}\CliXml.psm1" -Force
Import-Module "${ReflectionRoot}\ExtensionMethods.psm1" -Force

function Get-Type {
   <#
      .Synopsis
         Gets the types that are currenty loaded in .NET, or gets information about a specific type
      .Description
         Gets information about one or more loaded types, or gets the possible values for an enumerated type or value.    
      .Example
         Get-Type
          
         Gets all loaded types (takes a VERY long time to print out)
      .Example
         Get-Type -Assembly ([PSObject].Assembly)
          
         Gets types from System.Management.Automation
      .Example
         [Threading.Thread]::CurrentThread.ApartmentState | Get-Type
          
         Gets all of the possible values for the ApartmentState property
      .Example
         [Threading.ApartmentState] | Get-Type
          
         Gets all of the possible values for an apartmentstate
   #>
   [CmdletBinding(DefaultParameterSetName="Assembly")]   
   param(
      # The Assemblies to search for types.
      # Can be an actual Assembly object or a regex to pass to Get-Assembly.
      [Parameter(ValueFromPipeline=$true)]
      [PsObject[]]$Assembly,

      # The type name(s) to search for (wildcard patterns allowed).
      [Parameter(Mandatory=$false,Position=0)]
      [SupportsWildCards()]
      [String[]]$TypeName,

      # A namespace to restrict where we selsect types from (wildcard patterns allowed).
      [Parameter(Mandatory=$false)]
      [SupportsWildCards()]
      [String[]]$Namespace,

      # A Base type they should derive from (wildcard patterns allowed).
      [Parameter(Mandatory=$false)]
      [SupportsWildCards()]
      [String[]]$BaseType,

      # An interface they should implement (wildcard patterns allowed).
      [Parameter(Mandatory=$false)]
      [SupportsWildCards()]
      [String[]]$Interface,

      # An Custom Attribute which should decorate the class
      [Parameter(Mandatory=$false)]
      [SupportsWildCards()]
      [String[]]$Attribute,


      # The enumerated value to get all of the possible values of
      [Parameter(ParameterSetName="Enum")]
      [PSObject]$Enum, 

      # Causes Private types to be included
      [Parameter()][Alias("Private","ShowPrivate")]
      [Switch]$Force
   )

    process {
        $Cmdlet = $PSCmdlet
        if($Cmdlet.ParameterSetName -eq 'Enum') {
            if($Enum -is [Enum]) {
                [Enum]::GetValues($enum.GetType())
            } elseif($Enum -is [Type] -and $Enum.IsEnum) {
                [Enum]::GetValues($enum)
            } else {
                throw "Specified Enum is neither an enum value nor an enumerable type"
            }
        }
        else {
            if($Assembly -as [Reflection.Assembly[]]) { 
                ## This is what we expected, move along
            } elseif($Assembly -as [String[]]) {
                $Assembly = Get-Assembly $Assembly
            } elseif(!$Assembly) {
                $Assembly = [AppDomain]::CurrentDomain.GetAssemblies()
            }

            :asm foreach ($asm in $assembly) {
                Write-Verbose "Testing Types from Assembly: $($asm.Location)"
                if ($asm) { 
                    $asm.GetTypes().Where({
                        $Type = $_
                        trap {
                            Write-Debug "Failure matching '$n'"
                            if( $_.Exception.LoaderExceptions -and $_.Exception.LoaderExceptions[0] -is [System.IO.FileNotFoundException] ) {
                                #$Cmdlet.WriteWarning( "Unable to load some types from $($asm.Location), required assemblies were not found. Use -Debug to see more detail")
                                WriteError -Cmdlet $Cmdlet -Exception $_.Exception -Message "Unable to load $Type from $($asm.Location), required assembly not found. Check LoaderExceptions for details" -ErrorId "PathNotFound,Reflection\Get-Type" -Category ObjectNotFound
                            } elseif( $_.Exception.LoaderExceptions ) {
                                WriteError -Cmdlet $Cmdlet -Exception $_.Exception -Message "Unable to load $Type from $($asm.Location). Check LoaderExceptions for details." -ErrorId "LoadException,Reflection\Get-Type" -Category InvalidType
                            } else {
                                WriteError -Cmdlet $Cmdlet -Exception $_.Exception -Message "Unable to load $Type from $($asm.Location)." -ErrorId "TypeEvaluation,Reflection\Get-Type" -Category InvalidType
                            }
                            write-output $false
                            continue
                        }

                        ( $Force -or $_.IsPublic ) -AND
                        ( !$Namespace -or $( foreach($n in $Namespace) { $n = $n -replace "\[","``[" -replace "]","``]"; $_.Namespace -like $n  } ) ) -AND
                        ( !$TypeName -or $( foreach($n in $TypeName)   { $n = $n -replace "\[","``[" -replace "]","``]"; $_.Name -like $n -or $_.FullName -like $n } ) -contains $True ) -AND
                        ( !$Attribute -or $( foreach($n in $Attribute) { $n = $n -replace "\[","``[" -replace "]","``]"; $_.CustomAttributes | ForEach { $_.AttributeType.Name -like $n -or $_.AttributeType.FullName -like $n } } ) -contains $True ) -AND
                        ( !$BaseType -or $( foreach($n in $BaseType)   { $n = $n -replace "\[","``[" -replace "]","``]"; $_.BaseType -like $n } ) -contains $True ) -AND
                        ( !$Interface -or @( foreach($n in $Interface) { $n = $n -replace "\[","``[" -replace "]","``]"; $_.GetInterfaces() -like $n } ).Count -gt 0 )
                    })
                }
            }
        }
    }
}

function Add-Assembly {
   #.Synopsis
   #  Load assemblies 
   #.Description
   #  Load assemblies from a folder
   #.Parameter Path
   #  Specifies a path to one or more locations. Wildcards are permitted. The default location is the current directory (.).
   #.Parameter Passthru
   #  Returns System.Runtime objects that represent the types that were added. By default, this cmdlet does not generate any output.
   #  Aliased to -Types
   #.Parameter Recurse
   #  Gets the items in the specified locations and in all child items of the locations.
   # 
   #  Recurse works only when the path points to a container that has child items, such as C:\Windows or C:\Windows\*, and not when it points to items that do not have child items, such as C:\Windows\*.dll
   [CmdletBinding()]
   param(
      [Parameter(ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true, Position=0)]
      [Alias("PSPath")]
      [string[]]$Path = ".",

      [Alias("Types")]
      [Switch]$Passthru,

      [Switch]$Recurse
   )
   process {
      foreach($file in Get-ChildItem $Path -Filter *.dll -Recurse:$Recurse) {
         Add-Type -Path $file.FullName -Passthru:$Passthru | Where { $_.IsPublic }
      }
   }
}

function Get-Assembly {
   <#
   .Synopsis 
      Get a list of assemblies available in the runspace
   .Description
      Returns AssemblyInfo for all the assemblies available in the current AppDomain, optionally filtered by partial name match
   .Parameter Name
      A regex to filter the returned assemblies. This is matched against the .FullName or Location (path) of the assembly.
   #>
   [CmdletBinding()]
   param(
      [Parameter(ValueFromPipeline=$true, Position=0)]
      [string[]]$Name = ''
   )
   process {
      [appdomain]::CurrentDomain.GetAssemblies() | Where {
         $Assembly = $_
         if($Name){ 
            $(
               foreach($n in $Name){
                  if(Resolve-Path $n -ErrorAction 0) {
                     $n = [Regex]::Escape( (Resolve-Path $n).Path )
                  }
                  $Assembly.FullName -match $n -or $Assembly.Location -match $n -or ($Assembly.Location -and (Split-Path $Assembly.Location) -match $n)
               }
            ) -contains $True 
         } else { $true }
      }         
   }
}

function Update-PSBoundParameters { 
   #.Synopsis
   #  Ensure a parameter value is set
   #.Description
   #  Update-PSBoundParameters takes the name of a parameter, a default value, and optionally a min and max value, and ensures that PSBoundParameters has a value for it.
   #.Parameter Name
   #  The name (key) of the parameter you want to set in PSBoundParameters
   #.Parameter Default
   #  A Default value for the parameter, in case it's not already set
   #.Parameter Min
   #  The Minimum allowed value for the parameter
   #.Parameter Max
   #  The Maximum allowed value for the parameter
   #.Parameter PSBoundParameters
   #  The PSBoundParameters you want to affect (this picks the local PSBoundParameters object, so you shouldn't have to set it)
   Param(
      [Parameter(Mandatory=$true,  Position=0)]
      [String]$Name,

      [Parameter(Mandatory=$false, Position=1)]
      $Default,

      [Parameter()]
      $Min,

      [Parameter()]
      $Max,

      [Parameter(Mandatory=$true, Position=99)]
      $PSBoundParameters=$PSBoundParameters
   )
   end {
      $outBuffer = $null
      ## If it's not set, and you passed a default, we set it to the default
      if($Default) {
         if (!$PSBoundParameters.TryGetValue($Name, [ref]$outBuffer))
         {
            $PSBoundParameters[$Name] = $Default
         }
      }
      ## If you passed a $max, and it's set greater than $max, we set it to $max
      if($Max) {
         if ($PSBoundParameters.TryGetValue($Name, [ref]$outBuffer) -and $outBuffer -gt $Max)
         {
            $PSBoundParameters[$Name] = $Max
         }
      }
      ## If you passed a $min, and it's set less than $min, we set it to $min
      if($Min) {
         if ($PSBoundParameters.TryGetValue($Name, [ref]$outBuffer) -and $outBuffer -lt $Min)
         {
            $PSBoundParameters[$Name] = $Min
         }
      }
      $PSBoundParameters
   }
}

function Get-Constructor {
   <#
   .Synopsis 
      Returns RuntimeConstructorInfo for the (public) constructor methods of the specified Type.
   .Description
      Get the RuntimeConstructorInfo for a type and add members "Syntax," "SimpleSyntax," and "Definition" to each one containing the syntax information that can use to call that constructor.
   .Parameter Type
      The type to get the constructor for
   .Parameter Force
      Force inclusion of Private and Static constructors which are hidden by default.
   .Parameter NoWarn
      Serves as the replacement for the broken -WarningAction. If specified, no warnings will be written for types without public constructors.
   .Example
      Get-Constructor System.IO.FileInfo
      
      Description
      -----------
      Gets all the information about the single constructor for a FileInfo object. 
   .Example
      Get-Type System.IO.*info mscorlib | Get-Constructor -NoWarn | Select Syntax
      
      Description
      -----------
      Displays the constructor syntax for all of the *Info objects in the System.IO namespace. 
      Using -NoWarn supresses the warning about System.IO.FileSystemInfo not having constructors.
     
   .Example
      $path = $pwd
      $driveName = $pwd.Drive
      $fileName = "$Profile"
      Get-Type System.IO.*info mscorlib | Get-Constructor -NoWarn | ForEach-Object { Invoke-Expression $_.Syntax }
      
      Description
      -----------
      Finds and invokes the constructors for DirectoryInfo, DriveInfo, and FileInfo.
      Note that we pre-set the parameters for the constructors, otherwise they would fail with null arguments, so this example isn't really very practical.


   #>
   [CmdletBinding()]
   param( 
      [Parameter(Mandatory=$true, ValueFromPipeline=$True, ValueFromPipelineByPropertyName=$true, Position=0)]
      [Alias("ParameterType")]
      [Type]$Type,
      [Switch]$Force,
      [Switch]$NoWarn
   )
   process { 
      $type.GetConstructors() | Where-Object { $Force -or $_.IsPublic -and -not $_.IsStatic } -OutVariable ctor 
      if(!$ctor -and !$NoWarn) { Write-Warning "There are no public constructors for $($type.FullName)" }
   }
}

function Test-AssignableToGeneric { 
   <#
      .Synopsis
         Determine if a specific type can be cast to the given generic type
   #>
   param(
      # The concrete type you want to test generics against
      [Parameter(Position=0, Mandatory = $true)]
      [Type]$type,

      # A Generic Type to test 
      [Parameter(ValueFromPipeline=$true, Position=1, Mandatory = $true)]
      [Type]$genericType,

      # Check the GenericTypeDefinition of the GenericType (in case it's typed)
      [Switch]$force,

      # If the type is assignable because of an interface, return that interface here
      [Parameter(Position=2)]
      [ref]$interface = [ref]$null
   )

   process {
      $interfaces = $type.GetInterfaces()
      if($type.IsGenericType -and ($type.GetGenericTypeDefinition().equals($genericType))) {
         return $true
      }

      foreach($i in $interfaces) 
      { 
         if($i.IsGenericType -and $i.GetGenericTypeDefinition().Equals($genericType)) {
            $interface.Value = $i
            return $true
         }
         if($i.IsGenericType -and $i.GetGenericTypeDefinition().Equals($genericType.GetGenericTypeDefinition())) {
            $genericTypeArgs = @($genericType.GetGenericArguments())[0]
            if(($genericTypeArgs.IsGenericParameter -and 
                $genericTypeArgs.BaseType.IsAssignableFrom( @($i.GetGenericArguments())[0] ) ) -or 
               $genericTypeArgs.IsAssignableFrom( @($i.GetGenericArguments())[0] )) {
               
               $interface.Value = $i
               return $true
            }
         }
      }
      if($force -and $genericType -ne $genericType.GetGenericTypeDefinition()) {
         if(Test-AssignableToGeneric $type $genericType.GetGenericTypeDefinition()) {
            return $true
         }
      }

      $base = $type.BaseType
      if(!$base) { return $false }

      Test-AssignableToGeneric $base $genericType
   }
}

function Get-Method {
   <#
   .Synopsis 
      Returns MethodInfo for the (public) methods of the specified Type.
   .Description
      Get the MethodInfo for a type and add members "Syntax," "SimpleSyntax," and "Definition" to each one containing the syntax information that can use to call that method.
   .Parameter Type
   .Parameter Name
      
   .Parameter Force
   #>
   [CmdletBinding(DefaultParameterSetName="Type")]
   param( 
      # The type to get methods from
      [Parameter(ParameterSetName="Type", Mandatory=$true, ValueFromPipeline=$True, ValueFromPipelineByPropertyName=$true, Position=0)]
      [Type]$Type,
      # The name(s) of the method(s) you want to retrieve (Accepts Wildcard Patterns)
      [Parameter(Mandatory=$false, Position=1)]
      [SupportsWildCards()]
      [PSDefaultValue(Help='*')]
      [String[]]$Name ="*",
      # Force inclusion of Private methods and property accessors which are hidden by default.
      [Switch]$Force,
      # The Binding Flags filter the output. defaults to returning all methods, static or instance
      [PSDefaultValue(Help='Instance,Static,Public')]
      [System.Reflection.BindingFlags]$BindingFlags = $(if($Force){"Instance,Static,Public,NonPublic"} else {"Instance,Static,Public"}),

      # An Custom Attribute which should decorate the class
      [Parameter(Mandatory=$false)]
      [SupportsWildCards()]
      [String[]]$Attribute

   )
   process {
      Write-Verbose "[$($type.FullName)].GetMethods(`"$BindingFlags`")"
      Write-Verbose "[$($type.FullName)].GetConstructors(`"$BindingFlags`")"
      Write-Verbose "Filter by Name -like '$Name'"

      
      $Type.GetMethods($BindingFlags) + $type.GetConstructors($BindingFlags) | Where-Object {
         # Hide the Property accessor methods
         ($Force -or !$_.IsSpecialName -or $_.Name -notmatch "^get_|^set_") -AND 
         # And Filter by Name, if necessary 
         ($Name -eq "*" -or ($( foreach($n in $Name) { $_.Name -like $n } ) -contains $True)) -AND
         (!$Attribute -or $( foreach($n in $Attribute) { $_.CustomAttributes | ForEach { $_.AttributeType.Name -like $n -or $_.AttributeType.FullName -like $n } } ) -contains $True ) 
      }
   }
}

# if(!($RMI = Get-TypeData System.Reflection.RuntimeMethodInfo) -or !$RMI.Members.ContainsKey("TypeName")) {
#    Update-TypeData -TypeName System.Reflection.RuntimeMethodInfo -MemberName "TypeName" -MemberType ScriptProperty -Value { $this.ReflectedType.FullName }
#    Update-TypeData -TypeName System.Reflection.RuntimeMethodInfo -MemberName "Definition" -MemberType ScriptProperty -Value { Get-MemberSignature $this -Simple }
#    Update-TypeData -TypeName System.Reflection.RuntimeMethodInfo -MemberName "Syntax" -MemberType AliasProperty -Value "Definition"
#    Update-TypeData -TypeName System.Reflection.RuntimeMethodInfo -MemberName "SafeSyntax" -MemberType ScriptProperty -Value { Get-MemberSignature $this }
# }

function Get-MemberSignature {
    <#
        .Synopsis
            Get the powershell signature for calling a member.
    #>
    [CmdletBinding(DefaultParameterSetName="CallSignature")]
    param(
        # The Method we're getting the signature for
        [Parameter(ValueFromPipeline=$true,Mandatory=$true,Position=0)]
        [System.Reflection.MethodBase]$MethodBase,

        [Parameter(Mandatory=$false, Position=1)]
        [Alias("GenericArguments")]
        [Type[]]$GenericArgumentTypes,
      
        # Return the simplified markup
        [Parameter(ParameterSetName="CallSignature")]
        [Switch]$Simple,
      
        # Return a param block
        [Parameter(ParameterSetName="ParamBlock")]
        [Switch]$ParamBlock,

        [Parameter()]
        [Switch]$AsExtensionMethod,

        [ref]$ConcreteArguments
    )
    process {
        if($PSCmdlet.ParameterSetName -eq "ParamBlock") { $Simple = $true }
        [Array]$GenericArguments = $MethodBase.GetGenericArguments()
        if($PSBoundParameters.ContainsKey("ConcreteArguments")) {
            $ConcreteArguments.Value = @("[PSObject]") * $GenericArguments.Length
        }

        Write-Verbose "GenericArguments: $($GenericArguments -join ', ')"
        [int[]]$used = @()

        $parameters = $MethodBase.GetParameters()
        $parameters = $(
            foreach($param in $parameters) {
                # Write-Verbose "$($param.ParameterType.UnderlyingSystemType.FullName) - $($param.ParameterType)"
                $paramType = $param.ParameterType
                if($paramType.Name.EndsWith('&')) { $ref = '[ref]' } else { $ref = '' }
                if($paramType.IsArray) { $array = ',' } else { $array = '' }

                if($GenericArgumentTypes -and $GenericArguments) {
                    if($paramType.IsGenericType) {
                        try {
                            $ga = 0
                            $GenericType = @(
                                foreach($typeArg in $paramType.GetGenericArguments()) {
                                    $used += $index = [array]::IndexOf($GenericArguments, $typeArg)

                                    if($index -lt 0) {
                                        $typeArg
                                    } else {
                                        if($PSBoundParameters.ContainsKey("ConcreteArguments")) {
                                            $ConcreteArguments.Value[$index] = "`$$($param.Name).GetType().GetGenericArguments()[$ga]"
                                        }
                                        $OutType = $GenericArgumentTypes[$index]
                                        if($OutType.IsArray) {
                                            $OutType.GetElementType()
                                        } else {
                                            $OutType
                                        }
                                    }
                                    $ga++
                                }
                            )

                            $paramType = $paramType.GetGenericTypeDefinition().MakeGenericType( $GenericType )
                        } catch { 
                            continue 
                        }
                    } elseif($paramType.IsGenericParameter) { 
                        $used += $index = [array]::IndexOf($GenericArguments, $typeArg)
                        $paramType = $GenericArgumentTypes[$index]
                        if($PSBoundParameters.ContainsKey("ConcreteArguments")) {
                            $ConcreteArguments.Value[$index] = "`$$($param.Name).GetType()"
                        }
                    }
                } else {
                    if($paramType.IsGenericType) {
                        $GenericType = @(
                            foreach($typeArg in $paramType.GetGenericArguments()) {
                                if($typeArg.IsGenericParameter) { [PSObject] } else { $typeArg } 
                            }
                        )
                        $paramType = $paramType.GetGenericTypeDefinition().MakeGenericType($GenericType)
                    } elseif($paramType.IsGenericParameter) { 
                        $paramType = [PSObject]
                    }
                }
                New-Object PSObject -Property @{
                    ParameterType = $paramType.ToString().TrimEnd('&')
                    ParameterName = $param.Name
                }
            }
        )

        if($GenericArgumentTypes -and $GenericArguments) {
            $notUsed = @(0..($GenericArguments.Count-1) | Where-Object { $_ -notin $used })
            if($notused.Count -gt 0) {
                $i = 1
                $Remaining = $GenericArgumentTypes[$notUsed] | % {
                    New-Object PSObject -Property @{
                        ParameterType = $_.ToString().TrimEnd('&')
                        ParameterName = "GenericArgumentType$($i++)"
                    }
                }
                $parameters = @(@($parameters) + @($Remaining))
            }
        }

        $parameters = $(
            foreach($paramType in $parameters) {
                if($ParamBlock) { 
                    '[Parameter(Mandatory=$true)]{0}[{1}]${2}' -f $ref, $paramType.ParameterType, $paramType.ParameterName
                } elseif($Simple) { 
                    '[{0}]${1}' -f $paramType.ParameterType, $paramType.ParameterName
                } else {
                    '{0}({1}[{2}]${3})' -f $ref, $array, $paramType.ParameterType, $paramType.ParameterName
                }
            }
        )

        # For extension methods, we need to push "this" to the end, because we won't ever specify it
        if($ParamBlock -and ($AsExtensionMethod -or ($MethodBase.CustomAttributes | ForEach-Object { $_.AttributeType -eq [System.Runtime.CompilerServices.ExtensionAttribute]}) -contains $true)) {
            $thispar, $parameters = $parameters
            $thispar = "$thispar = `$this" -replace 'Mandatory=\$true'
            $parameters = @($parameters) + @($thispar) | Where { $_ }
        }

        $ReturnType = $MethodBase.ReturnType
        if($GenericArgumentTypes -and $GenericArguments) {
            if($returnType.IsGenericType) {
                try {
                    $GenericType = @(foreach($typeArg in $returnType.GetGenericArguments()) {
                        $used += $index = [array]::IndexOf($GenericArguments, $typeArg)
                        if($index -lt 0) {
                            $typeArg
                        } else {
                            $GenericArgumentTypes[$index]
                        }
                    })

                    $returnType = $returnType.GetGenericTypeDefinition().MakeGenericType( $GenericType )
                } catch { continue }
            } elseif($returnType.IsGenericParameter) { 
                $used += $index = [array]::IndexOf($GenericArguments, $typeArg)
                $returnType = $GenericArgumentTypes[$index]
            }
        } else {
            if($returnType.IsGenericType) {
                $returnType = $returnType.GetGenericTypeDefinition().MakeGenericType(@($returnType.GetGenericArguments() | % { if($_.IsGenericParameter) { [PSObject] } else { $_ } } ))
            } elseif($returnType.IsGenericParameter) { 
                $returnType = [PSObject]
            }
        }


        if($ParamBlock) {
            $parameters -join ', '
        } elseif($MethodBase.IsConstructor) {
            "New-Object $($MethodBase.ReflectedType.FullName) $($parameters -join ', ')"
        } elseif($Simple) {
            "<# [$($ReturnType.FullName)] #> $($MethodBase.Name)($($parameters -join ', '))"
        } elseif($MethodBase.IsStatic) {
            "<# [$($ReturnType.FullName)] #> [$($MethodBase.ReflectedType.FullName)]::$($MethodBase.Name)($($parameters -join ', '))"
        } else {
            "<# [$($ReturnType.FullName)] #> `$$($MethodBase.ReflectedType.Name)Object.$($MethodBase.Name)($($parameters -join ', '))"
        }
    }
}

function Read-Choice {
   <#
      .Synopsis
         Prompt the user for a choice, and return the (0-based) index of the selected item
      .Example
         Read-Choice -Prompt "WEBPAGE BUILDER MENU"  "&Create Webpage","&View HTML code","&Publish Webpage","&Remove Webpage","E&xit"
      .Example
         [bool](Read-Choice "Do you really want to do this?" "&No","&Yes" -Default 1)
        
         This example takes advantage of the 0-based index to convert No (0) to False, and Yes (1) to True. It also specifies YES as the default, since that's the norm in PowerShell.
      .Example
         Read-Choice "Do you really want to delete them all?" @{label="&Yes"; Help="Confirm that you want to delete all of the files"},@{Label="&No"; Help="Do not delete all files. You will be prompted to delete each file individually."}
        
         Specifies the labels and help text explicitly using hashtables.
      .Example
         $Env:PSModulePath -Split ';' | Read-Choice -Passthru | Get-Item

         Pipes paths into Read-Choice to use as selections, and passes through the selected path to Get-Item
      .Example
         Get-Process | Where { $_.VM -gt 500MB } | Read-Choice -Multi -Label ProcessName -Value Id -Help { if($_.Path) { $_.Path } else { $_.ProcessName + " (" + $_.ID + ")" } }
         
         An advanced example dealing with pipeline input. In this example we're taking processes and rendering the name as the labels, and showing the path (or process name and ID) as help, and RETURNING the process Id of the selected processes
   #>
   [CmdletBinding(DefaultParameterSetName="InputObject")]
   param(
      # An array of choices (or menu items), with optional ampersands (&) in them to mark (unique) characters which can be used to select each item.
      # Can be an array of strings which are used as labels, or objects (or hashtables) with properties for Name (Name or Label or Key) and Help (Help or Expression or Value)
      [Parameter(Mandatory=$False, ParameterSetName="InputObject", ValueFromPipeline = $true)]
      [Object]$InputObject,

      # This is the prompt that will be presented to the user. Basically, the question you're asking.
      [Parameter(Mandatory=$False, Position=0)]
      [string]$Prompt = "Choose one of the following options:",

      # An array of choices (or menu items), with optional ampersands (&) in them to mark (unique) characters which can be used to select each item.
      # Can be an array of strings which are used as labels, or objects (or hashtables) with properties for Name (Name or Label or Key) and Help (Help or Expression or Value)
      [Parameter(Mandatory=$true, Position=1, ParameterSetName="Choices")]
      [Array]$Choices,  

      # The name of a property of the InputObject to be used as the Label text.
      # NOTE: this parameter is ValueFromPipelineByPropertyName and you can use a scriptblock to calculate something based on the InputObject
      [Parameter(Mandatory=$false, ParameterSetName="InputObject", ValueFromPipelineByPropertyName = $true)]
      [Alias("Name")]
      [String]$Label,

      # The name of a property of the InputObject to be used as the Help text.
      # NOTE: this parameter is ValueFromPipelineByPropertyName and you can use a scriptblock to calculate something based on the InputObject
      [Parameter(Mandatory=$false, ParameterSetName="InputObject", ValueFromPipelineByPropertyName = $true)]
      [String]$Help,

      # The name of a property of the InputObject to be used as the Value for output.
      # If -Value is set, it forces -Passthru (since there's no other reason to use Value)
      # NOTE: this parameter is ValueFromPipelineByPropertyName and you can use a scriptblock to calculate something based on the InputObject
      [Parameter(Mandatory=$false, ParameterSetName="InputObject", ValueFromPipelineByPropertyName = $true)]
      [String]$Value,

      # An additional caption that can be displayed (usually above the Prompt) as part of the prompt. Defaults to "Please choose!"
      [Parameter(Mandatory=$False)]
      [string]$Title = "Please choose!",

      # The (0-based) index of the menu item to select by default (defaults to zero).
      [Parameter(Mandatory=$False)]
      [int[]]$Default  = 0,

      # Prompt the user to select more than one option. This changes the prompt display for the default PowerShell.exe host to show the options in a column and allows them to choose multiple times.
      # Note: when you specify MultipleChoice you may also specify multiple options as the default!
      [Switch]$MultipleChoice,

      # Assume options aren't currently sorted or labelled, and sort them by the key letter we choose
      # Setting -Sorted forces -Passthru (since otherwise there's no way to tell what they selected)
      [Switch]$Sorted,

      # Causes the Choices objects to be output instead of just the indexes
      [Switch]$Passthru
   )
   begin { 
      $ChoiceDescriptions = @() 
      $Output = @()
      if($PSCmdlet.ParameterSetName -eq "Choices") {
         $ChoiceDescriptions = $(
            foreach($choice in $Choices) {
               if($Choice -is [System.Collections.IDictionary]) {
                  foreach($Key in $Choice.Keys) {
                     if("Label" -like "${Key}*" -or "Name" -like "${Key}*") { 
                        $Name = $Choice.$Key
                     } elseif ("Help" -like "${Key}*" -or "Value" -like "${Key}*" -or "Expression" -like "${Key}*") {
                        $Value = $Choice.$Key
                     } else {
                        Write-Error "The key $Key is not valid. Expected `"Label`" and `"Help`""
                     }
                  }
                  if($Name -and $Value) {
                     New-Object System.Management.Automation.Host.ChoiceDescription $Name, $Value
                  } else {
                     Write-Error "The parameter $Choice is not valid. Expected `"Label`" and `"Help`" keys."
                  }
               } else {
                  New-Object System.Management.Automation.Host.ChoiceDescription "$Choice", "$Choice"
               }
               $Output += $Choice
            }
         )
      }
      
      # Set calculated* variables true if the parameter is a scriptblock to calculate
      $CalculatedLabel = $PSBoundParameters.ContainsKey('Label') -and !$Label
      $CalculatedHelp  = $PSBoundParameters.ContainsKey('Help') -and !$Help
      $CalculatedValue = $PSBoundParameters.ContainsKey('Value') -and !$Value

      if($PSBoundParameters.ContainsKey('Value')) {
         $Passthru = $True
      }
   }
   process {
      if($PSCmdlet.ParameterSetName -eq 'InputObject') {
         $Output   += if($CalculatedValue) { $Value } elseif($Value -and $InputObject.$Value) { $InputObject.$Value } elseif($Value) { $Value } else { $InputObject }
         $LabelText = if($CalculatedLabel) { $Label } elseif($Label -and $InputObject.$Label) { $InputObject.$Label } elseif($Label) { $Label } else { "$InputObject" }
         $HelpText  = if($CalculatedHelp)  { $Help  } elseif($Help -and $InputObject.$Help)   { $InputObject.$Help  } elseif($Help)  { $Help  } else { $LabelText } 

         if($LabelText -and $HelpText) {
            $ChoiceDescriptions += New-Object System.Management.Automation.Host.ChoiceDescription $LabelText, $HelpText
         }
      }
   }
   end {
      if(@($ChoiceDescriptions).Count -eq 0) {
         Write-Error "There were no choices generated, no input"
         return
      } elseif (@($ChoiceDescriptions).Count -eq 1) {
         return $Output
      }


      [string[]]$Labels = $ChoiceDescriptions | % { $_.Label }
      # Try making unique keys for the labels:
      $Keys = @()
      # If they already have a key
      for($l =0; $l -lt $Labels.Count; $l++) {
         if($Labels[$l].IndexOf('&') -ge 0) {
            $Keys += $Labels[$l][($Labels[$l].IndexOf('&')+1)]
         }
      }
      # Otherwise pick the first letter that's not a key
      for($l =0; $l -lt $Labels.Count; $l++) {
         if($Labels[$l].IndexOf('&') -lt 0) {
            for($i = 0; $i -lt $Labels[$l].Length; $i++) {
               if($Keys -notcontains $Labels[$l][$i]) {
                  $Keys += $Labels[$l][$i]
                  $Labels[$l] = $Labels[$l].Insert($i,'&')
                  $ChoiceDescriptions[$l] = New-Object System.Management.Automation.Host.ChoiceDescription $Labels[$l], $ChoiceDescriptions[$l].HelpMessage
                  break
               }
            }
         }
      }
      # Otherwise, add a number or a letter
      for($l =0; $l -lt $Labels.Count; $l++) {
         if($Labels[$l].IndexOf('&') -lt 0) {
            foreach($i in 49..57+66..90) {
               if($Keys -notcontains [string][char]$i) {
                  $Keys += [string][char]$i
                  $Labels[$l] = '{0}(&{1})' -f $Labels[$l], ([string][char]$i)
                  $ChoiceDescriptions[$l] = New-Object System.Management.Automation.Host.ChoiceDescription $Labels[$l], $ChoiceDescriptions[$l].HelpMessage
                  break
               }
            }
         }
      }
      if($ChoiceDescriptions.Length -gt 34 -and $Labels -notmatch '&') {
         Write-Warning "There are too many choices, some may be unpickable!"
      }

      if($Sorted) {
         $Passthru = $True
         $Max = 1000
         $Indexes = $Labels | %{ if(($amp = $_.IndexOf('&')) -lt 0) { ($Max++) } else { [int][byte][char]"$($_[($amp+1)])".ToUpperInvariant() } }
         [Array]::Sort($Indexes.Clone(), $Output)
         [Array]::Sort($Indexes, $ChoiceDescriptions)
      }

      # Passing an array as the $Default triggers multiple choice prompting.
      if(!$MultipleChoice) { [int]$Default = $Default[0] }

      [int[]]$Answer = $Host.UI.PromptForChoice($Title,$Prompt,$ChoiceDescriptions,$Default)

      if($Passthru) {
         Write-Verbose "$Answer"
         Write-Output  $Output[$Answer]
      } else {
         Write-Output $Answer
      }
   }
}

function Get-Argument {
   param(
      [Type]$Target,
        [ref]$Method,
        [Array]$Arguments
   )
   end {
      trap {
         write-error $_
         break
      }

      $flags = [System.Reflection.BindingFlags]"public,ignorecase,invokemethod,instance"

      [Type[]]$Types = @(
         foreach($arg in $Arguments) {
            if($arg -is [type]) { 
               $arg 
            }
            else {
               $arg.GetType()
            }
         } 
      )
      try {
         Write-Verbose "[$($Target.FullName)].GetMethod('$($Method.Value)', [$($Flags.GetType())]'$flags', `$null, ([Type[]]($(@($Types|%{$_.Name}) -join ','))), `$null)"
         $MethodBase = $Target.GetMethod($($Method.Value), $flags, $null, $types, $null)
         $Arguments
         if($MethodBase) {
            $Method.Value = $MethodBase.Name
         }
      } catch { }
      
      if(!$MethodBase) {
         Write-Verbose "Try again to get $($Method.Value) Method on $($Target.FullName):"
         $MethodBase = Get-Method $target $($Method.Value)
         if(@($MethodBase).Count -gt 1) {
            $i = 0
            $i = Read-Choice -Choices $(foreach($mb in $MethodBase) { @{ "$($mb.SafeSyntax) &$($i = $i+1;$i)`b`n" =  $mb.SafeSyntax } }) -Default ($MethodBase.Count-1) -Caption "Choose a Method." -Message "Please choose which method overload to invoke:"
            [System.Reflection.MethodBase]$MethodBase = $MethodBase[$i]
         }
         
         
         ForEach($parameter in $MethodBase.GetParameters()) {
            $found = $false
            For($a =0;$a -lt $Arguments.Count;$a++) {
               if($argument[$a] -as $parameter.ParameterType) {
                  Write-Output $argument[$a]
                  if($a -gt 0 -and $a -lt $Arguments.Count) {
                     $Arguments = $Arguments | Select -First ($a-1) -Last ($Arguments.Count -$a)
                  } elseif($a -eq 0) {
                     $Arguments = $Arguments | Select -Last ($Arguments.Count - 1)
                  } else { # a -eq count
                     $Arguments = $Arguments | Select -First ($Arguments.Count - 1)
                  }
                  $found = $true
                  break
               }
            }
            if(!$Found) {
               $userInput = Read-Host "Please enter a [$($parameter.ParameterType.FullName)] value for $($parameter.Name)"
               if($userInput -match '^{.*}$' -and !($userInput -as $parameter.ParameterType)) {
                  Write-Output ((Invoke-Expression $userInput) -as $parameter.ParameterType)
               } else {
                  Write-Output ($userInput -as $parameter.ParameterType)
               }
            }
         }
      }
   }
}

function Invoke-Member {
   [CmdletBinding()]
   param(        
      [parameter(position=10, valuefrompipeline=$true, mandatory=$true)]
      [allowemptystring()]
      $InputObject,

      [parameter(position=0, mandatory=$true)]
      [validatenotnullorempty()]
      $Member,

      [parameter(position=1, valuefromremainingarguments=$true)]
      [allowemptycollection()]
      $Arguments,

      [parameter()]
      [switch]$Static
   )
   #  begin {
      #  if(!(get-member SafeSyntax -input $Member -type Property)){
         #  if(get-member Name -inpup $Member -Type Property) {
            #  $Member = Get-Method $InputObject $Member.Name
         #  } else {
            #  $Member = Get-Method $InputObject $Member
         #  }
      #  }
      #  $SafeSyntax = [ScriptBlock]::Create( $Member.SafeSyntax )
   #  }
   process {
      #  if ($InputObject) 
      #  {
         #  if ($InputObject | Get-Member $Member -static:$static) 
         #  {

            if ($InputObject -is [type]) {
                $target = $InputObject
            } else {
                $target = $InputObject.GetType()
            }
         
            if(Get-Member $Member -InputObject $InputObject -Type Properties) {
               $_.$Member
            } 
            elseif($Member -match "ctor|constructor") {
               $Member = ".ctor"
               [System.Reflection.BindingFlags]$flags = "CreateInstance"
               $InputObject = $Null
            } 
            else {
               [System.Reflection.BindingFlags]$flags = "IgnoreCase,Public,InvokeMethod"
               if($Static) { $flags = "$Flags,Static" } else { $flags = "$Flags,Instance" }
            }
            [ref]$Member = $Member
            [Object[]]$Parameters = Get-Argument $Target $Member $Arguments
            [string]$Member = $Member.Value

            Write-Verbose $(($Parameters | %{ '[' + $_.GetType().FullName + ']' + $_ }) -Join ", ")

            try {
               Write-Verbose "Invoking $Member on [$target]$InputObject with [$($Flags.GetType())]'$flags' and [$($Parameters.GetType())]($($Parameters -join ','))"
               Write-Verbose "[$($target.FullName)].InvokeMember('$Member', [System.Reflection.BindingFlags]'$flags', `$null, '$InputObject', ([object[]]($(($Parameters | %{ '[' + $_.GetType().FullName + ']''' + $_ + ''''}) -join', '))))"
               $target.InvokeMember($Member, [System.Reflection.BindingFlags]"$flags", $null, $InputObject, $Parameters)
            } catch {
               Write-Warning $_.Exception
                if ($_.Exception.Innerexception -is [MissingMethodException]) {
                    write-warning "Method argument count (or type) mismatch."
                }
            }
         #  } else {
            #  write-warning "Method $Member not found."
         #  }
      #  }
   }
}


###############################################################################
##### Imported from PowerBoots

$Script:CodeGenContentProperties = 'Content','Child','Children','Frames','Items','Pages','Blocks','Inlines','GradientStops','Source','DataPoints', 'Series', 'VisualTree'
$DependencyProperties = @{}
if(Test-Path $PSScriptRoot\DependencyPropertyCache.xml) {
    #$DependencyProperties = [System.Windows.Markup.XamlReader]::Parse( (gc $PSScriptRoot\DependencyPropertyCache.xml) )
    $DependencyProperties = Import-CliXml  $PSScriptRoot\DependencyPropertyCache.xml 
}

function Get-ReflectionModule { $executioncontext.sessionstate.module }

function Set-ObjectProperties {
   [CmdletBinding()]
   param( $Parameters, [ref]$DObject )

   if($DObject.Value -is [System.ComponentModel.ISupportInitialize]) { $DObject.Value.BeginInit() }

   if($DebugPreference -ne "SilentlyContinue") { Write-Host; Write-Host ">>>> $($Dobject.Value.GetType().FullName)" -fore Black -back White }
   foreach ($param in $Parameters) {
      if($DebugPreference -ne "SilentlyContinue") { Write-Host "Processing Param: $($param|Out-String )" }
      ## INGORE DEPENDENCY PROPERTIES FOR NOW :)
      if($param.Key -eq "DependencyProps") {
      ## HANDLE EVENTS ....
      }
      elseif ($param.Key.StartsWith("On_")) {
         $EventName = $param.Key.SubString(3)
         if($DebugPreference -ne "SilentlyContinue") { Write-Host "Event handler $($param.Key) Type: $(@($param.Value)[0].GetType().FullName)" }
         $sb = $param.Value -as [ScriptBlock]
         if(!$sb) {
            $sb = (Get-Command $param.Value -CommandType Function,ExternalScript).ScriptBlock
         }
         $Dobject.Value."Add_$EventName".Invoke( $sb );
         # $Dobject.Value."Add_$EventName".Invoke( ($sb.GetNewClosure()) );

         # $Dobject.Value."Add_$EventName".Invoke( $PSCmdlet.MyInvocation.MyCommand.Module.NewBoundScriptBlock( $sb.GetNewClosure() ) );


      } ## HANDLE PROPERTIES ....
      else { 
         try {
            ## TODO: File a BUG because Write-DEBUG and Write-VERBOSE die here.
            if($DebugPreference -ne "SilentlyContinue") {
               Write-Host "Setting $($param.Key) of $($Dobject.Value.GetType().Name) to $($param.Value.GetType().FullName): $($param.Value)" -fore Gray
            }
            if(@(foreach($sb in $param.Value) { $sb -is [ScriptBlock] }) -contains $true) {
               $Values = @()
               foreach($sb in $param.Value) {
                  $Values += & (Get-ReflectionModule) $sb
               }
            } else {
               $Values = $param.Value
            }

            if($DebugPreference -ne "SilentlyContinue") { Write-Host ([System.Windows.Markup.XamlWriter]::Save( $Dobject.Value )) -foreground green }
            if($DebugPreference -ne "SilentlyContinue") { Write-Host ([System.Windows.Markup.XamlWriter]::Save( @($Values)[0] )) -foreground green }

            Set-Property $Dobject $Param.Key $Values

            if($DebugPreference -ne "SilentlyContinue") { Write-Host ([System.Windows.Markup.XamlWriter]::Save( $Dobject.Value )) -foreground magenta }

            if($DebugPreference -ne "SilentlyContinue") {
               if( $Dobject.Value.$($param.Key) -ne $null ) {
                  Write-Host $Dobject.Value.$($param.Key).GetType().FullName -fore Green
               }
            }
         }
         catch [Exception]
         {
            Write-Host "COUGHT AN EXCEPTION" -fore Red
            Write-Host $_ -fore Red
            Write-Host $this -fore DarkRed
         }
      }

      while($DependencyProps) {
         $name, $value, $DependencyProps = $DependencyProps
         $name = ([string]@($name)[0]).Trim("-")
         if($name -and $value) {
            Set-DependencyProperty -Element $Dobject.Value -Property $name -Value $Value
         }
      }
   }
   if($DebugPreference -ne "SilentlyContinue") { Write-Host "<<<< $($Dobject.Value.GetType().FullName)" -fore Black -back White; Write-Host }

   if($DObject.Value -is [System.ComponentModel.ISupportInitialize]) { $DObject.Value.EndInit() }

}

function Set-Property {
   PARAM([ref]$TheObject, $Name, $Values)
   $DObject = $TheObject.Value

   if($DebugPreference -ne "SilentlyContinue") { Write-Host ([System.Windows.Markup.XamlWriter]::Save( $DObject )) -foreground DarkMagenta }
   if($DebugPreference -ne "SilentlyContinue") { Write-Host ([System.Windows.Markup.XamlWriter]::Save( @($Values)[0] )) -foreground DarkMagenta }

   $PropertyType = $DObject.GetType().GetProperty($Name).PropertyType
   if('System.Windows.FrameworkElementFactory' -as [Type] -and $PropertyType -eq [System.Windows.FrameworkElementFactory] -and $DObject -is [System.Windows.FrameworkTemplate]) {
      if($DebugPreference -ne "SilentlyContinue") { Write-Host "Loading a FrameworkElementFactory" -foreground Green}

      # [Xml]$Template = [PoshWpf.XamlHelper]::ConvertToXaml( $DObject )
      # [Xml]$Content = [PoshWpf.XamlHelper]::ConvertToXaml( (@($Values)[0]) )
      # In .Net 3.5 the recommended way to programmatically create a template is to load XAML from a string or a memory stream using the Load method of the XamlReader class.
      [Xml]$Template = [System.Windows.Markup.XamlWriter]::Save( $DObject )
      [Xml]$Content = [System.Windows.Markup.XamlWriter]::Save( (@($Values)[0]) )

      $Template.DocumentElement.PrependChild( $Template.ImportNode($Content.DocumentElement, $true) ) | Out-Null

      $TheObject.Value = [System.Windows.Markup.XamlReader]::Parse( $Template.get_OuterXml() )
   }
   elseif('System.Windows.Data.Binding' -as [Type] -and @($Values)[0] -is [System.Windows.Data.Binding] -and !$PropertyType.IsAssignableFrom([System.Windows.Data.BindingBase])) {
      $Binding = @($Values)[0];
      if($DebugPreference -ne "SilentlyContinue") { Write-Host "$($DObject.GetType())::$Name is $PropertyType and the value is a Binding: $Binding" -fore Cyan}

      if(!$Binding.Source -and !$Binding.ElementName) {
         $Binding.Source = $DObject.DataContext
      }
      if($DependencyProperties.ContainsKey($Name)) {
         $field = @($DependencyProperties.$Name.Keys | Where { $DObject -is $_ -and $PropertyType -eq ([type]$DependencyProperties.$Name.$_.PropertyType)})[0] #  -or -like "*$Class" -and ($Param1.Value -as ([type]$_.PropertyType)
         if($field) { 
            if($DebugPreference -ne "SilentlyContinue") { Write-Host "$($field)" -fore Blue }
            if($DebugPreference -ne "SilentlyContinue") { Write-Host "Binding: ($field)::`"$($DependencyProperties.$Name.$field.Name)`" to $Binding" -fore Blue}

            $DObject.SetBinding( ([type]$field)::"$($DependencyProperties.$Name.$field.Name)", $Binding ) | Out-Null
         } else {
            throw "Couldn't figure out $( @($DependencyProperties.$Name.Keys) -join ', ' )"
         }
      } else {
         if($DebugPreference -ne "SilentlyContinue") { 
            Write-Host "But $($DObject.GetType())::${Name}Property is not a Dependency Property, so it probably can't be bound?" -fore Cyan
         }
         try {

            $DObject.SetBinding( ($DObject.GetType()::"${Name}Property"), $Binding ) | Out-Null

            if($DebugPreference -ne "SilentlyContinue") { 
               Write-Host ([System.Windows.Markup.XamlWriter]::Save( $Dobject )) -foreground yellow
            }
         } catch {
            Write-Host "Nope, was not able to set it." -fore Red
            Write-Host $_ -fore Red
            Write-Host $this -fore DarkRed
         }
      }
   }
   elseif($PropertyType -ne [Object] -and $PropertyType.IsAssignableFrom( [System.Collections.IEnumerable] ) -and ($DObject.$($Name) -eq $null)) {
      if($Values -is [System.Collections.IEnumerable]) {
         if($DebugPreference -ne "SilentlyContinue") { Write-Host "$Name is $PropertyType which is IEnumerable, and the value is too!" -fore Cyan }
         $DObject.$($Name) = $Values
      } else { 
         if($DebugPreference -ne "SilentlyContinue") { Write-Host "$Name is $PropertyType which is IEnumerable, but the value is not." -fore Cyan }
         $DObject.$($Name) = new-object "System.Collections.ObjectModel.ObservableCollection[$(@($Values)[0].GetType().FullName)]"
         $DObject.$($Name).Add($Values)
      }
   }
   elseif($DObject.$($Name) -is [System.Collections.IList]) {
      foreach ($value in @($Values)) {
         try {
            $null = $DObject.$($Name).Add($value)
         }
         catch
         {
            # Write-Host "CAUGHT array problem" -fore Red
            if($_.Exception.Message -match "Invalid cast from 'System.String' to 'System.Windows.UIElement'.") {
               $null = $DObject.$($Name).Add( (New-System.Windows.Controls.TextBlock $value) )
            } else {
               Write-Error $_.Exception
            throw
            }
         }
      }
   }
   else {
      ## If they pass an array of 1 when we only want one, we just use the first value
      if($Values -is [System.Collections.IList] -and $Values.Count -eq 1) {
         if($DebugPreference -ne "SilentlyContinue") { Write-Host "Value is an IList ($($Values.GetType().FullName))" -fore Cyan}
         if($DebugPreference -ne "SilentlyContinue") { Write-Host "But we'll just use the first ($($Values[0].GetType().FullName))" -fore Cyan}

         if($DebugPreference -ne "SilentlyContinue") { Write-Host ([System.Windows.Markup.XamlWriter]::Save( $Values[0] )) -foreground White}
         try {
            $DObject.$($Name) = $Values[0]
         }
         catch [Exception]
         {
            # Write-Host "CAUGHT collection value problem" -fore Red
            if($_.Exception.Message -match "Invalid cast from 'System.String' to 'System.Windows.UIElement'.") {
               $null = $DObject.$($Name).Add( (TextBlock $Values[0]) )
            }else { 
               throw
            }
         }
      }
      else ## If they pass an array when we only want one, we try to use it, and failing that, cast it to strings
      {
         if($DebugPreference -ne "SilentlyContinue") { Write-Host "Value is just $Values" -fore Cyan}
         try {
            $DObject.$($Name) = $Values
         } catch [Exception]
         {
            # Write-Host "CAUGHT value problem" -fore Red
            if($_.Exception.Message -match "Invalid cast from 'System.String' to 'System.Windows.UIElement'.") {
               $null = $DObject.$($Name).Add( (TextBlock $values) )
            }else { 
               throw
            }
         }
      }
   }
}

function Set-DependencyProperty {
   [CmdletBinding()]
   param(
      [Parameter(Position=0,Mandatory=$true)]
      $Property,

      [Parameter(Mandatory=$true,ValueFromPipeline=$true)]
      $Element,

      [Parameter()]
      [Switch]$Passthru
   )

   dynamicParam {
      $paramDictionary = new-object System.Management.Automation.RuntimeDefinedParameterDictionary
      $Param1 = new-object System.Management.Automation.RuntimeDefinedParameter
      $Param1.Name = "Value"
      # $Param1.Attributes.Add( (New-ParameterAttribute -Position 1) )
      $Param1.Attributes.Add( (New-Object System.Management.Automation.ParameterAttribute -Property @{ Position = 1 }) )

      if( $Property ) {
         if($Property.GetType() -eq ([System.Windows.DependencyProperty]) -or
            $Property.GetType().IsSubclassOf(([System.Windows.DependencyProperty]))) 
         {
            $Param1.ParameterType = $Property.PropertyType
         } 
         elseif($Property -is [string] -and $Property.Contains(".")) {
            $Class,$Property = $Property.Split(".")
            if($DependencyProperties.ContainsKey($Property)){
               $type = $DependencyProperties.$Property.Keys -like "*$Class"
               if($type) { 
                  $Param1.ParameterType = [type]@($DependencyProperties.$Property.$type)[0].PropertyType
               }
            }

         } elseif($DependencyProperties.ContainsKey($Property)){
            if($Element) {
               if($DependencyProperties.$Property.ContainsKey( $element.GetType().FullName )) { 
                  $Param1.ParameterType = [type]$DependencyProperties.$Property.($element.GetType().FullName).PropertyType
               }
            } else {
               $Param1.ParameterType = [type]$DependencyProperties.$Property.Values[0].PropertyType
            }
         }
         else 
         {
            $Param1.ParameterType = [PSObject]
         }
      }
      else 
      {
         $Param1.ParameterType = [PSObject]
      }
      $paramDictionary.Add("Value", $Param1)
      return $paramDictionary
   }
   process {
      trap { 
         Write-Host "ERROR Setting Dependency Property" -Fore Red
         Write-Host "Trying to set $Property to $($Param1.Value)" -Fore Red
         continue
      }
      if($Property.GetType() -eq ([System.Windows.DependencyProperty]) -or
         $Property.GetType().IsSubclassOf(([System.Windows.DependencyProperty]))
      ){
         trap { 
            Write-Host "ERROR Setting Dependency Property" -Fore Red
            Write-Host "Trying to set $($Property.FullName) to $($Param1.Value)" -Fore Red
            continue
         }
         $Element.SetValue($Property, ($Param1.Value -as $Property.PropertyType))
      } else {
         if("$Property".Contains(".")) {
            $Class,$Property = "$Property".Split(".")
         }

         if( $DependencyProperties.ContainsKey("$Property" ) ) {
            $fields = @( $DependencyProperties.$Property.Keys -like "*$Class" | ? { $Param1.Value -as ([type]$DependencyProperties.$Property.$_.PropertyType) } )
            if($fields.Count -eq 0 ) { 
               $fields = @($DependencyProperties.$Property.Keys -like "*$Class" )
            }            
            if($fields.Count) {
               $success = $false
               foreach($field in $fields) {
                  trap { 
                     Write-Host "ERROR Setting Dependency Property" -Fore Red
                     Write-Host "Trying to set $($field)::$($DependencyProperties.$Property.$field.Name) to $($Param1.Value) -as $($DependencyProperties.$Property.$field.PropertyType)" -Fore Red
                     continue
                  }
                  $Element.SetValue( ([type]$field)::"$($DependencyProperties.$Property.$field.Name)", ($Param1.Value -as ([type]$DependencyProperties.$Property.$field.PropertyType)))
                  if($?) { $success = $true; break }
               }
                
               if(!$success) { 
                  throw "food" 
               }                
            } else {
               Write-Host "Couldn't find the right property: $Class.$Property on $( $Element.GetType().Name ) of type $( $Param1.Value.GetType().FullName )" -Fore Red
            }
         }
         else {
            Write-Host "Unknown Dependency Property Key: $Property on $($Element.GetType().Name)" -Fore Red
         }
      }
    
      if( $Passthru ) { $Element }
   }
}

function Add-Struct {
   <#
      .Synopsis
         Creates Struct types from a list of types and properties
      .Description
         Add-Struct is a wrapper for Add-Type to create struct types.
      .Example
         New-Struct Song { 
         [string]$Artist
         [string]$Album
         [string]$Name
         [TimeSpan]$Length
         } -CreateConstructorFunction
      
         Description
         -----------
         Creates a "Song" type with strongly typed Artist, Album, Name, and Length properties, with a simple constructor and a constructor function
      .Example
         New-Struct @{
         >> Product  = { [string]$Name; [double]$Price; }
         >> Order    = { [Guid]$Id; [Product]$Product; [int]$Quantity }
         >> Customer = { 
         >>   [string]$FirstName
         >>   [string]$LastName
         >>   [int]$Age
         >>   [Order[]]$OrderHistory
         >> }
         >> }
         >>
      
         Description
         -----------
         To create a series of related struct types (where one type is a property of another type), you need to use the -Types hashtable parameter set.  That way, all of the types will compiled together at once, so the compiler will be able to find them all.
   #>
   [CmdletBinding(DefaultParameterSetName="Multiple")]
   param(
       # The name of the TYPE you are creating. Must be unique per PowerShell session.
       [ValidateScript({
           if($_ -notmatch '^[a-z][a-z1-9_]*$') {
               throw "'$_' is invalid. A valid name identifier must start with a letter, and contain only alpha-numeric or the underscore (_)."
           }
           return $true             
       })]
       [Parameter(Position=0, Mandatory=$true, ValueFromPipelineByPropertyName=$true, ParameterSetName = "Single")]
       [string]$Name,

       # A Scriptblock full of "[Type]$Name" definitions to show what properties you want on your Struct type
       [Parameter(Position=1, Mandatory=$true, ValueFromPipelineByPropertyName=$true, ParameterSetName = "Single")]
       [ScriptBlock]$Property,

       # A Hashtable in the form @{Name={Properties}} with multiple Names and Property Scriptblocks to define related structs (see example 2).
       [Parameter(Position=0, Mandatory=$true, ParameterSetName = "Multiple")]
       [HashTable]$Types,

       # Generate a New-StructName shortcut function for each New-Object StructName
       [Alias("CTorFunction","ConstructorFunction")]
       [Switch]$CreateConstructorFunction,

       # Output the defined type(s)
       [Switch]$PassThru
   )
   begin {
       if($PSCmdlet.ParameterSetName -eq "Multiple") {
           $Structs = foreach($key in $Types.Keys) {
               New-Object PSObject -Property @{Name=$key;Property=$Types.$key}
           }
           Write-Verbose ($Structs | Out-String)
           $Structs | New-Struct -Passthru:$Passthru -CreateConstructorFunction:$CreateConstructorFunction
       } else {
       $code = "using System;`nusing System.Collections;`nusing System.Management.Automation;`n"
       $function = ""
       }
   }
   process {
      if($PSCmdlet.ParameterSetName -ne "Multiple") {
         $parserrors = $null
         $tokens = [PSParser]::Tokenize( $Property, [ref]$parserrors ) | Where-Object { "Newline","StatementSeparator" -notcontains $_.Type }

         # CODE GENERATION MAGIKS!
         $Name = $Name.ToUpper()[0] + $Name.SubString(1)
         $ctor = @()
         $setr = @()
         $prop = @()
         $parm = @()
         $cast = @()
         $hash = @()
         $2Str = @()

         $(while($typeToken,$varToken,$tokens = $tokens) {
             if($typeToken.Type -ne "Type") {
                 throw "Error on line $($typeToken.StartLine) Column $($typeToken.Start). The Struct Properties block must contain only statements of the form: [Type]`$Name, see Get-Help New-Struct -Parameter Properties"
             } elseif($varToken.Type -ne "Variable") {
                 throw "Error on line $($varToken.StartLine) Column $($varToken.Start). The Struct Properties block must contain only statements of the form: [Type]`$Name, see Get-Help New-Struct -Parameter Properties"
             }

             $varName = $varToken.Content.ToUpper()[0] + $varToken.Content.SubString(1)
             $varNameLower = $varName.ToLower()[0] + $varName.SubString(1)
             try {
                 $typeName = Invoke-Expression "[$($typeToken.Content)].FullName"
             } catch {
                 $typeName = $typeToken.Content
             }
             
             $prop += '   public {0} {1};' -f $typeName,$varName
             $setr += '      {0} = {1};' -f $varName,$varNameLower
             $ctor += '{0} {1}' -f $typeName,$varNameLower
             $cast += '      if(input.Properties["{0}"] != null){{ output.{0} = ({1})input.Properties["{0}"].Value; }}' -f $varName,$typeName
             $hash += '      if(hash.ContainsKey("{0}")){{ output.{0} = ({1})hash["{0}"]; }}' -f $varName,$typeName
             $2Str += '"{0} = [{1}]\"" + {0}.ToString() + "\""' -f $varName, $typeName
             if($CreateConstructorFunction) {
                 $parm += '[{0}]${1}' -f $typeName,$varName
             }
         })

$code += @"
public struct $Name {
$($prop -join "`n")
   public $Name ($( $ctor -join ","))
   {
$($setr -join "`n")
   }
   public static implicit operator $Name(Hashtable hash)
   {
      $Name output = new $Name();
$($hash -join "`n")
      return output;
   }
   public static implicit operator $Name(PSObject input)
   {
      $Name output = new $Name();
$($cast -join "`n")
      return output;
   }
   
   public override string ToString()
   {
      return "@{" + $($2Str -join ' + "; " + ') + "}";
   }
}

"@

if($CreateConstructorFunction) {
$function += @"
   Function global:New-$Name {
   [CmdletBinding()]
   param(
   $( $parm -join ",`n" )
   )
   New-Object $Name -Property `$PSBoundParameters
   }

"@
}

      }
   }
   end {
      if($PSCmdlet.ParameterSetName -ne "Multiple") {
          Write-Verbose "C# Code:`n$code"
          Write-Verbose "PowerShell Code:`n$function"

          Add-Type -TypeDefinition $code -PassThru:$Passthru -ErrorAction Stop
          if($CreateConstructorFunction) {
              Invoke-Expression $function
          }
      }
   }
}

function Add-Enum {
   #.Synopsis
   #   Generates an enumerable type
   #.Description
   #   Add-Enum is a wrapper for Add-Type to create Enums that can be used as parameters for functions. It includes the ability to create Flag enums, and automatically generates integer values (optionally adding a "None" (zero) value with the name you specify).
   #.Example
   #     Add-Enum SpecialFolders Desktop Programs Personal MyDocuments
   #.Example
   #   get-content FolderPerLine.txt | New-Enum "SpecialFolders"
   [CmdletBinding(DefaultParameterSetName="Simple")]
   param (
      # The name of the enum type. 
      # Note: To avoid collisions, this type will reside in the "PowerEnums" namespace, but we'll generate an alias for it so you can use just the name.
      [Parameter(Position=0,Mandatory=$true)]
      [String]$Name,

      # The values in the enum
      [Parameter(Position=1,Mandatory=$true,ValueFromPipeline=$true,ValueFromRemainingArguments=$true)]
      [String[]]$Members,

      # Controls whether the enum is generated as a [Flags] enum (meaning that combinations of the enumerations are valid)
      [Parameter(ParameterSetName="Flags",Mandatory=$true)]
      [Switch]$Flags,
      
      # Sets the name for the "None" (zero) value in a flags enum
      [Parameter(ParameterSetName="Flags")]
      [String]$ZeroValue,
      
      # If set, the type will be output
      [Switch]$Passthru
   )
   begin {
      $AllMembers = New-Object System.Collections.Generic.List[String]
   }
   process {
      $AllMembers += $Members
   }
   end {
      $Members = foreach($m in $AllMembers -Split " ") { $m.Trim() -replace "^.", $m.Trim()[0].ToString().ToUpper() } 
      $Members = $Members | Select -Unique
      if($Flags) {
         $Value = 1
         $Members = foreach($m in $Members) {
            "$m = $Value"
            $Value += $Value
         }
         if($ZeroValue) {
            $Members = @("$ZeroValue = 0,`n") + $Members
         }
      }
      
      $Type = Add-Type -TypeDefinition @"
namespace PowerEnums {
   $(if($Flags){"[System.Flags]"})
   public enum $Name {
      $($Members -Join ",`n")
   }
}
"@ -Passthru

      if($Type) {
         Add-Accelerator $Name $Type
         
         if($Passthru) {
            $Type
         }
      }
   }
}

Add-Type -Assembly WindowsBase
function Add-ConstructorFunction {
   <#
      .Synopsis
         Add support for a new class by creating the dynamic constructor function(s).
      .Description
         Creates a New-Namespace.Type function for each type passed in, as well as a short form "Type" alias.

         Exposes all of the properties and events of the type as perameters to the function. 

         NOTE: The Type MUST have a default parameterless constructor.
      .Parameter Assembly
          The Assembly you want to generate constructors for. All public types within it will be generated if possible.
      .Parameter Type
         The type you want to create a constructor function for.  It must have a default parameterless constructor.
      .Example
         Add-ConstructorFunction System.Windows.Controls.Button

         Creates a new function for the Button control.

      .Example
         [Reflection.Assembly]::LoadWithPartialName( "PresentationFramework" ).GetTypes() | Add-ConstructorFunction

         Will create constructor functions for all the WPF components in the PresentationFramework assembly.  Note that you could also load that assembly using GetAssembly( "System.Windows.Controls.Button" ) or Load( "PresentationFramework, Version=3.0.0.0, Culture=neutral, PublicKeyToken=31bf3856ad364e35" )

      .Example
         Add-ConstructorFunction -Assembly PresentationFramework

         Will create constructor functions for all the WPF components in the PresentationFramework assembly.

      .Links 
         http://HuddledMasses.org/powerboots
      .ReturnValue
         The name(s) of the function(s) created -- so you can export them, if necessary.
      .Notes
         AUTHOR:    Joel Bennett http://HuddledMasses.org
         LASTEDIT:  2009-01-13 16:35:23
   #>
   [CmdletBinding(DefaultParameterSetName="FromType")]
   param(
      [Parameter(Position=0,ValueFromPipeline=$true,ParameterSetName="FromType",Mandatory=$true)]
      [type[]]$type,

      [Alias("FullName")]
      [Parameter(Position=0,ValueFromPipelineByPropertyName=$true,ParameterSetName="FromAssembly",Mandatory=$true)]
      [string[]]$Assembly,

      [Parameter()]
       [string]$Path = "$PSScriptRoot\Types_Generated",

      [switch]$Force,

      [switch]$ShortAliases,

      [Switch]$Quiet
   )
   begin {
      [Type[]]$Empty=@()
      if(!(Test-Path $Path)) {
         MkDir $Path
      }
      $ErrorList = @()
   }
   end {
      #Set-Content -Literal $PSScriptRoot\DependencyPropertyCache.xml -Value ([System.Windows.Markup.XamlWriter]::Save( $DependencyProperties ))
       Export-CliXml -Path $PSScriptRoot\DependencyPropertyCache.xml -InputObject $DependencyProperties
       
      if($ErrorList.Count) { Write-Warning "Some New-* functions not aliased." }
      $ErrorList | Write-Error
   }
   process {
      if($PSCmdlet.ParameterSetName -eq "FromAssembly") {
         [type[]]$type = @()
         foreach($lib in $Assembly) {
            $asm =  $null
            trap { continue }
            if(Test-Path $lib) {
               $asm =  [Reflection.Assembly]::LoadFrom( (Convert-Path (Resolve-Path $lib -EA "SilentlyContinue") -EA "SilentlyContinue") )
            }
            if(!$asm) {
               ## BUGBUG: LoadWithPartialName is "Obsolete" -- but it still works in 2.0/3.5
               $asm =  [Reflection.Assembly]::LoadWithPartialName( $lib )
            }
            if($asm) {
               $type += $asm.GetTypes() | ?{ $_.IsPublic    -and !$_.IsEnum      -and 
                                            !$_.IsAbstract  -and !$_.IsInterface -and 
                                             $_.GetConstructor( "Instance,Public", $Null, $Empty, @() )}
            } else {
               Write-Error "Can't find the assembly $lib, please check your spelling and try again"
            }
         }
      }

      foreach($T in $type) {
         $TypeName = $T.FullName
         $ScriptPath = Join-Path $Path "New-$TypeName.ps1"
         Write-Verbose $TypeName

         ## Collect all dependency properties ....
         $T.GetFields() |
            Where-Object { $_.FieldType -eq [System.Windows.DependencyProperty] } |
            ForEach-Object { 
               [string]$Field = $_.DeclaringType::"$($_.Name)".Name
               [string]$TypeName = $_.DeclaringType.FullName

               if(!$DependencyProperties.ContainsKey( $Field )) {
                  $DependencyProperties.$Field = @{}
               }

               $DependencyProperties.$Field.$TypeName = @{ 
                  Name         = [string]$_.Name
                  PropertyType = [string]$_.DeclaringType::"$($_.Name)".PropertyType.FullName
               }
            }

           if(!( Test-Path $ScriptPath ) -OR $Force) {
            $Pipelineable = @();
            ## Get (or generate) a set of parameters based on the the Type Name
            $PropertyNames = New-Object System.Text.StringBuilder "@("

            $Parameters = New-Object System.Text.StringBuilder "[CmdletBinding(DefaultParameterSetName='Default')]`nPARAM(`n"
            
            ## Add all properties
            $Properties = $T.GetProperties("Public,Instance,FlattenHierarchy") | 
               Where-Object { $_.CanWrite -Or $_.PropertyType.GetInterface([System.Collections.IList]) }
               
            $Properties = ($T.GetEvents("Public,Instance,FlattenHierarchy") + $Properties) | Sort-Object Name -Unique

            foreach ($p in $Properties) {
               $null = $PropertyNames.AppendFormat(",'{0}'",$p.Name)
               switch( $p.MemberType ) {
                  Event {
                     $null = $PropertyNames.AppendFormat(",'{0}__'",$p.Name)
                     $null = $Parameters.AppendFormat(@'
    [Parameter()]
    [PSObject]${{On_{0}}},

'@, $p.Name)
               }
               Property {
                  if($p.Name -match "^$($CodeGenContentProperties -Join '$|^')`$") {
                     $null = $Parameters.AppendFormat(@'
    [Parameter(Position=1,ValueFromPipeline=$true)]
    [Object[]]${{{0}}},

'@, $p.Name)
                     $Pipelineable += @(Add-Member -in $p.Name -Type NoteProperty -Name "IsCollection" -Value $($p.PropertyType.GetInterface([System.Collections.IList]) -ne $null) -Passthru)
                  } 
                  elseif($p.PropertyType -eq [System.Boolean]) 
                  {
                     $null = $Parameters.AppendFormat(@'
    [Parameter()]
    [Switch]${{{0}}},

'@, $p.Name)
                  }
                  else 
                  {
                     $null = $Parameters.AppendFormat(@'
    [Parameter()]
    [Object[]]${{{0}}},

'@, $p.Name)
                  }
               }
            }
         }
        $null = $Parameters.Append('    [Parameter(ValueFromRemainingArguments=$true)]
    [string[]]$DependencyProps
)')
        $null = $PropertyNames.Remove(2,1).Append(')')
            
      $collectable = [bool]$(@(foreach($p in @($Pipelineable)){$p.IsCollection}) -contains $true)
      $ofs = "`n";

$function = $(
"
if(!( '$TypeName' -as [Type] )) {
$(
   if( $T.Assembly.GlobalAssemblyCache ) {
"  `$null = [Reflection.Assembly]::Load( '$($T.Assembly.FullName)' ) "
   } else {
"  `$null = [Reflection.Assembly]::LoadFrom( '$($T.Assembly.Location)' ) "
   }
)
}
## if(`$ExecutionContext.SessionState.Module.Guid -ne (Get-ReflectionModule).Guid) {
##     Write-Warning `"$($T.Name) not invoked in ReflectionModule context. Attempting to reinvoke.`"
##    # `$scriptParam = `$PSBoundParameters
##    # return iex `"& (Get-ReflectionModule) '`$(`$MyInvocation.MyCommand.Path)' ```@PSBoundParameters`"
## }
Write-Verbose ""$($T.Name) in module `$(`$executioncontext.sessionstate.module) context!""

function New-$TypeName {
<#
.Synopsis
   Create a new $($T.Name) object
.Description
   Generates a new $TypeName object, and allows setting all of it's properties.
   (From the $($T.Assembly.GetName().Name) assembly v$($T.Assembly.GetName().Version))
.Notes
 GENERATOR : $((Get-ReflectionModule).Name) v$((Get-ReflectionModule).Version) by Joel Bennett http://HuddledMasses.org
 GENERATED : $(Get-Date)
 ASSEMBLY  : $($T.Assembly.FullName)
 FULLPATH  : $($T.Assembly.Location)
#>
 
$Parameters
BEGIN {
   `$DObject = New-Object $TypeName
   `$All = $PropertyNames
}
PROCESS {
"
if(!$collectable) {
"
   # The content of $TypeName is not a collection
   # So if we're in a pipeline, make a new $($T.Name) each time
   if(`$_) { 
      `$DObject = New-Object $TypeName
   }
"
}
@'
foreach($key in @($PSBoundParameters.Keys) | where { $PSBoundParameters[$_] -is [ScriptBlock] }) {
   $PSBoundParameters[$key] = $PSBoundParameters[$key].GetNewClosure()
}
Set-ObjectProperties @($PSBoundParameters.GetEnumerator() | Where { [Array]::BinarySearch($All,($_.Key -replace "^On_(.*)",'$1__')) -ge 0 } ) ([ref]$DObject)
'@

if(!$collectable) {
@'
   Microsoft.PowerShell.Utility\Write-Output $DObject
} #Process
'@
   } else {
@'
} #Process
END {
   Microsoft.PowerShell.Utility\Write-Output $DObject
}
'@
   }
@"
}
## New-$TypeName `@PSBoundParameters
"@
)

            Set-Content -Path $ScriptPath -Value $Function
         }

         # Note: set the aliases global for now, because it's too late to export them
           # E.g.: New-Button = New-System.Windows.Controls.Button
           Set-Alias -Name "New-$($T.Name)" "New-$TypeName" -ErrorAction SilentlyContinue -ErrorVariable +ErrorList -Scope Global -Passthru:(!$Quiet)
           if($ShortAliases) {
           # E.g.: Button = New-System.Windows.Controls.Button
               Set-Alias -Name $T.Name "New-$TypeName" -ErrorAction SilentlyContinue -ErrorVariable +ErrorList -Scope Global -Passthru:(!$Quiet)
           }
           
         New-AutoLoad -Name $ScriptPath -Alias "New-$TypeName"
      }
   }#PROCESS
}

function Import-ConstructorFunctions {
   #.Synopsis
   #  Autoload pre-generated constructor functions and generate aliases for them.
   #.Description
   #  Parses the New-* scripts in the specified path, and uses the Autoload module to pre-load them as commands and set up aliases for them, without parsing them into memory.
   #.Parameter Path
   #  The path to a folder with functions to preload
   param(
      [Parameter()]
      [Alias("PSPath")]
       [string[]]$Path = "$PSScriptRoot\Types_Generated"
   )
   end {
       $Paths = $(foreach($p in $Path) { Join-Path $p "New-*.ps1" })
       Write-Verbose "Importing Constructors from: `n`t$($Paths -join "`n`t")"

       foreach($script in Get-ChildItem $Paths -ErrorAction 0) {
           $TypeName = $script.Name -replace 'New-(.*).ps1','$1'
         $ShortName = ($TypeName -split '\.')[-1]
         Write-Verbose "Importing constructor for type: $TypeName ($ShortName)"
           
         # Note: set the aliases global for now, because it's too late to export them
           # E.g.: New-Button = New-System.Windows.Controls.Button
           Set-Alias -Name "New-$ShortName" "New-$TypeName" -ErrorAction SilentlyContinue -ErrorVariable +ErrorList -Scope Global -Passthru:(!$Quiet)
           if($ShortAliases) {
           # E.g.: Button = New-System.Windows.Controls.Button
               Set-Alias -Name $ShortName "New-$TypeName" -ErrorAction SilentlyContinue -ErrorVariable +ErrorList -Scope Global -Passthru:(!$Quiet)
           }

           New-Autoload -Name $Script.FullName -Alias "New-$TypeName"
           # Write-Host -fore yellow $(Get-Command "New-$TypeName" | Out-String)
           Get-Command "New-$TypeName"
       }
   }
}

function New-ModuleManifestFromSnapin {
   #.Parameter Snapin
   #  The full path to where the snapin .dll is
   #.Parameter OutputPath
   #  Force the module manifest(s) to output in a different location than where the snapin .dll is
   #.Parameter ModuleName
   #  Override the snapin name(s) for the module manifest
   #.Parameter Author
   #  Overrides the Company Name from the manifest when generating the module's "Author" comment
   #.Parameter Passthru
   #  Returns the ModuleManifest (same as -Passthru on New-ModuleManifest)
   #.Example
   #  New-ModuleManifestFromSnapin ".\Quest Software\Management Shell for AD" -ModuleName QAD
   #
   #  Description
   #  -----------
   #  Generates a new module manifest file: QAD.psd1 in the folder next to the Quest.ActiveRoles.ArsPowerShellSnapIn.dll
   #.Example
   #  New-ModuleManifestFromSnapin "C:\Program Files (x86)\Microsoft SQL Server\100\Tools\Binn\" -Output $pwd
   #
   #  Description
   #  -----------
   #  Generates module manifest files for the SqlServer PSSnapins and stores them in the current folder
   param( 
      [Parameter(Mandatory=$true, Position="0", ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
      [Alias("FullName")]
      [String[]]$Snapin,

      [Parameter()]
      $OutputPath,

      [Parameter()]
      $ModuleName,

      [Parameter()]
      [String]$Author,

      [Switch]$Passthru
   ) 

   # $SnapinPath = $(Get-ChildItem $SnapinPath -Filter *.dll)
   $EAP = $ErrorActionPreference
   $ErrorActionPreference = "SilentlyContinue"
   Add-Assembly $Snapin 
   $ErrorActionPreference = $EAP

   $SnapinTypes = Get-Assembly $Snapin | Get-Type -BaseType System.Management.Automation.PSSnapIn, System.Management.Automation.CustomPSSnapIn -WarningAction SilentlyContinue


   foreach($SnapinType in $SnapinTypes) {
      $Installer = New-Object $SnapinType

      if(!$PSBoundParameters.ContainsKey("OutputPath")) {
         $OutputPath = (Split-Path $SnapinType.Assembly.Location)
      }

      if(!$PSBoundParameters.ContainsKey("ModuleName")) {
         $ModuleName = $Installer.Vendor
      }
      if(!$PSBoundParameters.ContainsKey("Author")) {
         $Author = $Installer.Name
      }
      $ManifestPath = (Join-Path $OutputPath "$ModuleName.psd1")

      Write-Verbose "Creating Module Manifest: $ManifestPath"

      $RequiredAssemblies = @( $SnapinType.Assembly.GetReferencedAssemblies() | Get-Assembly | Where-Object { (Split-Path $_.Location) -eq (Split-Path $SnapinType.Assembly.Location) } | Select-Object -Expand Location | Resolve-Path -ErrorAction Continue)

      # New-ModuleManifest has a bad bug -- it makes paths relative to the current location (and it does it wrong).
      Push-Location $OutputPath

      if($Installer -is [System.Management.Automation.CustomPSSnapIn]) {
         $Cmdlets = $Installer.Cmdlets | Select-Object -Expand Name
         $Types = $Installer.Types | Select-Object -Expand FileName | %{ $path = Resolve-Path $_ -ErrorAction Continue; if(!$path){ $_ } else { $path } }
         $Formats = $Installer.Formats | Select-Object -Expand FileName | %{ $path = Resolve-Path $_ -ErrorAction Continue; if(!$path){ $_ } else { $path } }
      } else {
         $Types = $Installer.Types |  %{ $path = Resolve-Path $_ -ErrorAction Continue; if(!$path){ $_ } else { $path } }
         $Formats = $Installer.Formats |  %{ $path = Resolve-Path $_ -ErrorAction Continue; if(!$path){ $_ } else { $path } }
      }
      if(!$Cmdlets) { $Cmdlets = "*" }
      if(!$Types) { $Types = @() }
      if(!$Formats) { $Formats = @() }

      New-ModuleManifest -Path $ManifestPath -Author $Author -Company $Installer.Vendor -Description $Installer.Description `
                         -ModuleToProcess $SnapinType.Assembly.Location -Types $Types -Formats $Formats -Cmdlets $Cmdlets `
                         -RequiredAssemblies $RequiredAssemblies  -Passthru:$Passthru `
                         -NestedModules @() -Copyright $Installer.Vendor -FileList @()
      Pop-Location
   }
}


# Utility to throw an errorrecord
function ThrowError {
    <#
        .Synopsis
            Throw a terminating error
    #>
    param
    (        
        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [System.Management.Automation.PSCmdlet]
        $Cmdlet = $((Get-Variable -Scope 1 PSCmdlet).Value),

        [Parameter(Mandatory = $true, ParameterSetName="ExistingException", Position=1, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
        [Parameter(ParameterSetName="NewException")]
        [ValidateNotNullOrEmpty()]
        [System.Exception]
        $Exception,

        [Parameter(ParameterSetName="NewException", Position=2)]
        [ValidateNotNullOrEmpty()]
        [System.String]        
        $ExceptionType="System.Management.Automation.RuntimeException",

        [Parameter(Mandatory = $true, ParameterSetName="NewException", Position=3)]
        [ValidateNotNullOrEmpty()]
        [System.String]
        $Message,
        
        [Parameter(Mandatory = $false)]
        [System.Object]
        $TargetObject,
        
        [Parameter(Mandatory = $true, ParameterSetName="ExistingException", Position=10)]
        [Parameter(Mandatory = $true, ParameterSetName="NewException", Position=10)]
        [ValidateNotNullOrEmpty()]
        [System.String]
        $ErrorId,

        [Parameter(Mandatory = $true, ParameterSetName="ExistingException", Position=11)]
        [Parameter(Mandatory = $true, ParameterSetName="NewException", Position=11)]
        [ValidateNotNull()]
        [System.Management.Automation.ErrorCategory]
        $Category,

        [Parameter(Mandatory = $true, ParameterSetName="Rethrow", Position=1)]
        [System.Management.Automation.ErrorRecord]$ErrorRecord
    ) 
    process {
        if(!$ErrorRecord) {
            if($PSCmdlet.ParameterSetName -eq "NewException") {
                if($Exception) {
                    $Exception = New-Object $ExceptionType $Message, $Exception
                } else {
                    $Exception = New-Object $ExceptionType $Message
                }
            }
            $errorRecord = New-Object System.Management.Automation.ErrorRecord $Exception, $ErrorId, $Category, $TargetObject
        }
        $Cmdlet.ThrowTerminatingError($errorRecord)
    }
}

# Utility to throw an errorrecord
function WriteError {
    <#
        .Synopsis
            Make writing proper errors easier
        .Example
            WriteError -ExceptionType System.Management.Automation.ItemNotFoundException `
                       -Message "Can't find settings file $Path" `
                       -ErrorId "PathNotFound,Metadata\Import-Metadata" `
                       -Category "ObjectNotFound"
    #>
    param
    (        
        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [System.Management.Automation.PSCmdlet]
        $Cmdlet = $((Get-Variable -Scope 1 PSCmdlet).Value),

        [Parameter(Mandatory = $true, ParameterSetName="ExistingException", Position=1, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
        [Parameter(ParameterSetName="NewException")]
        [ValidateNotNullOrEmpty()]
        [System.Exception]
        $Exception,

        [Parameter(ParameterSetName="NewException", Position=2)]
        [ValidateNotNullOrEmpty()]
        [System.String]        
        $ExceptionType="System.Management.Automation.RuntimeException",

        [Parameter(Mandatory = $true, ParameterSetName="NewException", Position=3)]
        [ValidateNotNullOrEmpty()]
        [System.String]
        $Message,
        
        [Parameter(Mandatory = $false)]
        [System.Object]
        $TargetObject,
        
        [Parameter(Mandatory = $true, Position=10)]
        [ValidateNotNullOrEmpty()]
        [System.String]
        $ErrorId,

        [Parameter(Mandatory = $true, Position=11)]
        [ValidateNotNull()]
        [System.Management.Automation.ErrorCategory]
        $Category,

        [Parameter(Mandatory = $true, ParameterSetName="Rethrow", Position=1)]
        [System.Management.Automation.ErrorRecord]$ErrorRecord
    ) 
    process {
        if(!$ErrorRecord) {
            if($PSCmdlet.ParameterSetName -eq "NewException") {
                if($Exception) {
                    $Exception = New-Object $ExceptionType $Message, $Exception
                } else {
                    $Exception = New-Object $ExceptionType $Message
                }
            }
            $errorRecord = New-Object System.Management.Automation.ErrorRecord $Exception, $ErrorId, $Category, $TargetObject
        }
        $Cmdlet.WriteError($errorRecord)
    }
}



Set-Alias aasm Add-Assembly
Set-Alias gt Get-Type
Set-Alias gasm Get-Assembly
Set-Alias gctor Get-Constructor

Update-TypeData -MemberType ScriptProperty -MemberName TokenType -Value { $this.GetType().FullName } -TypeName System.Management.Automation.Language.Ast -Force

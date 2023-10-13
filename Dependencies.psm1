function GetRequiredModule {
    [OutputType([System.Collections.Generic.List[System.Management.Automation.PSModuleInfo]])]
    [CmdletBinding()]
    param([string[]]$Name)
    Write-Debug "ENTER: GetRequiredModule $Name"
    $Modules = [System.Collections.Generic.List[System.Management.Automation.PSModuleInfo]]::new()
    do {
        Write-Debug "TRACE GetRequiredModule: GET: $Name"
        $Modules.AddRange([System.Management.Automation.PSModuleInfo[]]@(
                Get-Module $Name -ListAvailable -ErrorAction Stop | Sort-Object Name, Version | Sort-Object Name -Unique
            ))
        [string[]]$Names = @($Modules.Name)
        Write-Debug "TRACE GetRequiredModule: FOUND: $Names"
        $Name = $Modules.RequiredModules.Name.Where{ $_ -notin $Names }
    } while ($Name)
    $Modules
}

function Optimize-ModuleList {
    <#
        .SYNOPSIS
            Sorts Modules based on dependency, so modules always appear after their RequiredModules
        .NOTES
            From https://gist.github.com/Jaykul/304e7874d629ef4848c9acd0cfd550d0
    #>
    [CmdletBinding(DefaultParameterSetName = "ByName")]
    param(
        [Parameter(Mandatory, Position = 0, ParameterSetName = "ByName")]
        [string[]]$Name,

        [Parameter(Mandatory, Position = 0, ValueFromPipeline, ParameterSetName = "ModuleInfo")]
        [System.Management.Automation.PSModuleInfo[]]$Module,

        [Parameter(Mandatory, ParameterSetName = "RequiredModulesPath")]
        [string]$RequiredModulesPath
    )
    begin {
        Write-Debug "ENTER: Optimize-ModuleList $Name$Module"
        $Modules = [System.Collections.Generic.List[System.Management.Automation.PSModuleInfo]]::new()
    }
    process {
        if ($RequiredModulesPath) {
            Write-Debug "TRACE Optimize-ModuleList: Import-Metadata $RequiredModulesPath"
            Write-Progress "Looking up initial module info" "Loading RequiredModulesPath"
            $Metadata = Import-Metadata $RequiredModulesPath
            $Name = @($Metadata.Keys)
        }
        if ($Name) {
            Write-Debug "TRACE Optimize-ModuleList: Get-Module $($Name)"
            Write-Progress "Looking up initial module info" "Getting module information from disk (may take a minute)"
            $Module = GetRequiredModule $Name
        }
        $Modules.AddRange($Module)
    }
    end {
        Write-Progress "Tracing Dependencies" "Calling Trace-RequiredModule for $($Modules.Count) modules"
        Write-Debug "TRACE Optimize-ModuleList: Call Trace-RequiredModule with $($Modules.Count) modules"
        $Ordered = $Modules | Resolve-DependencyOrder -Key { $_.Name } -DependsOn { $_.RequiredModules.Name }
        Write-Progress "Tracing Dependencies" "Ordering results"
        if (!$Metadata) {
            $Ordered
        } else {
            $RequiredModules = [Ordered]@{}
            # Output for RequiredModules ...
            foreach ($ModuleName in $Ordered.Name) {
                $VersionRange = $Metadata[$ModuleName]
                if (!$VersionRange) {
                    Write-Debug "TRACE Optimize-ModuleList: Fabricating version range for '$ModuleName'"
                    # This works even if there's no match, or the version is just "2.0"
                    $Version = $Ordered.Where({ $_.Name -eq $ModuleName }, "First", 1).Version
                    $VersionRange = "[{0}.{1}.{2},]" -f [Math]::Max(0, $Version.Major), [Math]::Max(0, $Version.Minor), [Math]::Max(0, $Version.Build)
                }
                $RequiredModules[$ModuleName] = $VersionRange
            }
            Export-Metadata -InputObject $RequiredModules -Path $RequiredModulesPath
        }
        Write-Progress "Tracing Dependencies" -Completed
        Write-Debug "EXIT: Optimize-ModuleList $Name$Module"
    }
}

filter PushRequiredModule {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 1, ValueFromPipeline, ParameterSetName = "ModuleInfo")]
        [System.Management.Automation.PSModuleInfo]$RequiredModules,

        $Depth
    )
    $__Trace_RequiredModule_Cache[$RequiredModules.Name].Depth = $Depth
    $__Trace_RequiredModule_Cache[$RequiredModules.Name]
    $RequiredModules.RequiredModules | PushRequiredModule -Depth ($Depth + 1)
}

function Trace-RequiredModule {
    <#
        .SYNOPSIS
            Traces RequiredModules recursively
        .NOTES
            From https://gist.github.com/Jaykul/304e7874d629ef4848c9acd0cfd550d0
    #>
    [CmdletBinding(DefaultParameterSetName = "ByName")]
    param(
        [Parameter(Mandatory, Position = 0, ParameterSetName = "ByName")]
        [string[]]$Name,

        [Parameter(Mandatory, Position = 0, ValueFromPipeline, ParameterSetName = "ModuleInfo")]
        [System.Management.Automation.PSModuleInfo[]]$Module,

        $Depth = 0,

        $ChildIndicator = $(([char[]]@(0x251c, 0x2500, " ")) -join "")
    )
    begin {
        # Because we recurse, we need to be sure to only create this once
        if (!(Test-Path Variable:__Trace_RequiredModule_Cache)) {
            $__Trace_RequiredModule_Cache = [System.Collections.Generic.Dictionary[string, System.Management.Automation.PSModuleInfo]]::new()
        }
    }
    process {
        Write-Debug "ENTER: Trace-RequiredModule $Name$Module"
        if ($Name) {
            Write-Debug "TRACE Trace-RequiredModule: Get-Module $($Name)"
            Write-Progress "Tracing Dependencies" "Getting initial module information from disk (may take a minute)"
            $Module = Get-Module $Name -ListAvailable -ErrorAction Stop | Sort-Object Name, Version | Sort-Object Name -Unique
        }

        foreach ($M in $Module) {
            if (!$__Trace_RequiredModule_Cache.ContainsKey($M.Name)) {
                Write-Progress "Tracing Dependencies" "Tracing module $($M.Name)"
                Write-Debug "TRACE Trace-RequiredModule: Adding '$($M.Name)' to list (depth $Depth), with its $($m.RequiredModules.Count) dependencies"
                # New module we haven't seen, update object and recurse
                $m.PSTypeNames.Insert(0, "TreeView")
                $m | Add-Member NoteProperty Depth $Depth
                # Making this a script property means we only have to update Depth to get it to display right
                $m | Add-Member ScriptProperty TreeName ({ "$("   " * [Math]::Max(($this.Depth - 1), 0))$(if ($this.Depth -ne 0) { $ChildIndicator })$($this.Name)" }.GetNewClosure())
                $__Trace_RequiredModule_Cache.Add($m.Name, $m)
                $m # .Clone()

                foreach ($rm in @($m.RequiredModules)) {
                    Trace-RequiredModule -Depth ($Depth + 1) -Module $(
                        if ($__Trace_RequiredModule_Cache.ContainsKey($rm.Name)) {
                            $__Trace_RequiredModule_Cache[$rm.Name]
                        } else {
                            Get-Module $rm.Name -ListAvailable | Select-Object -First 1
                        }
                    )
                }
                # Module's already tracked, increase depth if necessary
                Write-Progress "Tracing Dependencies" -Completed
            } elseif ($Depth -gt $__Trace_RequiredModule_Cache[$m.Name].Depth) {
                Write-Debug "TRACE Trace-RequiredModule: Pushing '$($M.Name)' deeper (to $Depth), with its $($m.RequiredModules.Count) dependencies"
                $m | PushRequiredModule -Depth $Depth
            }
        }
    }
    end {
        # $__Trace_RequiredModule_Cache.Values
        Write-Debug "EXIT: Trace-RequiredModule $Name$Module"
    }
}
Update-TypeData -TypeName TreeView -DefaultDisplayProperty TreeName -DefaultDisplayPropertySet TreeName, Version, ExportedCommands -Force

function Resolve-Command {
    <#
    .SYNOPSIS
        Resolves aliases to commands (recursively)
    .NOTES
        From https://gist.github.com/Jaykul/f10337411d545b15a84b06c6294b825e
    #>
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline, ValueFromPipelineByPropertyName, Mandatory)]
        [string]$Name
    )
    process {
        Write-Progress "Resolving Command $Name"
        Write-Debug "  ENTER: Resolve-Command $Name"
        $Trace = ""
        try {
            while (($command = Get-Command $Name -ErrorAction Stop).CommandType -eq "Alias") {
                $Name = $command.Definition
                $Trace = "$Trace --> '$Name'"
            }
            $command
        } catch {
            Write-Error "Command not resolved '$($PSBoundParameters['Name'])'$Trace. Command '$($_.TargetObject)' not found." -Category InvalidData -TargetObject $Command
        }
        Write-Debug "  EXIT: Resolve-Command $Name"
    }
}

function Invoke-Parser {
    <#
    .SYNOPSIS
        Invokes [Parser]::Parse* and returns the AST, Tokens, and Errors
    .NOTES
        From https://gist.github.com/Jaykul/f10337411d545b15a84b06c6294b825e
    #>
    param(
        # The script, function, or file path to parse
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias("Path", "PSPath", "ScriptBlock")]
        $Script
    )
    process {
        Write-Progress "Parsing $Script"
        Write-Debug "ENTER: Invoke-Parser $Script"
        $ParseErrors = $null
        $Tokens = $null
        if ($Script | Test-Path -ErrorAction SilentlyContinue) {
            Write-Debug "      Parse $Script as Path"
            $AST = [System.Management.Automation.Language.Parser]::ParseFile(($Script | Convert-Path), [ref]$Tokens, [ref]$ParseErrors)
        } elseif ($Script -is [System.Management.Automation.FunctionInfo]) {
            Write-Debug "      Parse $Script as Function"
            $String = "function $($Script.Name) { $($Script.Definition) }"
            $AST = [System.Management.Automation.Language.Parser]::ParseInput($String, [ref]$Tokens, [ref]$ParseErrors)
        } else {
            Write-Debug "      Parse $Script as String" # Or Scriptblock ;)
            $AST = [System.Management.Automation.Language.Parser]::ParseInput([String]$Script, [ref]$Tokens, [ref]$ParseErrors)
        }

        Write-Debug "EXIT: Invoke-Parser $Script"
        [PSCustomObject]@{
            PSTypeName  = "System.Management.Automation.Language.ParseResults"
            ParseErrors = $ParseErrors
            Tokens      = $Tokens
            AST         = $AST
        }
    }
}

function Expand-Command {
    <#
    .SYNOPSIS
        Takes a single script command and returns all the commands it calls
    .NOTES
        From https://gist.github.com/Jaykul/f10337411d545b15a84b06c6294b825e
    #>
    [CmdletBinding()]
    param([string[]]$Command)
    Write-Debug "ENTER: Expand-Command $Command"
    Write-Progress "Searching Dependencies in $Command"

    $Command | Resolve-Command | Invoke-Parser | & {
        process {
            Write-Progress "Recursively searching for commands..."
            $_.AST.FindAll({ param($Ast) $Ast -is [System.Management.Automation.Language.CommandAst] }, $true)
        }
    } |
        # Errors will appear for commands you don't have available
        Resolve-Command -Name { $_.CommandElements[0].Value } -ErrorAction SilentlyContinue -ErrorVariable +global:__missing_commands_in_trace

    Write-Debug "EXIT: Expand-Command $Command"
}

function Trace-CommandDependence {
    <#
    .SYNOPSIS
        Takes a script command and returns all the commands it calls, recursively
    .NOTES
        From https://gist.github.com/Jaykul/f10337411d545b15a84b06c6294b825e
    #>
    [CmdletBinding()]
    param(
        # The path to a script or name of a command
        [Parameter(Mandatory)]
        [string[]]$Command,

        # If you want to trace private functions from a module, make sure it's imported, and pass the ModuleInfo here
        [System.Management.Automation.PSModuleInfo]$ModuleScope = $(
            Get-Module $Command -ListAvailable -ErrorAction SilentlyContinue | Get-Module -ErrorAction SilentlyContinue
        ),

        # If set, traces the dependencies of dependencies recursively (but never traces the same dependency twice)
        [switch]$Recurse,

        # If set, outputs the dependencies grouped by their source (module)
        [switch]$ShowModule
    )

    $ExpandCommand = @(Get-Command Expand-Command)[0].ScriptBlock
    # These are the commands we still need to scan.
    # In recurse mode, we add new commands we find to the end of this...
    $Commands = @( $Command | Resolve-Command )
    # Once we've scanned them, put them here to avoid scanning them again
    $ScannedCommands = @()
    # This HAS to be global, because we're going to use it INSIDE many modules ...
    $global:__missing_commands_in_trace = @()

    do {
        $Pass = $Commands | Where-Object {
            $_ -notin $ScannedCommands -and
            $_ -isnot [System.Management.Automation.CmdletInfo] -and
            $_ -isnot [System.Management.Automation.ApplicationInfo] }
        $Commands += @(
            foreach ($Command in $Pass) {
                Write-Progress "Parsing $Command"
                if ($Command.Module) {
                    Write-Debug "Parsing $Command in module $($Command.Module)"
                    & $Command.Module $ExpandCommand $Command
                } else {
                    Write-Debug "Parsing $Command"
                    Expand-Command $Command
                }
                $ScannedCommands += $Command
            }
        )
    } while ($Recurse -and $Pass)

    if ($ShowModule) {
        $Commands |
            Sort-Object Source, Name -Unique |
            Group-Object Source |
            Select-Object @{N = "Module"; e = { $_.Name } }, @{N = "Used Commands"; E = { $_.Group } }
    } else {
        $Commands | Select-Object -Unique
    }

    if ($__missing_commands_in_trace) {
        Write-Warning "Missing source for some (probably internal) commands: $(($__missing_commands_in_trace | Select-Object -Expand TargetObject -Unique -ErrorAction SilentlyContinue) -join ', ')"
        Write-Verbose ($__missing_commands_in_trace | Sort-Object -Unique | Out-String)
    }
}

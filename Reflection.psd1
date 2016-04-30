﻿@{

# Script module or binary module file associated with this manifest.
RootModule = 'Reflection.psm1'

# Version number of this module.
ModuleVersion = '4.9'

# ID used to uniquely identify this module
GUID = '64b5f609-970f-4e65-b02f-93ccf3e60cbb'

# Author of this module
Author = 'Joel Bennett'

# Company or vendor of this module
CompanyName = 'http://HuddledMasses.org'

# Copyright statement for this module
Copyright = 'Copyright (c) 2008-2014 by Joel Bennett, released under the Ms-PL'

# Description of the functionality provided by this module
Description = 'A .Net Framework Interaction Module for PowerShell'

# Minimum version of the Windows PowerShell engine required by this module
PowerShellVersion = '2.0'

# Name of the Windows PowerShell host required by this module
# PowerShellHostName = ''

# Minimum version of the Windows PowerShell host required by this module
# PowerShellHostVersion = ''

# Minimum version of Microsoft .NET Framework required by this module
# DotNetFrameworkVersion = ''

# Minimum version of the common language runtime (CLR) required by this module
CLRVersion = '2.0'

# Processor architecture (None, X86, Amd64) required by this module
ProcessorArchitecture = 'None'

# Modules that must be imported into the global environment prior to importing this module
RequiredModules = @(@{ModuleName = 'Autoload'; GUID = '4001ca5f-8b94-41a1-9229-4db6afa6c6ea'; ModuleVersion = '4.0'; })

# Assemblies that must be loaded prior to importing this module
# RequiredAssemblies = @()

# Script files (.ps1) that are run in the caller's environment prior to importing this module.
ScriptsToProcess = @("Get-ParameterValue.ps1")

# Type files (.ps1xml) to be loaded when importing this module
# TypesToProcess = @()

# Format files (.ps1xml) to be loaded when importing this module
# FormatsToProcess = @()

# Modules to import as nested modules of the module specified in RootModule/ModuleToProcess
# NestedModules = @()

# Functions to export from this module
FunctionsToExport = 'Add-Accelerator', 'Add-Assembly', 'Add-ConstructorFunction', 
               'Add-Struct', 'Add-Enum', 'Get-Accelerator', 'Get-Argument', 
               'Get-Assembly', 'Get-Constructor', 'Get-ExtensionMethod', 'Import-ExtensionMethod',
               'Get-MemberSignature', 'Get-Method', 'Get-ReflectionModule', 'Get-Type', 
               'Import-ConstructorFunctions', 'Import-Namespace', 'Invoke-Generic', 
               'Invoke-Member', 'New-ModuleManifestFromSnapin', 'Read-Choice', 
               'Remove-Accelerator', 'Set-DependencyProperty', 
               'Set-ObjectProperties', 'Set-Property', 'Test-AssignableToGeneric', 
               'Update-PSBoundParameters', 'Test-RestrictedLanguage', 
               'Get-ParseResults', 'Find-Token'

# Cmdlets to export from this module
CmdletsToExport = '*'

# Variables to export from this module
VariablesToExport = '*'

# Aliases to export from this module
AliasesToExport = '*'

# DSC resources to export from this module
# DscResourcesToExport = @()

# List of all modules packaged with this module
# ModuleList = @()

# List of all files packaged with this module
FileList = 'Reflection.psm1', 'Reflection.psd1', 'license.txt'

# Private data to pass to the module specified in RootModule/ModuleToProcess. This may also contain a PSData hashtable with additional module metadata used by PowerShell.
PrivateData = @{

    PSData = @{

        # Tags applied to this module. These help with module discovery in online galleries.
        Tags = @("Reflection", "CodeGen", "Accelerator", "CliXml")

        # A URL to the license for this module.
        LicenseUri = 'https://github.com/Jaykul/Reflection/blob/master/license.txt'

        # A URL to the main website for this project.
        ProjectUri = 'https://github.com/Jaykul/Reflection'
        # ReleaseNotes of this module
        ReleaseNotes = 'https://github.com/Jaykul/Reflection/blob/master/ReleaseNotes.md'

    } # End of PSData hashtable

} # End of PrivateData hashtable

# HelpInfo URI of this module
# HelpInfoURI = ''

# Default prefix for commands exported from this module. Override the default prefix using Import-Module -Prefix.
# DefaultCommandPrefix = ''

}

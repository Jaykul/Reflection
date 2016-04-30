
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

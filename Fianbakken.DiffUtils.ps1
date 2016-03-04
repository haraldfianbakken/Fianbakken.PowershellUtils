<#
.Synopsis
   Merge 2 json structures
.DESCRIPTION
   Long description
.EXAMPLE
   Example of how to use this cmdlet
.EXAMPLE
   Another example of how to use this cmdlet
#>
function Diff-Json{
    [CmdletBinding()]
    [Alias()]
    [OutputType([json])]
    Param
    (
        # Param1 help description
        [Parameter(Mandatory=$true,
                   ValueFromPipelineByPropertyName=$true,
                   Position=0)]
        [Json]
        $master,
        [Parameter(Mandatory=$true,
            ValueFromPipelineByPropertyName=$true,
            Position=1)]
        [Json]
        $merge,
        [switch]
        $removeProperties
        
    )    
    Process
    {
    }
    
}

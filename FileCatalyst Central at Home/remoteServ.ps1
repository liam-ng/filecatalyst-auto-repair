param (
    [string[]]$Computers
)

$Computers = $Computers -split ","

Try {
    Get-Service -ComputerName $Computers -Name FileCatalystHotFolder | select Status
} catch {
    "Get-Service Failed."
}
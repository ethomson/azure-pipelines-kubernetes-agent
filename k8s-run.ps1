$Default_Image="ethomson/azure-pipelines-agent-win32:latest"

Set-StrictMode -Version Latest

$ErrorActionPreference = "Stop"
$PSDefaultParameterValues['*:ErrorAction'] = 'Stop'

if (-not $Env:AZURE_PIPELINES_URL -or -not $Env:AZURE_PIPELINES_POOL -or -not $Env:AZURE_PIPELINES_PAT) {
	[System.Console]::Error.WriteLine("Configuration is incomplete; the following environment variables must be set:")
	[System.Console]::Error.WriteLine(" AZURE_PIPELINES_URL to the URL of your Azure DevOps organization")
	[System.Console]::Error.WriteLine(" AZURE_PIPELINES_POOL to the name of the pool that this agent will belong")
	[System.Console]::Error.WriteLine(" AZURE_PIPELINES_PAT to the PAT to authenticate to Azure DevOps")
	exit 1
}

function CheckLastExitCode {
	if ($LastExitCode -ne 0) { Write-Error "Command failed with exit code ${LastExitCode}" }
}

$Agent_Guid=New-Guid
if ($Env:AZURE_PIPELINES_AGENT_NAME) { $Agent_Name=$Env:AZURE_PIPELINES_AGENT_NAME } else { $Agent_Name="$(hostname)_${Agent_Guid}" }
if ($Env:IMAGE) { $Agent_Image=$Env:IMAGE } else { $Agent_Image=$Default_Image }

# Register an agent that will remain idle; we always need an agent in the
# pool and since our container agents create and delete themselves, there's
# a possibility of the pool existing with no agents in it, and jobs will
# fail to queue in this case.  This idle agent will prevent that.

Write-Host ""
Write-Host ":: Setting up reserved agent (${Env:AZURE_PIPELINES_POOL}_reserved)..."
Copy-Item C:\Data\Agent C:\Data\Reserved_Agent -Recurse
C:\Data\Reserved_Agent\config.cmd --unattended --url "${Env:AZURE_PIPELINES_URL}" --pool "${Env:AZURE_PIPELINES_POOL}" --agent "${Env:AZURE_PIPELINES_POOL}_reserved" --auth pat --token "${Env:AZURE_PIPELINES_PAT}" --replace
CheckLastExitCode

# Set up the actual runner that will do work.
Write-Host ""
Write-Host ":: Setting up runner agent (${Agent_Name})..."
if (Test-Path C:\Tmp\Agent) {
	if (Test-Path C:\Tmp\Agent\.agent) { attrib -h C:\Tmp\Agent\.agent }
	if (Test-Path C:\Tmp\Agent\.credentials) { attrib -h C:\Tmp\Agent\.credentials }
	if (Test-Path C:\Tmp\Agent\.credentials_rsaparams) { attrib -h C:\Tmp\Agent\.credentials_rsaparams }
	Remove-Item -Path C:\Tmp\Agent -Recurse
}
Copy-Item C:\Data\Agent C:\Tmp\Agent -Recurse -Force
C:\Tmp\Agent\config.cmd --unattended --url "${Env:AZURE_PIPELINES_URL}" --pool "${Env:AZURE_PIPELINES_POOL}" --agent "${Agent_Name}" --auth pat --token "${Env:AZURE_PIPELINES_PAT}" --replace
CheckLastExitCode

$ret=0
while ($ret -eq 0) {
	Write-Host ""
	Write-Host ":: Starting agent..."
	docker run -v "C:/Tmp:C:/Tmp:ro" "${Image}" powershell 'Copy-Item C:\Tmp\Agent C:\ -Recurse ; C:\Agent\run.cmd --once'
	$ret=$LastExitCode
	Write-Host ":: Agent exited with: ${ret}"
}

Write-Host ""
Write-Host ":: Cleaning up runner agent..."
C:\Tmp\Agent\config.cmd remove --auth pat --token "${Env:AZURE_PIPELINES_PAT}"
CheckLastExitCode

echo ":: Exiting (exit code ${ret})"
exit $ret

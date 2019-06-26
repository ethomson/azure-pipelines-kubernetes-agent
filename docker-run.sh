#!/bin/sh

set -e

if [ -z "$AZURE_PIPELINES_URL" -o -z "$AZURE_PIPELINES_POOL" -o -z "$AZURE_PIPELINES_PAT" ]; then
	echo "Configuration is incomplete; the following environment variables must be set:" >&2
	echo " AZURE_PIPELINES_URL to the URL of your Azure DevOps organization" >&2
	echo " AZURE_PIPELINES_POOL to the name of the pool that this agent will belong" >&2
	echo " AZURE_PIPELINES_PAT to the PAT to authenticate to Azure DevOps" >&2
	exit 1
fi

IMAGE="ethomson/azure-pipelines-agent-linux:latest"

export AGENT_ALLOW_RUNASROOT=1

export AGENT_GUID=$(uuidgen)
export AGENT_NAME="${AZURE_PIPELINES_AGENT_NAME:-"$(hostname)_${AGENT_GUID}"}"

# Register an agent that will remain idle; we always need an agent in the
# pool and since our container agents create and delete themselves, there's
# a possibility of the pool existing with no agents in it, and jobs will
# fail to queue in this case.  This idle agent will prevent that.
echo ""
echo ":: Setting up reserved agent (${AZURE_PIPELINES_POOL}_reserved)..."
cp -R /data/agent /data/reserved_agent
"/data/reserved_agent/config.sh" --unattended --url "${AZURE_PIPELINES_URL}" --pool "${AZURE_PIPELINES_POOL}" --agent "${AZURE_PIPELINES_POOL}_reserved" --auth pat --token "${AZURE_PIPELINES_PAT}" --replace

# Set up the actual runner that will do work.
echo ""
echo ":: Setting up runner agent (${AGENT_NAME})..."
rm -rf /data/share/agent
cp -R /data/agent /data/share
"/data/share/agent/config.sh" --unattended --url "${AZURE_PIPELINES_URL}" --pool "${AZURE_PIPELINES_POOL}" --agent "${AGENT_NAME}" --auth pat --token "${AZURE_PIPELINES_PAT}"

ret=0
while [ $ret -eq 0 ]; do
    echo ""
    echo ":: Starting agent..."
    docker run -v "/data/share:/data/share:ro" -e "AGENT_ALLOW_RUNASROOT=1" "${IMAGE}" /bin/sh -c "cp -R /data/share/agent / && /agent/run.sh --once" || ret=$? && true
    echo ":: Agent exited with: ${ret}"
done

echo ""
echo ":: Cleaning up runner agent..."
/data/share/agent/config.sh remove --auth pat --token "${AZURE_PIPELINES_PAT}"

echo ":: Exiting (exit code ${ret})"
exit $ret

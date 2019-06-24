#!/bin/sh

set -e

if [ -z "$AZURE_PIPELINES_URL" -o -z "$AZURE_PIPELINES_POOL" -o -z "$AZURE_PIPELINES_PAT" ]; then
	echo "Configuration is incomplete; the following environment variables must be set:" >&2
	echo " AZURE_PIPELINES_URL to the URL of your Azure DevOps organization" >&2
	echo " AZURE_PIPELINES_POOL to the name of the pool that this agent will belong" >&2
	echo " AZURE_PIPELINES_PAT to the PAT to authenticate to Azure DevOps" >&2
	exit 1
fi

IMAGE="ethomson/azure-pipelines-agent:latest"

URL="$AZURE_PIPELINES_URL"
POOL="$AZURE_PIPELINES_POOL"
AGENT_NAME="${AZURE_PIPELINES_AGENT_NAME:-$(hostname)}"
PAT="${AZURE_PIPELINES_PAT}"

unset AZURE_PIPELINES_URL
unset AZURE_PIPELINES_POOL
unset AZURE_PIPELINES_AGENT_NAME
unset AZURE_PIPELINES_PAT

export AGENT_ALLOW_RUNASROOT=1

export AGENT_GUID=$(uuidgen)

# Register an agent that will remain idle; we always need an agent in the
# pool and since our container agents create and delete themselves, there's
# a possibility of the pool existing with no agents in it, and jobs will
# fail to queue in this case.  This idle agent will prevent that.
echo ""
echo ":: Setting up reserved agent..."
cp -R /data/agent /data/reserved_agent
"/data/reserved_agent/config.sh" --unattended --url "${URL}" --pool "${POOL}" --agent "${AGENT_NAME}_reserved" --auth pat --token "${PAT}" --replace

# Set up the actual runner that will do work.
echo ""
echo ":: Setting up runner agent..."
cp -R /data/agent /data/share
"/data/share/agent/config.sh" --unattended --url "${URL}" --pool "${POOL}" --agent "${AGENT_NAME}_${AGENT_GUID}" --auth pat --token "${PAT}" --replace

ret=0
while [ $ret -eq 0 ]; do
    echo ""
    echo ":: Starting agent..."
    docker run -v "/data/share:/data/share:ro" -e "AGENT_ALLOW_RUNASROOT=1" "${IMAGE}" /bin/sh -c "cp -R /data/share/agent / && /agent/run.sh --once" || ret=$? && true
done

echo ""
echo ":: Cleaning up runner agent..."
/data/share/agent/config.sh remove --auth pat --token "${PAT}"

echo ""
echo ":: Cleaning up reserved agent..."
/data/reserved_agent/config.sh remove --auth pat --token "${PAT}"

echo ":: Exiting (exit code ${ret})"
exit $ret

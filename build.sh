IMAGE_TAG="ethomson/azure-pipelines-k8s-linux:latest"

docker build . -f Dockerfile.linux -t ${IMAGE_TAG}
docker push ${IMAGE_TAG}

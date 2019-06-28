$Image_Tag="ethomson/azure-pipelines-k8s-win32:latest"

docker build . -f Dockerfile.win32 -t ${Image_Tag}
docker push ${Image_Tag}

<p align="center">
  <img src="docs/images/banner.svg" alt="k8s-dockerhub-detector banner" width="900"/>
</p>

<h1 align="center">k8s-dockerhub-detector</h1>

<p align="center">
  Detects where DockerHub is still used in a Kubernetes cluster.
</p>

---

Due to the incoming rate limit from DockerHub, there is a need to migrate away from it. This piece of software detects where in the cluster DockerHub is still used.

## Usage

Save the bash script to your PATH, apply `chmod +x inspector.sh` and then you can use it as `bash inspector.sh [-n namespace]`

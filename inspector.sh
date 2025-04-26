#!/bin/bash
# Usage: "bash inspector.sh [-n namespace]"

# Function to check if an image is from Docker Hub
is_docker_hub_image() {
    local image="$1"
    local remainder="$image"
    local registry=""

    # Remove the digest if present (after '@')
    remainder="${remainder%%@*}"
    # Remove the tag if present (after ':')
    remainder="${remainder%%:*}"

    # Check if there is a registry component (part before the first '/')
    if [[ "$remainder" =~ ^([^/]+)/(.+)$ ]]; then
        local possible_registry="${BASH_REMATCH[1]}"
        # If the possible registry contains '.' or ':', it's a registry
        if [[ "$possible_registry" == *"."* ]] || [[ "$possible_registry" == *":"* ]]; then
            registry="$possible_registry"
        fi
    fi

    # Determine if the image is from Docker Hub
    if [ -z "$registry" ] || [ "$registry" == "docker.io" ]; then
        return 0 # true, image is from Docker Hub
    else
        return 1 # false, image is not from Docker Hub
    fi
}

# ANSI color codes
RED='\033[0;31m'
NC='\033[0m' # No Color

# Initialize the Docker Hub image counters
docker_hub_image_count=0            # Total number of Docker Hub images (including duplicates)
declare -A docker_hub_images_seen   # Associative array to track unique images

# Initialize separate counters for container and initContainer images
total_container_images=0
total_init_container_images=0
declare -A unique_docker_hub_container_images_seen
declare -A unique_docker_hub_init_container_images_seen

# Default - consider all namespaces
namespaces=()

# Parse options
while getopts ":n:" opt; do
  case $opt in
    n)
      # User provided a namespace
      namespaces=("$OPTARG")
      ;;
    \?)
      echo "Invalid option: -$OPTARG" >&2
      echo "Usage: $0 [-n namespace]" >&2
      exit 1
      ;;
  esac
done

# If no namespace provided, get all namespaces
if [ ${#namespaces[@]} -eq 0 ]; then
    # Get all namespaces
    mapfile -t namespaces < <(kubectl get namespaces -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}')
fi

# Iterate over namespaces
for ns in "${namespaces[@]}"; do
    # Get all pods in the current namespace, each on a new line
    mapfile -t pods < <(kubectl get pods -n "$ns" -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}')

    # Check if there are any pods in the namespace
    if [ ${#pods[@]} -eq 0 ]; then
        continue
    fi

    namespace_outputted=false

    # Iterate over pods
    for pod in "${pods[@]}"; do
        # Get the images used by the pod's containers
        mapfile -t container_images < <(kubectl get pod "$pod" -n "$ns" -o jsonpath='{range .spec.containers[*]}{.image}{"\n"}{end}')

        # Get the images used by the pod's initContainers
        mapfile -t init_container_images < <(kubectl get pod "$pod" -n "$ns" -o jsonpath='{range .spec.initContainers[*]}{.image}{"\n"}{end}')

        # Declare an array to collect offending images
        offending_images=()

        # Process container images
        for image in "${container_images[@]}"; do
            if is_docker_hub_image "$image"; then
                offending_images+=("Container image: $image")
                # Increment the Docker Hub image counters
                docker_hub_image_count=$((docker_hub_image_count + 1))
                total_container_images=$((total_container_images + 1))
                # Check if the image is already counted for unique container images
                if [ -z "${unique_docker_hub_container_images_seen["$image"]}" ]; then
                    unique_docker_hub_container_images_seen["$image"]=1
                fi
                # Add to overall unique images
                if [ -z "${docker_hub_images_seen["$image"]}" ]; then
                    docker_hub_images_seen["$image"]=1
                fi
            fi
        done

        # Process initContainer images
        for image in "${init_container_images[@]}"; do
            if is_docker_hub_image "$image"; then
                offending_images+=("InitContainer image: $image")
                # Increment the Docker Hub image counters
                docker_hub_image_count=$((docker_hub_image_count + 1))
                total_init_container_images=$((total_init_container_images + 1))
                # Check if the image is already counted for unique initContainer images
                if [ -z "${unique_docker_hub_init_container_images_seen["$image"]}" ]; then
                    unique_docker_hub_init_container_images_seen["$image"]=1
                fi
                # Add to overall unique images
                if [ -z "${docker_hub_images_seen["$image"]}" ]; then
                    docker_hub_images_seen["$image"]=1
                fi
            fi
        done

        # If any offending images found, output the pod and images
        if [ ${#offending_images[@]} -gt 0 ]; then
            # Output namespace header only once
            if ! $namespace_outputted; then
                echo "-----------------------"
                echo "Namespace: $ns"
                echo "-----------------------"
                namespace_outputted=true
            fi
            echo "Pod: $pod"
            echo "Images:"
            for img in "${offending_images[@]}"; do
                echo -e "  - ${RED}$img${NC}"
            done
            echo
        fi
    done
done

# Compute unique image counts
unique_docker_hub_container_image_count=${#unique_docker_hub_container_images_seen[@]}
unique_docker_hub_init_container_image_count=${#unique_docker_hub_init_container_images_seen[@]}
unique_docker_hub_image_count=${#docker_hub_images_seen[@]}

# Output the detailed counts
echo "Total DockerHub images used as container image: $total_container_images"
echo "Total DockerHub images used as initContainer image: $total_init_container_images"
echo "Total DockerHub images: $docker_hub_image_count"
echo "Different DockerHub images used as container image: $unique_docker_hub_container_image_count"
echo "Different DockerHub images used as initContainer image: $unique_docker_hub_init_container_image_count"
echo "Total Different DockerHub images: $unique_docker_hub_image_count"

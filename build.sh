#!/bin/bash

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

IMAGE_NAME="iserverobotics/livox_recorder"
ROS_DISTRO="jazzy"
PUSH=true
MANIFEST=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --no-push)
            PUSH=false
            shift
            ;;
        --manifest)
            MANIFEST=true
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --no-push       Build only, don't push to Docker Hub"
            echo "  --manifest      Build native arch, push, and stitch into multi-arch manifest"
            echo "  --help, -h      Show this help message"
            echo ""
            echo "Examples:"
            echo "  $0 --no-push    # Build for local arch only"
            echo "  $0              # Build and push (single arch)"
            echo "  $0 --manifest   # Build native, push, stitch manifest"
            exit 0
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            echo "Run '$0 --help' for usage information"
            exit 1
            ;;
    esac
done

IMAGE_TAG="${ROS_DISTRO}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Detect native architecture
NATIVE_ARCH="$(uname -m)"
case "${NATIVE_ARCH}" in
    x86_64)  DOCKER_ARCH="amd64" ;;
    aarch64) DOCKER_ARCH="arm64" ;;
    *)       DOCKER_ARCH="${NATIVE_ARCH}" ;;
esac

echo -e "${GREEN}================================================${NC}"
echo -e "${GREEN}Building Livox Recorder Docker Image${NC}"
echo -e "${GREEN}  Image:  ${IMAGE_NAME}:${IMAGE_TAG}${NC}"
echo -e "${GREEN}  ROS:    ${ROS_DISTRO}${NC}"
echo -e "${GREEN}  Arch:   ${DOCKER_ARCH}${NC}"
if [ "${MANIFEST}" = true ]; then
echo -e "${GREEN}  Mode:   manifest (build + push + stitch)${NC}"
fi
echo -e "${GREEN}================================================${NC}"
echo ""

if [ "${MANIFEST}" = true ]; then
    ARCH_TAG="${IMAGE_TAG}-${DOCKER_ARCH}"

    docker build \
        -f "${SCRIPT_DIR}/Dockerfile" \
        --build-arg ROS_DISTRO=${ROS_DISTRO} \
        -t ${IMAGE_NAME}:${ARCH_TAG} \
        "${SCRIPT_DIR}"

    echo ""
    echo -e "${YELLOW}Pushing ${IMAGE_NAME}:${ARCH_TAG}...${NC}"
    docker push ${IMAGE_NAME}:${ARCH_TAG}

    echo ""
    echo -e "${YELLOW}Stitching multi-arch manifest for ${IMAGE_NAME}:${IMAGE_TAG}...${NC}"
    MANIFEST_ARGS=""
    for arch in amd64 arm64; do
        if docker manifest inspect ${IMAGE_NAME}:${IMAGE_TAG}-${arch} &>/dev/null; then
            MANIFEST_ARGS="${MANIFEST_ARGS} ${IMAGE_NAME}:${IMAGE_TAG}-${arch}"
            echo -e "  Found: ${IMAGE_NAME}:${IMAGE_TAG}-${arch}"
        else
            echo -e "  ${YELLOW}Not found: ${IMAGE_NAME}:${IMAGE_TAG}-${arch} (skipping)${NC}"
        fi
    done

    if [ -z "${MANIFEST_ARGS}" ]; then
        echo -e "${RED}Error: No arch-specific tags found on registry.${NC}"
        exit 1
    fi

    docker manifest rm ${IMAGE_NAME}:${IMAGE_TAG} 2>/dev/null || true
    docker manifest rm ${IMAGE_NAME}:latest 2>/dev/null || true

    docker manifest create ${IMAGE_NAME}:${IMAGE_TAG} ${MANIFEST_ARGS}
    docker manifest push ${IMAGE_NAME}:${IMAGE_TAG}

    docker manifest create ${IMAGE_NAME}:latest ${MANIFEST_ARGS}
    docker manifest push ${IMAGE_NAME}:latest

    echo ""
    echo -e "${GREEN}Multi-arch manifest pushed!${NC}"

else
    docker build \
        -f "${SCRIPT_DIR}/Dockerfile" \
        --build-arg ROS_DISTRO=${ROS_DISTRO} \
        -t ${IMAGE_NAME}:${IMAGE_TAG} \
        -t ${IMAGE_NAME}:latest \
        "${SCRIPT_DIR}"

    echo ""
    echo -e "${GREEN}Build complete!${NC}"

    if [ "${PUSH}" = true ]; then
        echo -e "${YELLOW}Pushing ${IMAGE_NAME}...${NC}"
        docker push ${IMAGE_NAME}:${IMAGE_TAG}
        docker push ${IMAGE_NAME}:latest
        echo -e "${GREEN}Push complete!${NC}"
    fi
fi

echo ""
echo -e "${GREEN}================================================${NC}"
echo -e "${GREEN}Done!${NC}"
echo -e "${GREEN}================================================${NC}"
echo ""
echo "To run:"
echo -e "${YELLOW}  docker compose up${NC}"

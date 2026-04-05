#!/bin/bash

# Colors
red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
plain='\033[0m'

# Ensure root privileges for dependency installation
if [[ $EUID -ne 0 ]]; then
    echo -e "${red}Please run this script with root privileges to install dependencies.${plain}"
    exit 1
fi

# Capture original execution directory (Should be the 3x-node project root)
ORIG_DIR=$(pwd)

# Basic check to ensure we are actually inside the 3x-node project directory
if [[ ! -f "$ORIG_DIR/main.go" ]] || [[ ! -f "$ORIG_DIR/go.mod" ]]; then
    echo -e "${red}Error: main.go or go.mod not found!${plain}"
    echo -e "${red}Please run this script from inside your 3x-node project directory.${plain}"
    exit 1
fi

echo -e "${green}Starting local x-node & XPray-core automated build process...${plain}"

# Detect OS
if [[ -f /etc/os-release ]]; then
    source /etc/os-release
    release=$ID
else
    echo -e "${red}Unsupported OS for dependency installation.${plain}"
    exit 1
fi

# Install Required Dependencies
echo -e "${yellow}Installing build dependencies...${plain}"
case "${release}" in
    ubuntu | debian | armbian)
        apt-get update
        apt-get install -y git wget curl tar unzip golang-go make
    ;;
    arch | manjaro | parch)
        pacman -Syu --noconfirm git wget curl tar unzip go make
    ;;
    *)
        echo -e "${red}This build script natively supports Arch, Ubuntu, and Debian.${plain}"
        echo -e "${yellow}Attempting to proceed anyway...${plain}"
    ;;
esac

# Create temporary build environment for XPray
BUILD_DIR="/tmp/x-node-build"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"


# ==========================================
# 1. Build Local x-node Panel
# ==========================================
cd "$ORIG_DIR" || exit 1

echo -e "${yellow}Compiling x-node Go Application...${plain}"
go build -o x-node .
if [[ $? -ne 0 ]]; then
    echo -e "${red}Compilation of x-node failed! Check your local code or Go installation.${plain}"
    exit 1
fi

# Setup folder structure for packaging
echo -e "${yellow}Preparing release package structure...${plain}"
PKG_DIR="release/x-node"
rm -rf release/ # Clean up previous builds if they exist
mkdir -p "$PKG_DIR/bin"

# Copy panel local dependencies into folder structure
cp x-node "$PKG_DIR/"
cp x-node.sh "$PKG_DIR/" 2>/dev/null || true
cp x-node.rc "$PKG_DIR/" 2>/dev/null || true
cp *.service* "$PKG_DIR/" 2>/dev/null || true


# ==========================================
# 2. Clone and Build XPray-core
# ==========================================
cd "$BUILD_DIR" || exit 1

echo -e "${yellow}Cloning XPray-core (branch: node-main)...${plain}"
git clone -b node-main https://github.com/danya2271/XPray-core.git
cd XPray-core || exit 1

echo -e "${yellow}Compiling XPray-core from source...${plain}"
env CGO_ENABLED=0 go build -o xray -trimpath -ldflags "-s -w -buildid=" ./main
if [[ $? -ne 0 ]]; then
    echo -e "${red}Compilation of XPray-core failed!${plain}"
    exit 1
fi

# Move the compiled binary directly into the local release folder
echo -e "${yellow}Moving XPray-core to package directory...${plain}"
cp xray "$ORIG_DIR/$PKG_DIR/bin/xray-linux-amd64"
chmod +x "$ORIG_DIR/$PKG_DIR/bin/xray-linux-amd64"

# ==========================================
# 2.5 Add Missing Files (Geo Assets, Readme, License)
# ==========================================
echo -e "${yellow}Copying LICENSE and README.md...${plain}"
cp LICENSE "$ORIG_DIR/$PKG_DIR/bin/LICENSE" 2>/dev/null || true
cp README.md "$ORIG_DIR/$PKG_DIR/bin/README.md" 2>/dev/null || true

echo -e "${yellow}Downloading standard GeoIP and GeoSite files...${plain}"
wget -q --show-progress -O "$ORIG_DIR/$PKG_DIR/bin/geoip.dat" "https://github.com/v2fly/geoip/releases/latest/download/geoip.dat"
wget -q --show-progress -O "$ORIG_DIR/$PKG_DIR/bin/geosite.dat" "https://github.com/v2fly/domain-list-community/releases/latest/download/dlc.dat"

echo -e "${yellow}Downloading RU specific GeoIP and GeoSite files...${plain}"
wget -q --show-progress -O "$ORIG_DIR/$PKG_DIR/bin/geoip_RU.dat" "https://github.com/runetfreedom/russia-v2ray-rules-dat/releases/latest/download/geoip.dat"
wget -q --show-progress -O "$ORIG_DIR/$PKG_DIR/bin/geosite_RU.dat" "https://github.com/runetfreedom/russia-v2ray-rules-dat/releases/latest/download/geosite.dat"
# (IR dat files intentionally omitted per request)


# ==========================================
# 3. Package and Cleanup
# ==========================================
cd "$ORIG_DIR/release" || exit 1

echo -e "${yellow}Compressing into x-node-linux-amd64.tar.gz...${plain}"
tar -czvf x-node-linux-amd64.tar.gz x-node/

# Move the resulting tarball back to the project root
cp x-node-linux-amd64.tar.gz "$ORIG_DIR/"

# Cleanup
rm -rf "$BUILD_DIR"

echo -e " "
echo -e "${green}Build complete!${plain}"
echo -e "Your package is ready and saved at: ${yellow}${ORIG_DIR}/x-node-linux-amd64.tar.gz${plain}"

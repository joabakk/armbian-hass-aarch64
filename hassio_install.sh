#!/bin/bash
set -e

#
# This is script from https://raw.githubusercontent.com/home-assistant/hassio-build/master/install/hassio_install
# Only change is not to start Hass.io service at the end.
#

ARCH=$(uname -m)
DOCKER_REPO=homeassistant
DATA_SHARE=/usr/share/hassio
URL_VERSION="https://s3.amazonaws.com/hassio-version/stable.json"
URL_BIN_HASSIO="https://raw.githubusercontent.com/home-assistant/hassio-build/master/install/files/hassio-supervisor"
URL_BIN_APPARMOR="https://raw.githubusercontent.com/home-assistant/hassio-build/master/install/files/hassio-apparmor"
URL_SERVICE_HASSIO="https://raw.githubusercontent.com/home-assistant/hassio-build/master/install/files/hassio-supervisor.service"
URL_SERVICE_APPARMOR="https://raw.githubusercontent.com/home-assistant/hassio-build/master/install/files/hassio-apparmor.service"
URL_APPARMOR_PROFILE="http://s3.amazonaws.com/hassio-version/apparmor.txt"

# Check env
command -v systemctl > /dev/null 2>&1 || { echo "[Error] Only systemd is supported!"; exit 1; }
command -v docker > /dev/null 2>&1 || { echo "[Error] Please install docker first"; exit 1; }
command -v jq > /dev/null 2>&1 || { echo "[Error] Please install jq first"; exit 1; }
command -v curl > /dev/null 2>&1 || { echo "[Error] Please install curl first"; exit 1; }
command -v avahi-daemon > /dev/null 2>&1 || { echo "[Error] Please install avahi first"; exit 1; }
command -v dbus-daemon > /dev/null 2>&1 || { echo "[Error] Please install dbus first"; exit 1; }
command -v apparmor_parser > /dev/null 2>&1 || echo "[Warning] No AppArmor support on Host."
command -v nmcli > /dev/null 2>&1 || echo "[Warning] No NetworkManager support on Host."

# Parse command line parameters
while [[ $# > 0 ]]; do
    arg="$1"

    case $arg in
        -m|--machine)
            MACHINE=$2
            shift
            ;;
        -d|--data-share)
            DATA_SHARE=$2
            shift
            ;;
        *)
            echo "[Error] Unrecognized option $1"
            exit 1
            ;;
    esac
    shift
done

# Generate hardware options
case $ARCH in
    "i386" | "i686")
        MACHINE=${MACHINE:=qemux86}
        HOMEASSISTANT_DOCKER="$DOCKER_REPO/$MACHINE-homeassistant"
        HASSIO_DOCKER="$DOCKER_REPO/i386-hassio-supervisor"
    ;;
    "x86_64")
        MACHINE=${MACHINE:=qemux86-64}
        HOMEASSISTANT_DOCKER="$DOCKER_REPO/$MACHINE-homeassistant"
        HASSIO_DOCKER="$DOCKER_REPO/amd64-hassio-supervisor"
    ;;
    "arm" | "armv7l" | "armv6l")
        if [ -z $MACHINE ]; then
            echo "[ERROR] Please set machine for $ARCH"
            exit 1
        fi
        HOMEASSISTANT_DOCKER="$DOCKER_REPO/$MACHINE-homeassistant"
        HASSIO_DOCKER="$DOCKER_REPO/armhf-hassio-supervisor"
    ;;
    "aarch64")
        if [ -z $MACHINE ]; then
            echo "[ERROR] Please set machine for $ARCH"
            exit 1
        fi
        HOMEASSISTANT_DOCKER="$DOCKER_REPO/$MACHINE-homeassistant"
        HASSIO_DOCKER="$DOCKER_REPO/aarch64-hassio-supervisor"
    ;;
    *)
        echo "[Error] $ARCH unknown!"
        exit 1
    ;;
esac

if [ -z "${HOMEASSISTANT_DOCKER}" ]; then
    echo "[Error] Found no Home Assistant docker images for this host!"
fi

### Main

# Init folders
if [ ! -d "$DATA_SHARE" ]; then
    mkdir -p "$DATA_SHARE"
fi

# Read infos from web
HASSIO_VERSION=$(curl -s $URL_VERSION | jq -e -r '.supervisor')

##
# Write config
cat > /etc/hassio.json <<- EOF
{
    "supervisor": "${HASSIO_DOCKER}",
    "homeassistant": "${HOMEASSISTANT_DOCKER}",
    "data": "${DATA_SHARE}"
}
EOF

##
# Pull supervisor image
echo "[Info] Install supervisor docker"
docker pull "$HASSIO_DOCKER:$HASSIO_VERSION" > /dev/null
docker tag "$HASSIO_DOCKER:$HASSIO_VERSION" "$HASSIO_DOCKER:latest" > /dev/null

##
# Install Hass.io Supervisor
echo "[Info] Install supervisor startup scripts"
curl -sL ${URL_BIN_HASSIO} > /usr/sbin/hassio-supervisor
curl -sL ${URL_SERVICE_HASSIO} > /etc/systemd/system/hassio-supervisor.service

chmod a+x /usr/sbin/hassio-supervisor
systemctl enable hassio-supervisor.service

#
# Install Hass.io AppArmor
if command -v apparmor_parser > /dev/null 2>&1; then
    echo "[Info] Install AppArmor scripts"
    mkdir -p ${DATA_SHARE}/apparmor
    curl -sL ${URL_BIN_APPARMOR} > /usr/sbin/hassio-apparmor
    curl -sL ${URL_SERVICE_APPARMOR} > /etc/systemd/system/hassio-apparmor.service
    curl -sL ${URL_APPARMOR_PROFILE} > ${DATA_SHARE}/apparmor/hassio-supervisor

    chmod a+x /usr/sbin/hassio-apparmor
    systemctl enable hassio-apparmor.service

    systemctl start hassio-apparmor.service
fi

echo "Hass.io installation done. Use 'systemctl start hassio-supervisor.service' command to start it."
##
# Init system
#echo "[Info] Run Hass.io"
#systemctl start hassio-supervisor.service
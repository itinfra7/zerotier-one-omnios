#!/usr/bin/bash

# ==============================================================================
# ZeroTier One 1.16.1 Installer for OmniOS r151054 LTS
#
# Release:
# - Version: v1.0.0
# - Date: 2026-03-20
#
# Credits:
# - ZeroTier One Upstream: https://github.com/zerotier/ZeroTierOne
# - OmniOS Patch & Tutorial: itinfra7 on GitHub (https://www.ourdare.com)
# - Pinned upstream commit: d9a7f62a5ca04f832d1025bcc7c48f9e8d65e3a6
# ==============================================================================

set -euo pipefail

ZEROTIER_UPSTREAM_VERSION="1.16.1"
ZEROTIER_UPSTREAM_COMMIT="d9a7f62a5ca04f832d1025bcc7c48f9e8d65e3a6"
RELEASE_BASE_URL="https://github.com/itinfra7/zerotier-one-omnios/releases/latest/download"
RELEASE_TAG="v1.0.0"
RELEASE_DATE="2026-03-20"
SERVICE_FMRI="svc:/network/zerotier-one:default"
ZEROTIER_MATCH="/opt/zerotier-one/bin/zerotier-one.*\\/var/lib/zerotier-one"

cleanup_tmp() {
    rm -f /tmp/zerotier-one-info.out /tmp/zerotier-one-info.err
}

stop_existing_service() {
    if svcs -H -o state "${SERVICE_FMRI}" >/dev/null 2>&1; then
        svcadm disable -st "${SERVICE_FMRI}" || true
    fi

    if [ -x /opt/zerotier-one/bin/zerotier-one-smf ]; then
        /opt/zerotier-one/bin/zerotier-one-smf stop || true
    fi

    if pgrep -f "${ZEROTIER_MATCH}" >/dev/null 2>&1; then
        pkill -TERM -f "${ZEROTIER_MATCH}" || true
        sleep 2
        pkill -KILL -f "${ZEROTIER_MATCH}" || true
    fi
}

verify_service_ready() {
    typeset attempt=0

    while [ "${attempt}" -lt 60 ]; do
        if [ "$(svcs -H -o state "${SERVICE_FMRI}" 2>/dev/null || true)" = "online" ] && PATH="/usr/bin:/usr/sbin:/opt/ooce/bin" zerotier-cli info >/tmp/zerotier-one-info.out 2>/tmp/zerotier-one-info.err; then
            return 0
        fi
        attempt=$((attempt + 1))
        sleep 1
    done

    return 1
}

trap cleanup_tmp EXIT

# Clear screen for better readability
clear

echo "========================================================"
echo " ZeroTier One ${ZEROTIER_UPSTREAM_VERSION} Installer for OmniOS r151054 LTS"
echo " Release: ${RELEASE_TAG} (${RELEASE_DATE})"
echo " Credits: "
echo "  - https://github.com/zerotier/ZeroTierOne"
echo "  - itinfra7 on GitHub"
echo "========================================================"
echo ""

# 1. Language Selection
read -p "Select language / 언어를 선택하세요 (1: English, 2: 한국어) [1/2]: " LANG_CHOICE

if [ "${LANG_CHOICE}" = "2" ]; then
    MSG_ROOT="이 스크립트는 루트(root) 권한으로 실행해야 합니다."
    MSG_PLATFORM="이 스크립트는 OmniOS r151054 LTS에서만 지원됩니다."
    MSG_START="ZeroTier One ${ZEROTIER_UPSTREAM_VERSION} 설치를 시작하시겠습니까? (y/n): "
    MSG_STEP1="[1/10] 필수 패키지 설치 중 (developer/versioning/git, developer/build/gnu-make, developer/gcc14)..."
    MSG_STEP2="[2/10] 기존 zerotier-one 서비스와 프로세스 정리 중..."
    MSG_STEP3="[3/10] ZeroTier One ${ZEROTIER_UPSTREAM_VERSION} 소스 코드 가져오는 중..."
    MSG_STEP4="[4/10] OmniOS 소스 패치 다운로드 및 적용 중..."
    MSG_STEP5="[5/10] 소스 코드 빌드 중 (시간이 다소 소요될 수 있습니다)..."
    MSG_STEP6="[6/10] 바이너리 복사 및 런타임 디렉터리 준비 중..."
    MSG_STEP7="[7/10] SMF 메소드 스크립트 설치 중..."
    MSG_STEP8="[8/10] SMF 매니페스트 설치 중..."
    MSG_STEP9="[9/10] 서비스 등록 및 실행 중..."
    MSG_STEP10="[10/10] 서비스 상태 검증 중..."
    MSG_VERIFY_FAIL="서비스가 준비 상태가 되지 않았습니다. 'svcs -xv zerotier-one' 및 'zerotier-cli info'로 상태를 확인하세요."
    MSG_FWD_PROMPT="이 서버를 라우터나 중계 노드로 사용하기 위해 IP 포워딩을 활성화하시겠습니까? (선택 사항) (y/n): "
    MSG_FWD_DONE="IP 포워딩이 활성화되었습니다."
    MSG_DONE="설치가 성공적으로 완료되었습니다. 'svcs -xv zerotier-one' 및 'zerotier-cli info'로 상태를 확인하세요."
    MSG_ABORT="설치가 취소되었습니다."
else
    MSG_ROOT="This script must be run as root."
    MSG_PLATFORM="This script only supports OmniOS r151054 LTS."
    MSG_START="Do you want to start the installation of ZeroTier One ${ZEROTIER_UPSTREAM_VERSION}? (y/n): "
    MSG_STEP1="[1/10] Installing required packages (developer/versioning/git, developer/build/gnu-make, developer/gcc14)..."
    MSG_STEP2="[2/10] Stopping any existing zerotier-one service and process..."
    MSG_STEP3="[3/10] Cloning ZeroTier One ${ZEROTIER_UPSTREAM_VERSION} source code..."
    MSG_STEP4="[4/10] Downloading and applying the OmniOS source patch..."
    MSG_STEP5="[5/10] Building source code (this may take some time)..."
    MSG_STEP6="[6/10] Installing binaries and preparing runtime directories..."
    MSG_STEP7="[7/10] Installing SMF method script..."
    MSG_STEP8="[8/10] Installing SMF manifest..."
    MSG_STEP9="[9/10] Registering and starting the service..."
    MSG_STEP10="[10/10] Verifying service state and CLI response..."
    MSG_VERIFY_FAIL="The service did not become ready. Check 'svcs -xv zerotier-one' and 'zerotier-cli info'."
    MSG_FWD_PROMPT="Do you want to enable IP forwarding to use this node as a router/relay? (Optional) (y/n): "
    MSG_FWD_DONE="IP forwarding has been enabled."
    MSG_DONE="Installation completed successfully. Check the status using 'svcs -xv zerotier-one' and 'zerotier-cli info'."
    MSG_ABORT="Installation aborted."
fi

echo ""

# 2. Root and Platform Check
if [ "${EUID}" -ne 0 ]; then
    echo "${MSG_ROOT}"
    exit 1
fi

if [ "$(/usr/bin/uname -s)" != "SunOS" ] || ! /usr/bin/uname -v | /usr/bin/grep -q '^omnios-r151054'; then
    echo "${MSG_PLATFORM}"
    exit 1
fi

# 3. Start Confirmation
read -p "${MSG_START}" START_CHOICE
if [[ "${START_CHOICE}" != "y" && "${START_CHOICE}" != "Y" ]]; then
    echo "${MSG_ABORT}"
    exit 0
fi

echo ""
echo "--------------------------------------------------------"

# Step 1: Install prerequisites
echo "${MSG_STEP1}"
pkg install --accept developer/versioning/git developer/build/gnu-make developer/gcc14

# Step 2: Stop existing service
echo "${MSG_STEP2}"
stop_existing_service

# Step 3: Clone repository
echo "${MSG_STEP3}"
rm -rf /opt/ZeroTierOne
git clone https://github.com/zerotier/ZeroTierOne.git /opt/ZeroTierOne
cd /opt/ZeroTierOne
git checkout --force "${ZEROTIER_UPSTREAM_COMMIT}"
git reset --hard "${ZEROTIER_UPSTREAM_COMMIT}"
git clean -fdx

# Step 4: Download and apply patch
echo "${MSG_STEP4}"
wget "${RELEASE_BASE_URL}/omnios-zerotier-one.patch" -O /opt/ZeroTierOne/omnios-zerotier-one.patch
patch -p1 < omnios-zerotier-one.patch

# Step 5: Build
echo "${MSG_STEP5}"
export PATH="/usr/bin:/usr/sbin:/opt/gcc-14/bin:/usr/gnu/bin:${PATH}"
gmake OSTYPE=OpenBSD CC=gcc CXX=g++ -j1 one

# Step 6: Install binaries and prepare directories
echo "${MSG_STEP6}"
mkdir -p /opt/zerotier-one/bin
mkdir -p /opt/ooce/bin
mkdir -p /var/lib/zerotier-one

cp /opt/ZeroTierOne/zerotier-one /opt/zerotier-one/bin/zerotier-one
chmod 755 /opt/zerotier-one/bin/zerotier-one

ln -sf /opt/zerotier-one/bin/zerotier-one /opt/zerotier-one/bin/zerotier-cli
ln -sf /opt/zerotier-one/bin/zerotier-one /opt/zerotier-one/bin/zerotier-idtool

ln -sf /opt/zerotier-one/bin/zerotier-one /opt/ooce/bin/zerotier-one
ln -sf /opt/zerotier-one/bin/zerotier-one /opt/ooce/bin/zerotier-cli
ln -sf /opt/zerotier-one/bin/zerotier-one /opt/ooce/bin/zerotier-idtool

# Step 7: SMF method script
echo "${MSG_STEP7}"
wget "${RELEASE_BASE_URL}/zerotier-one-smf" -O /opt/zerotier-one/bin/zerotier-one-smf
# Normalize CRLF line endings from downloaded release assets before SMF executes them.
/usr/bin/perl -pi -e 's/\r//g' /opt/zerotier-one/bin/zerotier-one-smf
chmod 755 /opt/zerotier-one/bin/zerotier-one-smf

# Step 8: SMF manifest
echo "${MSG_STEP8}"
mkdir -p /var/svc/manifest/network
wget "${RELEASE_BASE_URL}/zerotier-one.xml" -O /var/svc/manifest/network/zerotier-one.xml
/usr/bin/perl -pi -e 's/\r//g' /var/svc/manifest/network/zerotier-one.xml

# Step 9: Register and start service
echo "${MSG_STEP9}"
svccfg import /var/svc/manifest/network/zerotier-one.xml
svcadm enable -r "${SERVICE_FMRI}"

# Step 10: Verify service readiness
echo "${MSG_STEP10}"
if ! verify_service_ready; then
    cat /tmp/zerotier-one-info.err 2>/dev/null || true
    cat /tmp/zerotier-one-info.out 2>/dev/null || true
    echo "${MSG_VERIFY_FAIL}"
    exit 1
fi

echo "--------------------------------------------------------"
echo ""

# Optional Step: IP Forwarding
read -p "${MSG_FWD_PROMPT}" FWD_CHOICE
if [[ "${FWD_CHOICE}" == "y" || "${FWD_CHOICE}" == "Y" ]]; then
    routeadm -e ipv4-forwarding -u
    routeadm -e ipv6-forwarding -u
    echo "${MSG_FWD_DONE}"
    routeadm | egrep 'IPv4 forwarding|IPv6 forwarding'
fi

echo ""
echo "========================================================"
echo "${MSG_DONE}"
echo "========================================================"

#!/usr/bin/bash

set -euo pipefail

ZEROTIER_UPSTREAM_VERSION="1.16.2"
ZEROTIER_UPSTREAM_COMMIT="fc5c3ec22090b5b2a0f274e863651fe9ca489bf4"
RELEASE_TAG="v1.1.1"
RELEASE_BASE_URL="https://github.com/itinfra7/zerotier-one-omnios/releases/download/${RELEASE_TAG}"
SERVICE_FMRI="svc:/network/zerotier-one:default"
ZT_HOME="/var/lib/zerotier-one"
ZT_PREFIX="/opt/zerotier-one"
ZT_BIN="${ZT_PREFIX}/bin/zerotier-one"
BUILD_DIR="/var/tmp/zerotier-one-build.$$"
STAGE_DIR="/var/tmp/zerotier-one-stage.$$"
SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
ASSET_DIR=""
ASSUME_YES=0
ENABLE_FORWARDING="ask"
LANG_CHOICE=""
INSTALL_STARTED=0
BACKUP_DIR=""
IDENTITY_HASH_BEFORE=""
PREEXISTING_INSTALL=0

usage() {
    cat <<EOF
Usage: $0 [--yes] [--language en|ko] [--enable-forwarding|--no-forwarding]
          [--asset-dir DIR]
EOF
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --yes)
            ASSUME_YES=1
            ;;
        --language)
            [ "$#" -ge 2 ] || { usage >&2; exit 2; }
            LANG_CHOICE="$2"
            shift
            ;;
        --enable-forwarding)
            ENABLE_FORWARDING="yes"
            ;;
        --no-forwarding)
            ENABLE_FORWARDING="no"
            ;;
        --asset-dir)
            [ "$#" -ge 2 ] || { usage >&2; exit 2; }
            ASSET_DIR="$2"
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            usage >&2
            exit 2
            ;;
    esac
    shift
done

cleanup() {
    rm -rf "${BUILD_DIR}" "${STAGE_DIR}"
}

on_error() {
    typeset rc="$1"
    trap - ERR
    if [ "${INSTALL_STARTED}" -eq 1 ]; then
        restore_installation || true
    fi
    exit "${rc}"
}

trap cleanup EXIT HUP INT TERM
trap 'on_error $?' ERR

if [ "${EUID}" -ne 0 ]; then
    echo "This installer must run as root." >&2
    exit 1
fi

if [ "$(uname -s)" != "SunOS" ] || ! uname -v | grep -q '^omnios-r151054'; then
    echo "This release supports OmniOS r151054." >&2
    exit 1
fi

if [ -z "${LANG_CHOICE}" ]; then
    if [ "${ASSUME_YES}" -eq 1 ]; then
        LANG_CHOICE="en"
    else
        read -r -p "Select language / 언어를 선택하세요 (1: English, 2: 한국어) [1]: " answer
        [ "${answer:-1}" = "2" ] && LANG_CHOICE="ko" || LANG_CHOICE="en"
    fi
fi

case "${LANG_CHOICE}" in
    en|ko) ;;
    *) echo "Unsupported language: ${LANG_CHOICE}" >&2; exit 2 ;;
esac

if [ "${LANG_CHOICE}" = "ko" ]; then
    MSG_START="ZeroTier One ${ZEROTIER_UPSTREAM_VERSION} 설치 또는 업그레이드를 시작하시겠습니까? [y/N]: "
    MSG_BUILD="ZeroTier One ${ZEROTIER_UPSTREAM_VERSION} 소스를 준비하고 빌드합니다."
    MSG_INSTALL="기존 identity와 네트워크 설정을 보존하여 설치합니다."
    MSG_DONE="ZeroTier One ${ZEROTIER_UPSTREAM_VERSION} 설치 또는 업그레이드가 완료되었습니다."
    MSG_ROLLBACK="검증에 실패하여 이전 설치 파일을 복원합니다."
else
    MSG_START="Install or upgrade ZeroTier One ${ZEROTIER_UPSTREAM_VERSION}? [y/N]: "
    MSG_BUILD="Preparing and building ZeroTier One ${ZEROTIER_UPSTREAM_VERSION}."
    MSG_INSTALL="Installing while preserving the existing identity and network configuration."
    MSG_DONE="ZeroTier One ${ZEROTIER_UPSTREAM_VERSION} installation or upgrade completed."
    MSG_ROLLBACK="Validation failed; restoring the previous installation files."
fi

if [ "${ASSUME_YES}" -ne 1 ]; then
    read -r -p "${MSG_START}" answer
    case "${answer}" in y|Y) ;; *) exit 0 ;; esac
fi

install_packages() {
    typeset rc=0
    pkg install --accept developer/versioning/git developer/build/gnu-make developer/gcc14 || rc=$?
    if [ "${rc}" -ne 0 ] && [ "${rc}" -ne 4 ]; then
        return "${rc}"
    fi
}

stage_asset() {
    typeset name="$1"
    typeset destination="${STAGE_DIR}/${name}"

    if [ -n "${ASSET_DIR}" ]; then
        cp "${ASSET_DIR}/${name}" "${destination}"
    elif [ -f "${SCRIPT_DIR}/${name}" ]; then
        cp "${SCRIPT_DIR}/${name}" "${destination}"
    else
        wget -q "${RELEASE_BASE_URL}/${name}" -O "${destination}"
    fi
    /usr/bin/perl -pi -e 's/\r//g' "${destination}"
}

stop_service() {
    if svcs -H -o state "${SERVICE_FMRI}" >/dev/null 2>&1; then
        svcadm disable -st "${SERVICE_FMRI}" || true
    fi
    if [ -x "${ZT_PREFIX}/bin/zerotier-one-smf" ]; then
        "${ZT_PREFIX}/bin/zerotier-one-smf" stop || true
    fi
    pkill -TERM -f "^${ZT_BIN} -d ${ZT_HOME}$" >/dev/null 2>&1 || true
    sleep 2
    pkill -KILL -f "^${ZT_BIN} -d ${ZT_HOME}$" >/dev/null 2>&1 || true
}

backup_installation() {
    typeset timestamp
    timestamp="$(date +%Y%m%d-%H%M%S)"
    BACKUP_DIR="${ZT_HOME}/install-backups/${timestamp}"
    mkdir -p "${BACKUP_DIR}"
    chmod 700 "${ZT_HOME}/install-backups" "${BACKUP_DIR}"

    [ -f "${ZT_BIN}" ] && cp -p "${ZT_BIN}" "${BACKUP_DIR}/zerotier-one"
    [ -f "${ZT_PREFIX}/bin/zerotier-one-smf" ] && cp -p "${ZT_PREFIX}/bin/zerotier-one-smf" "${BACKUP_DIR}/zerotier-one-smf"
    [ -f /var/svc/manifest/network/zerotier-one.xml ] && cp -p /var/svc/manifest/network/zerotier-one.xml "${BACKUP_DIR}/zerotier-one.xml"
    return 0
}

restore_installation() {
    echo "${MSG_ROLLBACK}" >&2
    stop_service
    if [ -n "${BACKUP_DIR}" ] && [ -f "${BACKUP_DIR}/zerotier-one" ]; then
        cp -p "${BACKUP_DIR}/zerotier-one" "${ZT_BIN}"
        [ -f "${BACKUP_DIR}/zerotier-one-smf" ] && cp -p "${BACKUP_DIR}/zerotier-one-smf" "${ZT_PREFIX}/bin/zerotier-one-smf"
        [ -f "${BACKUP_DIR}/zerotier-one.xml" ] && cp -p "${BACKUP_DIR}/zerotier-one.xml" /var/svc/manifest/network/zerotier-one.xml
        svccfg import /var/svc/manifest/network/zerotier-one.xml
        svcadm enable -r "${SERVICE_FMRI}"
    else
        svcadm disable -s "${SERVICE_FMRI}" >/dev/null 2>&1 || true
        svccfg delete -f "${SERVICE_FMRI}" >/dev/null 2>&1 || true
        rm -f /opt/ooce/bin/zerotier-one /opt/ooce/bin/zerotier-cli /opt/ooce/bin/zerotier-idtool
        rm -f /var/svc/manifest/network/zerotier-one.xml
        rm -rf "${ZT_PREFIX}"
        if [ "${PREEXISTING_INSTALL}" -eq 0 ]; then
            rm -rf "${ZT_HOME}"
        fi
    fi
}

verify_installation() {
    typeset attempt=0
    typeset version

    while [ "${attempt}" -lt 90 ]; do
        if [ "$(svcs -H -o state "${SERVICE_FMRI}" 2>/dev/null || true)" = "online" ] && \
            PATH="/usr/bin:/usr/sbin:/opt/ooce/bin" zerotier-cli info >/dev/null 2>&1; then
            version="$("${ZT_BIN}" -v 2>/dev/null || true)"
            [ "${version}" = "${ZEROTIER_UPSTREAM_VERSION}" ] && return 0
        fi
        attempt=$((attempt + 1))
        sleep 1
    done
    return 1
}

if [ -e "${ZT_PREFIX}" ] || [ -e "${ZT_HOME}" ] || \
    [ -e /var/svc/manifest/network/zerotier-one.xml ]; then
    PREEXISTING_INSTALL=1
fi

install_packages
mkdir -p "${BUILD_DIR}" "${STAGE_DIR}" "${ZT_HOME}"
chmod 700 "${ZT_HOME}"

if [ -f "${ZT_HOME}/identity.public" ]; then
    IDENTITY_HASH_BEFORE="$(digest -a sha256 "${ZT_HOME}/identity.public")"
fi

stage_asset omnios-zerotier-one.patch
stage_asset zerotier-one-smf
stage_asset zerotier-one.xml

echo "${MSG_BUILD}"
git init -q "${BUILD_DIR}/source"
git -C "${BUILD_DIR}/source" remote add origin https://github.com/zerotier/ZeroTierOne.git
git -C "${BUILD_DIR}/source" fetch --depth 1 origin \
    "refs/tags/${ZEROTIER_UPSTREAM_VERSION}:refs/tags/${ZEROTIER_UPSTREAM_VERSION}"
git -C "${BUILD_DIR}/source" checkout -q --detach "${ZEROTIER_UPSTREAM_COMMIT}"
if [ "$(git -C "${BUILD_DIR}/source" rev-parse HEAD)" != "${ZEROTIER_UPSTREAM_COMMIT}" ]; then
    echo "Unexpected upstream commit." >&2
    exit 1
fi
patch --batch --forward -d "${BUILD_DIR}/source" -p1 < "${STAGE_DIR}/omnios-zerotier-one.patch"
PATH="/usr/bin:/usr/sbin:/opt/gcc-14/bin:/usr/gnu/bin:${PATH}" \
    gmake -C "${BUILD_DIR}/source" OSTYPE=OpenBSD CC=gcc CXX=g++ -j1 one
cp "${BUILD_DIR}/source/zerotier-one" "${STAGE_DIR}/zerotier-one"
chmod 755 "${STAGE_DIR}/zerotier-one" "${STAGE_DIR}/zerotier-one-smf"

echo "${MSG_INSTALL}"
backup_installation
stop_service
INSTALL_STARTED=1

mkdir -p "${ZT_PREFIX}/bin" /opt/ooce/bin /var/svc/manifest/network
cp "${STAGE_DIR}/zerotier-one" "${ZT_BIN}.new"
mv -f "${ZT_BIN}.new" "${ZT_BIN}"
cp "${STAGE_DIR}/zerotier-one-smf" "${ZT_PREFIX}/bin/zerotier-one-smf"
cp "${STAGE_DIR}/zerotier-one.xml" /var/svc/manifest/network/zerotier-one.xml

ln -sf "${ZT_BIN}" "${ZT_PREFIX}/bin/zerotier-cli"
ln -sf "${ZT_BIN}" "${ZT_PREFIX}/bin/zerotier-idtool"
ln -sf "${ZT_BIN}" /opt/ooce/bin/zerotier-one
ln -sf "${ZT_BIN}" /opt/ooce/bin/zerotier-cli
ln -sf "${ZT_BIN}" /opt/ooce/bin/zerotier-idtool

svccfg import /var/svc/manifest/network/zerotier-one.xml
svcadm enable -r "${SERVICE_FMRI}"

if ! verify_installation; then
    restore_installation
    exit 1
fi

if [ -n "${IDENTITY_HASH_BEFORE}" ] && [ "$(digest -a sha256 "${ZT_HOME}/identity.public")" != "${IDENTITY_HASH_BEFORE}" ]; then
    restore_installation
    echo "ZeroTier identity changed unexpectedly." >&2
    exit 1
fi

rm -rf /opt/ZeroTierOne
mv "${BUILD_DIR}/source" /opt/ZeroTierOne
rmdir "${BUILD_DIR}"
BUILD_DIR="/var/tmp/zerotier-one-build-complete.$$"

if [ "${ENABLE_FORWARDING}" = "ask" ] && [ "${ASSUME_YES}" -eq 1 ]; then
    ENABLE_FORWARDING="no"
elif [ "${ENABLE_FORWARDING}" = "ask" ]; then
    read -r -p "Enable IPv4 and IPv6 forwarding? [y/N]: " answer
    case "${answer}" in y|Y) ENABLE_FORWARDING="yes" ;; *) ENABLE_FORWARDING="no" ;; esac
fi

if [ "${ENABLE_FORWARDING}" = "yes" ]; then
    routeadm -e ipv4-forwarding -u
    routeadm -e ipv6-forwarding -u
fi

INSTALL_STARTED=0
echo "${MSG_DONE}"
PATH="/usr/bin:/usr/sbin:/opt/ooce/bin" zerotier-cli info

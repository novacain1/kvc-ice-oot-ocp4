#!/bin/bash

export DDP_PKG="ice_comms-1.3.30.0"
export ICE_PKG_ROOT="/var"

set -e

usage() {
    prog=$(basename "$0")
    cat <<-EOM
    Build MachineConfig for ice driver

    Usage:
        $prog command [arguments]
            build /path/entitlements    -- Build cm.yaml
            headers /path/entitlements   -- List available kernel-headers
                
        /path/entitlements -- Directory containing certs/keys to enable privileged kernel deploys.
EOM
}

build_ice_kmod() {
    local entitlements="$1"

    if [ ! -d "$entitlements" ]; then
        printf >&2 "Cannot access entitlements directory: %s\n" "$entitlements"
        exit 1
    fi

    printf "Reading certs from: %s\n" "$entitlements"

    mkdir -p build

    FAKEROOT=$(mktemp -d)

    mkdir -p "${FAKEROOT}"/etc/rhsm

    cp ./rhsm.conf "${FAKEROOT}"/etc/rhsm

    mkdir -p "${FAKEROOT}"/etc/pki/entitlement

    for f in "${entitlements}"/*.pem; do
        base=${f##*/}
        cp "$f" "${FAKEROOT}/etc/pki/entitlement/${base}"
    done

    # tar -czf subs.tar.gz /etc/pki/entitlement/ /etc/rhsm/ /etc/yum.repos.d/redhat.repo
    # tar -x -C "${FAKEROOT}" -f subs.tar.gz
    # rm subs.tar.gz

    if [ ! -d build/kmods-via-containers ]; then
        (
            cd build
            git clone https://github.com/openshift-psap/kmods-via-containers
        )
    fi

    (cd build/kmods-via-containers && git pull --no-rebase &&
        make install DESTDIR="${FAKEROOT}"/usr/local CONFDIR="${FAKEROOT}"/etc/)

    if [ ! -d build/kvc-ice-kmod ]; then
        (
            cd build
            git clone https://github.com/novacain1/kvc-ice-kmod.git
        )
    fi

    (cd build/kvc-ice-kmod && git pull --no-rebase &&
        make install DESTDIR="${FAKEROOT}"/usr/local CONFDIR="${FAKEROOT}"/etc/)

    if [ ! -d build/filetranspiler ]; then
        (
            cd build
            git clone https://github.com/ashcrow/filetranspiler
        )
    fi

    (cd build/filetranspiler && git checkout 1.1.3)

    ./build/filetranspiler/filetranspile -i ./baseconfig.ign -f "${FAKEROOT}" --format=yaml \
        --dereference-symlinks | sed 's/^/     /' | (cat mc-base.yaml -) >ice-mc.yaml
}

list_kernel_headers() {
    local entitlement="$1"

    podman run --rm -ti --mount type=bind,source="$entitlement",target=/etc/pki/entitlement/entitlement.pem \
        --mount type=bind,source="$entitlement",target=/etc/pki/entitlement/entitlement-key.pem \
        registry.access.redhat.com/ubi8:latest bash -c "dnf search kernel-devel --showduplicates"
}

build_ice_pkg() {

    mkdir -p build

    FAKEROOT=$(mktemp -d)

    (
        # The URL to the comms package associated with the version of the ice driver
        # is set in the kvc-ice-kmod repo, ice-kmod.conf file
        #
        mkdir -p build/package

        # shellcheck disable=SC1091
        source build/kvc-ice-kmod/ice-kmod.conf

        package_zip_file=$(basename "$KMOD_SOFTWARE_EXTRA_1")

        cd build/package

        if [ ! -e "$package_zip_file" ]; then
            wget -O $KMOD_SOFTWARE_EXTRA_NAME "$KMOD_SOFTWARE_EXTRA_1"
	    unzip $KMOD_SOFTWARE_EXTRA_NAME
        fi

        mkdir -p "${FAKEROOT}/${ICE_PKG_ROOT}/lib/firmware/updates/intel/ice/ddp/"
        unzip "${DDP_PKG}.zip" -d "${FAKEROOT}/${ICE_PKG_ROOT}/lib/firmware/updates/intel/ice/ddp/"
        rm -fv "${FAKEROOT}/${ICE_PKG_ROOT}/lib/firmware/updates/intel/ice/ddp/ice.pkg"
        package_file="${DDP_PKG}.pkg"
        mv -f "${FAKEROOT}/${ICE_PKG_ROOT}/lib/firmware/updates/intel/ice/ddp/$package_file" "${FAKEROOT}/${ICE_PKG_ROOT}/lib/firmware/updates/intel/ice/ddp/ice.pkg"
    )

    if [ ! -d build/filetranspiler ]; then
        (
            cd build
            git clone https://github.com/ashcrow/filetranspiler
        )
    fi

    (cd build/filetranspiler && git checkout 1.1.3)

    ./build/filetranspiler/filetranspile -i ./baseconfig-pkg.ign -f "${FAKEROOT}" --format=yaml \
        --dereference-symlinks | sed 's/^/     /' | (cat mc-pkg-base.yaml -) >ice-pkg-mc.yaml
}

list_kernel_headers() {
    local entitlement="$1"

    podman run --rm -ti --mount type=bind,source="$entitlement",target=/etc/pki/entitlement/entitlement.pem \
        --mount type=bind,source="$entitlement",target=/etc/pki/entitlement/entitlement-key.pem \
        registry.access.redhat.com/ubi8:latest bash -c "dnf search kernel-devel --showduplicates"
}

while getopts ":h" opt; do
    case ${opt} in
    h)
        usage
        exit 0
        ;;
    \?)
        echo "Invalid Option: -$OPTARG" 1>&2
        exit 1
        ;;
    esac
done
shift $((OPTIND - 1))

if [ "$#" -gt 0 ]; then
    COMMAND=$1
    shift
else
    COMMAND="build"
fi

case "$COMMAND" in
build)
    if [ "$#" -lt 1 ]; then
        printf >&2 "%s missing 1 arg\n" "$PROGRAM"
        usage
        exit 1
    fi
    build_ice_kmod "$1"
    build_ice_pkg
    ;;
headers)
    if [ "$#" -lt 1 ]; then
        printf >&2 "%s requires 1 arg\n" "$PROGRAM"
        usage
        exit 1
    fi
    list_kernel_headers "$1"
    ;;
*)
    echo "Unknown command: ${COMMAND}"
    usage
    ;;
esac

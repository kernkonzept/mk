#!/usr/bin/env bash

L4IMAGE="${OBJ_BASE}/source/tool/bin/l4image"

post_l4image_hook() {
    local mkimage="${TARGET_MKIMAGE:-${TARGET_IMAGE%.raw}.${IMAGEBUILDER_MKIMAGE_SUFFIX}}"
    local rawimage="${TARGET_IMAGE}"

    source <("$MAKECONF" "$OBJ_BASE" BOOTSTRAP_UIMAGE_COMPRESSION)

    # Read load address from rawimage
    local loadaddr="$($L4IMAGE -i "${rawimage}" attr --get l4i:loadaddr)"

    : ${MAKECONF_BOOTSTRAP_UIMAGE_COMPRESSION:=none}

    local mkimage_arch
    case "${MAKECONF_ARCH}" in
        mips)
            case "${MAKECONF_CPU}" in
                32*)
                    mkimage_arch=mips
                    ;;
                64*)
                    mkimage_arch=mips64
                    ;;
            esac
            ;;
        *)
            mkimage_arch=${MAKECONF_ARCH}
            ;;
    esac

    echo

    case "${MAKECONF_BOOTSTRAP_UIMAGE_COMPRESSION}" in
        gzip)
            gzip -c9 "${rawimage}" > "${rawimage}.gzip" || exit $?
            rawimage="${rawimage}.gzip"
            ;;
        bzip2)
            bzip2 -c9 "${rawimage}" > "${rawimage}.bzip2" || exit $?
            rawimage="${rawimage}.bzip2"
            ;;
        none)
            ;;
        *)
            echo "BOOTSTRAP_UIMAGE_COMPRESSION: Unknown compression: ${MAKECONF_BOOTSTRAP_UIMAGE_COMPRESSION}" >&2
            exit 1
            ;;
    esac

    echo

    local ret;

    mkimage ${IMAGEBUILDER_MKIMAGE_FLAGS} \
            -a "${loadaddr}" \
            -e "${loadaddr}" \
            -A "${mkimage_arch}" \
            -n "L4Re Image @ $(LC_ALL=C date)" \
            -C "${MAKECONF_BOOTSTRAP_UIMAGE_COMPRESSION}" \
            -d "$rawimage" \
            "$mkimage"; ret=$?

    if [[ $ret -ne 0 ]]; then exit $ret; fi

    TARGET_IMAGE="$mkimage"
}

source "$(dirname "$0")/rawimage"

#!/usr/bin/env bash

L4IMAGE="${OBJ_BASE}/source/tool/bin/l4image"

post_l4image_hook() {
    local mkimage="${TARGET_MKIMAGE:-${TARGET_IMAGE%.raw}.${IMAGEBUILDER_MKIMAGE_SUFFIX}}"
    local rawimage="${TARGET_IMAGE}"

    source <("$MAKECONF" "$OBJ_BASE" BOOTSTRAP_UIMAGE_COMPRESSION \
                                     BOOTSTRAP_UIMAGE_LOAD_ADDRESS)

    : ${BOOTSTRAP_UIMAGE_LOAD_ADDRESS:=${MAKECONF_BOOTSTRAP_UIMAGE_LOAD_ADDRESS}}

    if [[ -z "${BOOTSTRAP_UIMAGE_LOAD_ADDRESS}" ]]; then
        # Read load address from rawimage
        BOOTSTRAP_UIMAGE_LOAD_ADDRESS="$($L4IMAGE -i "${rawimage}" attr --get l4i:loadaddr)"
    fi

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
        lz4)
            lz4 -9 "${rawimage}" "${rawimage}.lz4" || exit $?
            rawimage="${rawimage}.lz4"
            ;;
        lzma)
            lzma -9 "${rawimage}" "${rawimage}.lzma" || exit $?
            rawimage="${rawimage}.lzma"
            ;;
        lzo)
            lzo -9 -c "${rawimage}" > "${rawimage}.lzo" || exit $?
            rawimage="${rawimage}.lzo"
            ;;
        zstd)
            zstd -19 "${rawimage}" -o "${rawimage}.zstd" || exit $?
            rawimage="${rawimage}.zstd"
            ;;
        none)
            ;;
        *)
            echo "BOOTSTRAP_UIMAGE_COMPRESSION: Unknown compression: ${MAKECONF_BOOTSTRAP_UIMAGE_COMPRESSION}" >&2
            exit 1
            ;;
    esac

    echo

    if [[ -n "${BOOTSTRAP_ITB_DTB}" ]]; then
        BOOTSTRAP_ITB_DTB="$(resolve_module "${BOOTSTRAP_ITB_DTB}")"
        IMAGEBUILDER_MKIMAGE_FLAGS+=( "-b" "${BOOTSTRAP_ITB_DTB}" )
    fi

    local ret;

    mkimage "${IMAGEBUILDER_MKIMAGE_FLAGS[@]}" \
            -a "${BOOTSTRAP_UIMAGE_LOAD_ADDRESS}" \
            -e "${BOOTSTRAP_UIMAGE_LOAD_ADDRESS}" \
            -A "${mkimage_arch}" \
            -n "L4Re Image @ $(LC_ALL=C date)" \
            -C "${MAKECONF_BOOTSTRAP_UIMAGE_COMPRESSION}" \
            -d "$rawimage" \
            "$mkimage"; ret=$?

    if [[ $ret -ne 0 ]]; then exit $ret; fi

    TARGET_IMAGE="$mkimage"
}

source "$(dirname "$0")/rawimage"

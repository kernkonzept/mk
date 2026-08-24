# vim:se ft=bash:
# Abstract: This script builds a bootstrap image using the l4image tool. First
# it runs _platform_rebuild.pl in order to ensure the present bootstrap image
# matches platform, ram base and efi support. Then it utilizes the l4image tool
# in tool/bin to create a final bootstrap image from the provided modules.list.

# TODO: Currently this script is expected run into trouble when attempting to
# build images for different platforms or rambases in parallel.

L4IMAGE="${OBJ_BASE}/source/tool/bin/l4image"
MAKECONF="${OBJ_BASE}/source/tool/bin/makeconf"

# Sets MAKECONF_{ARCH|CPU|...}
source <("$MAKECONF" "$OBJ_BASE" \
                     ARCH CPU BITS \
                     OBJCOPY \
                     QEMU_PATH QEMU_OPTIONS \
                     MODULE_SEARCH_PATH BUILDDIR_SEARCHPATH)

L4IMAGE_SEARCHPATH="${MODULE_SEARCH_PATH}:${SEARCHPATH}:${MAKECONF_MODULE_SEARCH_PATH}:${MAKECONF_BUILDDIR_SEARCHPATH}"

resolve_module() {
    if [[ "$1" == /* ]]; then
        echo "$1"
        return
    fi

    local -a paths=( $(sed -e 's/:/ /g' <<< "$L4IMAGE_SEARCHPATH") )

    for path in "${paths[@]}"; do
        if [[ -f "${path}/$1" ]]; then
            echo "${path}/$1"
            echo "Found ${path}/$1" >&2
            return
        fi
    done
}

# Detect selected system
: ${ARCH:=${MAKECONF_ARCH}}; export ARCH
: ${CPU:=${MAKECONF_CPU}}; export CPU
: ${BITS:=${MAKECONF_BITS}}; export BITS
: ${MAKE:=make}
: ${OBJCOPY:=${MAKECONF_OBJCOPY}}; export OBJCOPY
L4_SYSTEM="${ARCH}_${CPU}"

# Select base image and target image
: ${ENTRY:=${E}}; export ENTRY
BASE_IMAGE="${OBJ_BASE}/bin/${L4_SYSTEM}/plain/${BASE_IMAGE_FILENAME:-bootstrap}"

: ${TARGET_IMAGE_PATH:=${BOOTSTRAP_OUTPUT_DIR:-${OBJ_BASE}/images}}
: ${TARGET_IMAGE="${TARGET_IMAGE_PATH}/${TARGET_IMAGE_FILENAME//entry/${ENTRY}}"}

# Make sure there is no such image
if [[ -L "$TARGET_IMAGE" || -e "$TARGET_IMAGE" ]]; then
    if ! rm "$TARGET_IMAGE"; then
        echo "Could not cleanup target image: $TARGET_IMAGE" >&2
        exit 1
    fi
fi

# Check if we need to trigger the build system due to RAM_BASE/PLATFORM change
"$(dirname $0)/_platform_rebuild.pl" "$BASE_IMAGE" || exit 1

# Make sure the target directory exists.
mkdir -p "$(dirname "$TARGET_IMAGE")"

qemu_cmd="${MAKECONF_QEMU_PATH} ${MAKECONF_QEMU_OPTIONS}"

if ! grep -q "L4IMAGE_FILE" <<< "$qemu_cmd"; then
    qemu_cmd+=" -kernel \$L4IMAGE_FILE"
fi

# Create a new image
$L4IMAGE -i "$BASE_IMAGE" -o "$TARGET_IMAGE" --verbose create \
     --entry "${ENTRY}" \
     --modules-list-file "${MODULES_LIST}" \
     --search-path "$L4IMAGE_SEARCHPATH" \
     --set-attr "l4i:QEMUcmd" "${qemu_cmd}" \
     ${L4IMAGE_EXTRA_OPTS}
ret=$?

if [[ $ret -ne 0 ]]; then exit $ret; fi

if [[ "$(type -t post_l4image_hook)" == "function" ]]; then
    post_l4image_hook; ret=$?
fi

if [[ $ret -ne 0 ]]; then exit $ret; fi

echo
echo "Generated image: $TARGET_IMAGE"
echo

if [[ -n "$POST_IMAGE_CMD" ]]; then
    $MAKE -f <(echo -e '.PHONY: p\np:\n\t$(call POST_IMAGE_CMD,$(TARGET_IMAGE))') -C "${OBJ_BASE}" TARGET_IMAGE=$TARGET_IMAGE; ret=$?
fi

if [[ $ret -ne 0 ]]; then exit $ret; fi

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
                     ARCH CPU \
                     QEMU_PATH QEMU_OPTIONS \
                     MODULE_SEARCH_PATH BUILDDIR_SEARCHPATH)

# Detect selected system
: ${ARCH:=${MAKECONF_ARCH}}
: ${CPU:=${MAKECONF_CPU}}
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

L4IMAGE_SEARCHPATH="${MODULE_SEARCH_PATH}:${SEARCHPATH}:${MAKECONF_MODULE_SEARCH_PATH}:${MAKECONF_BUILDDIR_SEARCHPATH}"

# Create a new image
$L4IMAGE -i "$BASE_IMAGE" -o "$TARGET_IMAGE" create \
     --entry "${ENTRY}" \
     --modules-list-file "${MODULES_LIST}" \
     --search-path "$L4IMAGE_SEARCHPATH" \
     --set-attr "l4i:QEMUcmd" "${MAKECONF_QEMU_PATH} ${MAKECONF_QEMU_OPTIONS} -kernel \$L4IMAGE_FILE"
ret=$?

if [[ $ret -eq 0 ]] ; then
    echo
    echo "Generated image: $TARGET_IMAGE"
    echo
fi

if [[ $ret -eq 0 && -n "$POST_IMAGE_CMD" ]]; then
    make -f <(echo -e '.PHONY: p\np:\n\t$(call POST_IMAGE_CMD,$(TARGET_IMAGE))') -C "${OBJ_BASE}" TARGET_IMAGE=$TARGET_IMAGE; ret=$?
fi

exit $ret

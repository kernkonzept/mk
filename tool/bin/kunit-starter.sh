#! /usr/bin/env bash

# Copyright (C) 2021 Kernkonzept GmbH.
# Author(s): Philipp Eppelt <philipp.eppelt@kernkonzept.com>

function print_usage () {
cat << EOF
Start a single kernel test.

Usage:
  kunit-starter.sh --test=<> [--obj-base=<>] [-v] [*]
  kunit-starter.sh <path/to/kernel/test/binary>

Parameters:
  --test=      Path to the kernel test binary.
  --obj-base=  Path of the L4Re build directory. If this script is executed
               from an L4Re build directory, this option can be omitted.
  -v           Print information during script execution (forwarded to the
               test starter).
  [*]          Every unknown option is forwarded to the test starter.
EOF
}

# default initialize variables for command line arguments
test_binary=""
obj_base="$(pwd)"
verbose=""
test_params=""

# parse command line
for i in "$@"; do
  case "$i" in
    --usage|-h|--help)
      print_usage
      exit 0
      ;;

    --test=*)
      test_binary=${i#*=}
      ;;

    --obj-base=*)
      obj_base=${i#*=}
      ;;

    -v)
      verbose=1
      test_params+=${i}
      ;;

    *)
      test_params+="${i}"
      ;;
  esac;
done;

# Comfort feature: If no command line switch is given but a single parameter,
# use it as test_binary.
if [[ -z "${test_binary}" && $# == 1 ]]; then
  test_binary="$1"
fi

# work on absolute paths; assume current directory as relative path base.
if [[ -n "${test_binary}" && ${test_binary:0:1} != "/" ]]; then
  test_binary="$(pwd)/${test_binary}"
fi

if [[ ${obj_base:0:1} != "/" ]]; then
  obj_base="$(pwd)/${obj_base}"
fi

# Check provided paths
if [[ -z "${test_binary}" ]]; then
  echo "Please provide the path to the kernel test binary."
  exit 1
fi

if [[ ! -h "${obj_base}"/source  || ! -r "${obj_base}"/.config ]]; then
  echo "Please provide a L4Re build directory path."
  exit 1
fi

test_file=${test_binary##*/}
test_file_path=${test_binary%/${test_file}}
test_conf_file=${test_binary/test_/config_}

if [[ ${verbose} ]]; then
  echo "test_binary=${test_binary} test_file=${test_file}" \
    "test_file_path=${test_file_path} obj_base=${obj_base}" \
    "test_conf_file=${test_conf_file}"
fi

# Prepare environment
set -a
L4DIR=$(realpath "${obj_base}/source")
OBJ_BASE="${obj_base}"
ARCH=$("${obj_base}"/source/tool/kconfig/scripts/config \
  --file "${obj_base}"/.config --state CONFIG_BUILD_ARCH)

SEARCHPATH="${test_file_path}"${SEARCHPATH:+:${SEARCHPATH}}
KERNEL="${test_binary}"
TEST_KERNEL_UNIT=1

TEST_TAP_PLUGINS_CMDLINE="${TEST_TAP_PLUGINS}"
TEST_TAP_PLUGINS=

[[ -f "$test_conf_file" ]] && source "$test_conf_file"
: ${TEST_TAP_PLUGINS:=TAPOutput}
TEST_TAP_PLUGINS+=" ${TEST_TAP_PLUGINS_CMDLINE}"

TEST_TESTFILE="${test_file}"
TEST_DESCRIPTION="kunit_test ${TEST_TESTFILE}"
: "${TEST_STARTER:=${L4DIR}/tool/bin/default-test-starter}"

# if not called from the L4Re build dir and if O= is not set, we explicitly
# set O. Otherwise, make qemu fails.
if [[ "$(pwd)" != "${obj_base}" ]]; then
  : "${O:=${obj_base}}"
fi
set +a

exec "$TEST_STARTER" "${test_params}"

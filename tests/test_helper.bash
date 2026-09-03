#!/usr/bin/env bash
#
# Shared setup for the bats suite.

# Put the fake docker CLI ahead of anything real on PATH and point it at a
# scenario fixture. Call as: setup_stub <fixture-basename>
setup_stub() {
  export DSD_STUB_DIR="${BATS_TEST_TMPDIR}/stub"
  export DSD_STUB_SCENARIO="${BATS_TEST_DIRNAME}/fixtures/${1}.services"
  mkdir -p "${DSD_STUB_DIR}"
  export PATH="${BATS_TEST_DIRNAME}/helpers/bin:${PATH}"

  if [ ! -f "${DSD_STUB_SCENARIO}" ]; then
    echo "no such fixture: ${DSD_STUB_SCENARIO}" >&2
    return 1
  fi
}

# Everything the script under test asked docker to do, one invocation per line.
stub_calls() {
  cat "${DSD_STUB_DIR}/calls.log" 2>/dev/null || true
}

# Absolute path to a script under scripts/.
script_path() {
  echo "${BATS_TEST_DIRNAME}/../scripts/${1}"
}

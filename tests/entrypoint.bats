#!/usr/bin/env bats
#
# Behaviour of scripts/docker-entrypoint.sh.
#
# The script guards its deploy flow behind a BASH_SOURCE check, so `source`
# here defines the functions without connecting to anything. The required-input
# checks are exercised end-to-end instead: they all run before the first SSH
# call, so the script exits on its own before touching the network.

load test_helper

setup() {
  ENTRYPOINT="$(script_path docker-entrypoint.sh)"
  setup_stub converged
}

# Run the entrypoint with a controlled environment. Every VAR=value argument is
# passed through; nothing else from the test environment leaks in except PATH.
run_entrypoint() {
  run env -i \
    PATH="${PATH}" \
    HOME="${BATS_TEST_TMPDIR}" \
    DSD_STUB_DIR="${DSD_STUB_DIR}" \
    DSD_STUB_SCENARIO="${DSD_STUB_SCENARIO}" \
    "$@" \
    bash "${ENTRYPOINT}"
}

# --- sourcing -----------------------------------------------------------------

@test "sourcing defines the functions without running a deploy" {
  # shellcheck source=/dev/null
  source "${ENTRYPOINT}"
  run type -t configure_env_file
  [ "$status" -eq 0 ]
  [ "$output" = "function" ]
  # Nothing should have been asked of docker.
  [ -z "$(stub_calls)" ]
}

# --- required inputs ----------------------------------------------------------

@test "remote_host is required" {
  run_entrypoint
  [ "$status" -eq 1 ]
  [[ "$output" == *"Input remote_host is required!"* ]]
}

@test "remote_user is required" {
  run_entrypoint REMOTE_HOST=swarm.example.com
  [ "$status" -eq 1 ]
  [[ "$output" == *"Input remote_user is required!"* ]]
}

@test "remote_private_key is required" {
  run_entrypoint REMOTE_HOST=swarm.example.com REMOTE_USER=deploy
  [ "$status" -eq 1 ]
  [[ "$output" == *"Input private_key is required!"* ]]
}

@test "stack_file is required" {
  run_entrypoint REMOTE_HOST=swarm.example.com REMOTE_USER=deploy \
    REMOTE_PRIVATE_KEY=key
  [ "$status" -eq 1 ]
  [[ "$output" == *"Input stack_file is required!"* ]]
}

@test "stack_file must exist" {
  run_entrypoint REMOTE_HOST=swarm.example.com REMOTE_USER=deploy \
    REMOTE_PRIVATE_KEY=key STACK_FILE=/nope/missing.yml
  [ "$status" -eq 1 ]
  [[ "$output" == *"/nope/missing.yml does not exist."* ]]
}

@test "stack_name is required" {
  touch "${BATS_TEST_TMPDIR}/stack.yml"
  run_entrypoint REMOTE_HOST=swarm.example.com REMOTE_USER=deploy \
    REMOTE_PRIVATE_KEY=key STACK_FILE="${BATS_TEST_TMPDIR}/stack.yml"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Input stack_name is required!"* ]]
}

# --- container registry login -------------------------------------------------

@test "skips login when no credentials are given (issue #4)" {
  run_entrypoint
  [[ "$output" == *"Container Registry: No authentication provided"* ]]
  [[ "$(stub_calls)" != *"login"* ]]
}

@test "logs in when credentials are given" {
  run_entrypoint USERNAME=someone PASSWORD=secret REGISTRY=ghcr.io
  [[ "$output" == *"Container Registry: Logged in ghcr.io as someone"* ]]
  [[ "$(stub_calls)" == *"login ghcr.io -u someone --password-stdin"* ]]
}

@test "aborts when login fails" {
  run_entrypoint USERNAME=someone PASSWORD=secret REGISTRY=ghcr.io \
    DSD_STUB_LOGIN_FAILS=1
  [ "$status" -eq 1 ]
  [[ "$output" == *"Login to ghcr.io as someone failed"* ]]
}

@test "a preset DEBUG value does not abort the script" {
  # `[ -z ${DEBUG+x} ] && export DEBUG="0"` runs under `set -e`; make sure a
  # caller-supplied DEBUG does not make that line terminate the run. The
  # action always passes DEBUG, so this path is the normal one.
  run_entrypoint DEBUG=1
  [ "$status" -eq 1 ]
  [[ "$output" == *"Verbose logging"* ]]
  [[ "$output" == *"Input remote_host is required!"* ]]
}

# --- env_file parsing ---------------------------------------------------------

# Source the script and run configure_env_file against a given ENV_FILE body,
# printing the resulting value of one variable.
export_from_env_file() {
  local body="$1" var="$2"
  run env -i PATH="${PATH}" HOME="${BATS_TEST_TMPDIR}" \
    ENV_FILE="${body}" WANT="${var}" \
    bash -c "
      source '${ENTRYPOINT}'
      ENV_FILE_DEST=\"\${HOME}/.env\"
      configure_env_file >/dev/null 2>&1
      printf '%s' \"\${!WANT}\"
    "
}

@test "env_file exports a simple value" {
  export_from_env_file 'DB_USER=plone' DB_USER
  [ "$status" -eq 0 ]
  [ "$output" = "plone" ]
}

@test "env_file exports several values" {
  export_from_env_file $'DB_USER=plone\nDB_NAME=site' DB_NAME
  [ "$status" -eq 0 ]
  [ "$output" = "site" ]
}

@test "env_file ignores comments and blank lines" {
  export_from_env_file $'# a comment\n\nDB_USER=plone' DB_USER
  [ "$status" -eq 0 ]
  [ "$output" = "plone" ]
}

@test "env_file keeps an = inside the value" {
  export_from_env_file 'DSN=key=value' DSN
  [ "$status" -eq 0 ]
  [ "$output" = "key=value" ]
}

@test "env_file exports a value containing spaces (issue #21)" {
  export_from_env_file 'SOLR_JAVA_MEM=-Xms1536m -Xmx1536m' SOLR_JAVA_MEM
  [ "$status" -eq 0 ]
  [ "$output" = "-Xms1536m -Xmx1536m" ]
}

@test "env_file keeps quotes in a value verbatim (issue #21)" {
  export_from_env_file 'GREETING="hello world"' GREETING
  [ "$status" -eq 0 ]
  [ "$output" = '"hello world"' ]
}

@test "env_file preserves several space-bearing values in one file (issue #21)" {
  export_from_env_file $'JAVA_OPTS=-Xms1g -Xmx2g\nDB_USER=plone' JAVA_OPTS
  [ "$status" -eq 0 ]
  [ "$output" = "-Xms1g -Xmx2g" ]
}

@test "env_file still exports later keys after a space-bearing value" {
  export_from_env_file $'JAVA_OPTS=-Xms1g -Xmx2g\nDB_USER=plone' DB_USER
  [ "$status" -eq 0 ]
  [ "$output" = "plone" ]
}

@test "env_file preserves a trailing space in a value" {
  export_from_env_file 'GREETING=hello ' GREETING
  [ "$status" -eq 0 ]
  [ "$output" = "hello " ]
}

@test "env_file rejects a line that is not NAME=VALUE" {
  # Issue #3 reported passing a path (".env") and getting an opaque
  # "not a valid identifier" error from export. Fail with a clear message.
  run env -i PATH="${PATH}" HOME="${BATS_TEST_TMPDIR}" ENV_FILE=".env" \
    bash -c "
      source '${ENTRYPOINT}'
      ENV_FILE_DEST=\"\${HOME}/.env\"
      configure_env_file
    "
  [ "$status" -eq 1 ]
  [[ "$output" == *"'.env' is not in NAME=VALUE format"* ]]
}

@test "env_file rejects a name with a hyphen" {
  run env -i PATH="${PATH}" HOME="${BATS_TEST_TMPDIR}" ENV_FILE="MY-VAR=1" \
    bash -c "
      source '${ENTRYPOINT}'
      ENV_FILE_DEST=\"\${HOME}/.env\"
      configure_env_file
    "
  [ "$status" -eq 1 ]
  [[ "$output" == *"is not in NAME=VALUE format"* ]]
}

# --- env_file_path (issue #3) -------------------------------------------------

# Write a file with the given content, run configure_env_file_path against it,
# and print the resulting value of one variable.
#
# The value is bracketed because bats strips trailing newlines from $output,
# which would hide a value that wrongly kept one.
export_from_env_file_path() {
  local body="$1" var="$2"
  local file="${BATS_TEST_TMPDIR}/vars.env"
  printf '%s\n' "${body}" > "${file}"
  run env -i PATH="${PATH}" HOME="${BATS_TEST_TMPDIR}" \
    ENV_FILE_PATH="${file}" WANT="${var}" \
    bash -c "
      source '${ENTRYPOINT}'
      configure_env_file_path >/dev/null 2>&1
      printf '[%s]' \"\${!WANT}\"
    "
}

@test "env_file_path exports a value read from a file (issue #3)" {
  export_from_env_file_path 'DB_USER=plone' DB_USER
  [ "$status" -eq 0 ]
  [ "$output" = "[plone]" ]
}

@test "env_file_path exports every entry in the file (issue #3)" {
  export_from_env_file_path $'DB_USER=plone\nDB_NAME=site' DB_NAME
  [ "$status" -eq 0 ]
  [ "$output" = "[site]" ]
}

@test "env_file_path ignores comments and blank lines (issue #3)" {
  export_from_env_file_path $'# a comment\n\nDB_USER=plone' DB_USER
  [ "$status" -eq 0 ]
  [ "$output" = "[plone]" ]
}

@test "env_file_path takes values verbatim, like env_file (issue #3)" {
  # The semantics must not diverge between the two inputs: quotes are part of
  # the value, matching `docker --env-file`.
  export_from_env_file_path 'GREETING="hello world"' GREETING
  [ "$status" -eq 0 ]
  [ "$output" = '["hello world"]' ]
}

@test "env_file_path keeps a value containing spaces (issue #3)" {
  export_from_env_file_path 'SOLR_JAVA_MEM=-Xms1536m -Xmx1536m' SOLR_JAVA_MEM
  [ "$status" -eq 0 ]
  [ "$output" = "[-Xms1536m -Xmx1536m]" ]
}

@test "env_file_path does not drop the last line of the file (issue #3)" {
  # A real file ends in a newline, unlike the env_file input; the read loop
  # has to handle both without losing or duplicating the final entry.
  export_from_env_file_path $'DB_USER=plone\nDB_NAME=site\nLAST=here' LAST
  [ "$status" -eq 0 ]
  [ "$output" = "[here]" ]
}

@test "env_file_path rejects a malformed line (issue #3)" {
  printf '%s\n' 'not-a-pair' > "${BATS_TEST_TMPDIR}/bad.env"
  run env -i PATH="${PATH}" HOME="${BATS_TEST_TMPDIR}" \
    ENV_FILE_PATH="${BATS_TEST_TMPDIR}/bad.env" \
    bash -c "source '${ENTRYPOINT}'; configure_env_file_path"
  [ "$status" -eq 1 ]
  [[ "$output" == *"'not-a-pair' is not in NAME=VALUE format"* ]]
}

@test "env_file_path says which file it read (issue #3)" {
  printf '%s\n' 'DB_USER=plone' > "${BATS_TEST_TMPDIR}/vars.env"
  run env -i PATH="${PATH}" HOME="${BATS_TEST_TMPDIR}" \
    ENV_FILE_PATH="${BATS_TEST_TMPDIR}/vars.env" \
    bash -c "source '${ENTRYPOINT}'; configure_env_file_path"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Environment Variables: Reading ${BATS_TEST_TMPDIR}/vars.env"* ]]
}

@test "env_file_path fails when the file does not exist (issue #3)" {
  run_entrypoint ENV_FILE_PATH=/nope/missing.env
  [ "$status" -eq 1 ]
  [[ "$output" == *"/nope/missing.env does not exist."* ]]
}

@test "env_file and env_file_path together are rejected (issue #3)" {
  printf '%s\n' 'DB_USER=plone' > "${BATS_TEST_TMPDIR}/vars.env"
  run_entrypoint ENV_FILE="DB_NAME=site" \
    ENV_FILE_PATH="${BATS_TEST_TMPDIR}/vars.env"
  [ "$status" -eq 1 ]
  [[ "$output" == *"env_file and env_file_path are mutually exclusive"* ]]
}

@test "env_file_path is read as part of the deploy flow (issue #3)" {
  # The tests above call configure_env_file_path directly; this one proves the
  # input is actually wired into the script's flow.
  printf '%s\n' 'DB_USER=plone' > "${BATS_TEST_TMPDIR}/vars.env"
  run_entrypoint ENV_FILE_PATH="${BATS_TEST_TMPDIR}/vars.env"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Environment Variables: Reading ${BATS_TEST_TMPDIR}/vars.env"* ]]
  [[ "$output" == *"Input remote_host is required!"* ]]
}

@test "env_file still works when env_file_path is unset (issue #3)" {
  # Backwards compatibility is the whole point of adding an input rather than
  # changing the meaning of the existing one.
  run_entrypoint ENV_FILE="DB_USER=plone"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Environment Variables: Additional values"* ]]
  [[ "$output" == *"Input remote_host is required!"* ]]
}

# --- scale_after --------------------------------------------------------------

@test "scale_after does nothing when unset" {
  # shellcheck source=/dev/null
  source "${ENTRYPOINT}"
  SCALE_AFTER=""
  run scale_after
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "scale_after passes each service=n pair as its own argument" {
  # shellcheck source=/dev/null
  source "${ENTRYPOINT}"
  SCALE_AFTER="demo_dbpack=1 demo_reindex=1"
  run scale_after
  [ "$status" -eq 0 ]
  [[ "$(stub_calls)" == *"service scale demo_dbpack=1 demo_reindex=1"* ]]
}

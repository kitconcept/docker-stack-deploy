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
      ENV_FILE_PATH=\"\${HOME}/.env\"
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

@test "issue #21: env_file exports a value containing spaces" {
  skip "https://github.com/kitconcept/docker-stack-deploy/issues/21 -- the unquoted \$(...) word-splits the value before export runs"
  export_from_env_file 'SOLR_JAVA_MEM=-Xms1536m -Xmx1536m' SOLR_JAVA_MEM
  [ "$status" -eq 0 ]
  [ "$output" = "-Xms1536m -Xmx1536m" ]
}

@test "issue #21: quotes in an env_file value are kept verbatim" {
  skip "https://github.com/kitconcept/docker-stack-deploy/issues/21 -- pending the parser rewrite; we match 'docker --env-file' and do not strip quotes"
  export_from_env_file 'GREETING="hello world"' GREETING
  [ "$status" -eq 0 ]
  [ "$output" = '"hello world"' ]
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

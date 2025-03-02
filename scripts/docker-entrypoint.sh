#!/bin/bash
set -e

# Use root home folder
SSH_DIR="/root/.ssh"
SSH_KEY="${SSH_DIR}/docker"
KNOWN_HOSTS="${SSH_DIR}/known_hosts"
ENV_FILE_PATH="/root/.env"

login() {
  echo "${PASSWORD}" | docker login "${REGISTRY}" -u "${USERNAME}" --password-stdin
}

configure_ssh() {
  mkdir -p "${SSH_DIR}"
  printf '%s' "UserKnownHostsFile=${KNOWN_HOSTS}" > "${SSH_DIR}/config"
  chmod 600 "${SSH_DIR}/config"
}

configure_ssh_key() {
  printf '%s' "$REMOTE_PRIVATE_KEY" > "${SSH_KEY}"
  lastLine=$(tail -n 1 "${SSH_KEY}")
  if [ "${lastLine}" != "" ]; then
    printf '\n' >> "${SSH_KEY}";
  fi
  chmod 600 "${SSH_KEY}"
  eval "$(ssh-agent)"
  ssh-add "${SSH_KEY}"
}

configure_env_file() {
  cat "$ENV_FILE" > "${ENV_FILE_PATH}"
  env_file_len=$(grep -v '^#' ${ENV_FILE_PATH}|grep -v '^$' -c)
  if [[ $env_file_len -gt 0 ]]; then
    echo "Environment Variables: Additional values"
    if [ "${DEBUG}" != "0" ]; then
      echo "Environment vars before: $(env|wc -l)"
    fi
    # shellcheck disable=SC2046
    export $(grep -v '^#' ${ENV_FILE_PATH} | grep -v '^$' | xargs -d '\n')
    if [ "${DEBUG}" != "0" ]; then
      echo "Environment vars after: $(env|wc -l)"
    fi
  fi
}

configure_ssh_host() {
  ssh-keyscan -p "${REMOTE_PORT}" "${REMOTE_HOST}" > "${KNOWN_HOSTS}"
  chmod 600 "${KNOWN_HOSTS}"
}

connect_ssh() {
  cmd="ssh"
  if [ "${SSH_VERBOSE}" != "" ]; then
    cmd="ssh ${SSH_VERBOSE}"
  fi
  user=$(${cmd} -p "${REMOTE_PORT}" "${REMOTE_USER}@${REMOTE_HOST}" whoami)
  if [ "${user}" != "${REMOTE_USER}" ]; then
    exit 1;
  fi
}

deploy() {
  docker stack deploy --with-registry-auth -c "${STACK_FILE}" "${STACK_NAME}"
}

check_deploy() {
  echo "Deploy: Checking status"
  /stack-wait.sh -t "${DEPLOY_TIMEOUT}" "${STACK_NAME}"
}

[ -z ${DEBUG+x} ] && export DEBUG="0"

# ADDITIONAL ENV VARIABLES
if [[ -z "${ENV_FILE}" ]]; then
  export ENV_FILE=""
else
  configure_env_file;
fi

# SET DEBUG
if [ "${DEBUG}" != "0" ]; then
  OUT=/dev/stdout;
  SSH_VERBOSE="-vvv"
  echo "Verbose logging"
else
  OUT=/dev/null;
  SSH_VERBOSE=""
fi

# PROCEED WITH LOGIN
if [ -z "${USERNAME+x}" ] || [ -z "${PASSWORD+x}" ]; then
  echo "Container Registry: No authentication provided"
else
  [ -z ${REGISTRY+x} ] && export REGISTRY=""
  if login > /dev/null 2>&1; then
    echo "Container Registry: Logged in ${REGISTRY} as ${USERNAME}"
  else
    echo "Container Registry: Login to ${REGISTRY} as ${USERNAME} failed"
    exit 1
  fi
fi

if [[ -z "${DEPLOY_TIMEOUT}" ]]; then
  export DEPLOY_TIMEOUT=600
fi

# CHECK REMOTE VARIABLES
if [[ -z "${REMOTE_HOST}" ]]; then
  echo "Input remote_host is required!"
  exit 1
fi
if [[ -z "${REMOTE_PORT}" ]]; then
  export REMOTE_PORT="22"
fi
if [[ -z "${REMOTE_USER}" ]]; then
  echo "Input remote_user is required!"
  exit 1
fi
if [[ -z "${REMOTE_PRIVATE_KEY}" ]]; then
  echo "Input private_key is required!"
  exit 1
fi
# CHECK STACK VARIABLES
if [[ -z "${STACK_FILE}" ]]; then
  echo "Input stack_file is required!"
  exit 1
else
  if [ ! -f "${STACK_FILE}" ]; then
    echo "${STACK_FILE} does not exist."
    exit 1
  fi
fi

if [[ -z "${STACK_NAME}" ]]; then
  echo "Input stack_name is required!"
  exit 1
fi


# CONFIGURE SSH CLIENT
if configure_ssh > $OUT 2>&1; then
  echo "SSH client: Configured"
else
  echo "SSH client: Configuration failed"
  exit 1
fi

if configure_ssh_key > $OUT 2>&1; then
  echo "SSH client: Added private key"
else
  echo "SSH client: Private key failed"
  exit 1
fi

if configure_ssh_host > $OUT 2>&1; then
  echo "SSH remote: Keys added to ${KNOWN_HOSTS}"
else
  echo "SSH remote: Server ${REMOTE_HOST} on port ${REMOTE_PORT} not available"
  exit 1
fi

if connect_ssh > $OUT; then
  echo "SSH connect: Success"
else
  echo "SSH connect: Failed to connect to remote server"
  exit 1
fi

export DOCKER_HOST="ssh://${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_PORT}"

if deploy > $OUT; then
  echo "Deploy: Updated services"
else
  echo "Deploy: Failed to deploy ${STACK_NAME} from file ${STACK_FILE}"
  exit 1
fi

if check_deploy; then
  echo "Deploy: Completed"
else
  echo "Deploy: Failed"
  exit 1
fi

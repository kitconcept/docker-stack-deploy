<p align="center">
  <a href="https://github.com/marketplace/actions/docker-stack-deploy-action">
    <img alt="GitHub Pages Deploy Action Logo" width="200px" src="https://raw.githubusercontent.com/kitconcept/docker-stack-deploy/main/docs/icon.png">
  </a>
</p>

<h1 align="center">
  Docker Stack Deploy Tool
</h1>

<div align="center">

[![GitHub Actions Marketplace](https://img.shields.io/badge/action-marketplace-blue.svg?logo=github&color=orange)](https://github.com/marketplace/actions/docker-stack-deploy-action)
[![Release version badge](https://img.shields.io/github/v/release/kitconcept/docker-stack-deploy)](https://github.com/kitconcept/docker-stack-deploy/releases)

![GitHub Repo stars](https://img.shields.io/github/stars/kitconcept/docker-stack-deploy?style=flat-square)
[![license badge](https://img.shields.io/github/license/kitconcept/docker-stack-deploy)](./LICENSE)

</div>

GitHub Action and Docker image used to deploy a Docker stack on a Docker Swarm.


## Configuration options

| GitHub Action Input | Environment Variable | Summary | Required | Default Value |
| --- | --- | --- | --- | --- |
| `registry` | `REGISTRY` | Specify which container registry to login to. | |
| `username` | `USERNAME` | Container registry username. | | |
| `password` | `PASSWORD` | Container registry password. | | |
| `remote_host` | `REMOTE_HOST` | Hostname or address of the machine running the Docker Swarm manager node | ✅ | |
| `remote_port` | `REMOTE_PORT` | SSH port to connect on the the machine running the Docker Swarm manager node. | | **22** |
| `remote_user` | `REMOTE_USER` | User with SSH and Docker privileges on the machine running the Docker Swarm manager node. | ✅ | |
| `remote_private_key` | `REMOTE_PRIVATE_KEY` | Private key used for ssh authentication. | ✅ | |
| `deploy_timeout` | `DEPLOY_TIMEOUT` | Seconds, to wait until the deploy finishes | | **600** |
| `resolve_image` | `RESOLVE_IMAGE` | Query the registry to resolve image digest and supported platforms before deploy | | **always** |
| `prune` | `PRUNE` | Prune services that are not defined in the stack file | | **0** |
| `stack_file` | `STACK_FILE` | Path to the stack file used in the deploy. | ✅ | |
| `stack_name` | `STACK_NAME` | Name of the stack to be deployed. | ✅ | |
| `stack_param` | `STACK_PARAM` | A single additional value, available to the stack file as `${STACK_PARAM}`. Superseded by `env_file`, see [Passing values into the stack file](#passing-values-into-the-stack-file). | | |
| `env_file` | `ENV_FILE` | Additional environment variables **as content**, one `VAR=VALUE` per line. Mutually exclusive with `env_file_path`. | | |
| `env_file_path` | `ENV_FILE_PATH` | **Path** to a file of additional environment variables, one `VAR=VALUE` per line. Mutually exclusive with `env_file`. | | |
| `debug` | `DEBUG` | Verbose logging | | **0** |
| `scale_after` | `SCALE_AFTER` | Scale a service after a deployment has converged successfully. Example: servicename=1 | | |

### A note on whitespace

`registry`, `username`, `remote_host`, `remote_port` and `remote_user` cannot
contain whitespace, so any is removed before the value is used, and a line
naming the input is written to the log when that happens:

```
Input remote_host: removed whitespace from the value
```

This exists because a stray newline in a GitHub secret is invisible in the
repository UI, and used to surface much later as an opaque
`ssh: Could not resolve hostname`.

`remote_private_key` and `password` are left exactly as given — newlines are
structural in a PEM key, and whitespace can be a legitimate part of a token.


## Passing values into the stack file

Your stack file can reference environment variables, and `docker stack deploy`
substitutes them as it reads the file. This action gives you three ways to set
those variables, all of which work through that same substitution.

### `env_file` — the variables themselves

Pass the content directly. Each line is a `VAR=VALUE` pair:

```yaml
      - name: Deploy
        uses: kitconcept/docker-stack-deploy@v1.4.0
        with:
          # ...
          env_file: |
            BACKEND_REPLICAS=2
            FRONTEND_REPLICAS=3
            SOLR_JAVA_MEM=-Xms1536m -Xmx1536m
```

```yaml
# stacks/plone.yml
services:
  backend:
    deploy:
      replicas: ${BACKEND_REPLICAS}
  frontend:
    deploy:
      replicas: ${FRONTEND_REPLICAS}
```

Values are taken **verbatim**, matching `docker --env-file`: a value may
contain spaces, and quotes around it become part of the value rather than
being stripped. So `GREETING="hello"` sets `GREETING` to `"hello"`, quotes
included.

Lines that are blank or start with `#` are ignored. Anything else that is not
`NAME=VALUE` is an error naming the offending line, rather than a silent
failure to export.

### `env_file_path` — a file to read them from

If the variables already live in a file in your repository, point at it
instead. Relative paths resolve against the workspace, the same as `stack_file`:

```yaml
        with:
          # ...
          env_file_path: "stacks/production.env"
```

The file format and the verbatim semantics are identical to `env_file`. The two
inputs are mutually exclusive — supplying both is an error, because the
precedence between them would otherwise be arbitrary.

### `stack_param` — a single value (discouraged)

`stack_param` sets one variable, always named `STACK_PARAM`:

```yaml
        with:
          # ...
          stack_param: "2"
```

```yaml
# stacks/plone.yml
services:
  backend:
    deploy:
      replicas: ${STACK_PARAM}
```

It works, and it is kept for compatibility, but it is a one-variable special
case of `env_file` with a name you cannot choose. Prefer `env_file` or
`env_file_path` for anything new.


## Using the GitHub Action

Add, or edit an existing, `yaml` file inside `.github/actions` and use the configuration options listed above.

### Examples

#### Deploying public images


```yaml
name: Deploy Staging

on:
  push:
    branches:
      - main

jobs:

  deploy:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout codebase
        uses: actions/checkout@v7

      - name: Deploy
        uses: kitconcept/docker-stack-deploy@v1.4.0
        with:
          remote_host: ${{ secrets.REMOTE_HOST }}
          remote_user: ${{ secrets.REMOTE_USER }}
          remote_private_key: ${{ secrets.REMOTE_PRIVATE_KEY }}
          stack_file: "stacks/plone.yml"
          stack_name: "plone-staging"
```

#### Deploying private images from GitHub Container Registry

First, follow the steps to [create a Personal Access Token](https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry#authenticating-to-the-container-registry).

```yaml
name: Deploy Live

on:
  push:
    tags:
      - '*.*.*'

jobs:

  deploy:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout codebase
        uses: actions/checkout@v7

      - name: Deploy
        uses: kitconcept/docker-stack-deploy@v1.4.0
        with:
          registry: "ghcr.io"
          username: ${{ secrets.GHCR_USERNAME }}
          password: ${{ secrets.GHCR_TOKEN }}
          remote_host: ${{ secrets.REMOTE_HOST }}
          remote_user: ${{ secrets.REMOTE_USER }}
          remote_private_key: ${{ secrets.REMOTE_PRIVATE_KEY }}
          stack_file: "stacks/plone.yml"
          stack_name: "plone-live"
```

## Using the Docker Image

It is possible to directly use the `ghcr.io/kitconcept/docker-stack-deploy` Docker image, passing the configuration options as environment variables.

### Examples

#### Local machine

Considering you have a local file named `.env_deploy` with content:

```
REGISTRY=hub.docker.com
USERNAME=foo_usr
PASSWORD=averylargepasswordortoken
REMOTE_HOST=192.168.17.2
REMOTE_PORT=22
REMOTE_USER=user
STACK_FILE=path/to/stack.yml
STACK_NAME=mystack
DEBUG=1
```

Run the following command:
```shell
docker run --rm
  -v "$(pwd)":/github/workspace
  -v /var/run/docker.sock:/var/run/docker.sock
  --env-file=.env_deploy
  -e REMOTE_PRIVATE_KEY="$(cat ~/.ssh/id_rsa)"
  ghcr.io/kitconcept/docker-stack-deploy:latest
```

#### GitLab CI

On your GitLab project, go to  `Settings -> CI/CD` and add the environment variables under **Variables**.

Then edit your `.gitlab-cy.yml` to include the `deploy` step:

```yaml
image: busybox:latest

services:
  - docker:20.10.16-dind

before_script:
  - docker info

deploy:
  stage: deploy
  varibles:
    REGISTRY: ${REGISTRY}
    USERNAME: ${REGISTRY_USER}
    PASSWORD: ${REGISTRY_PASSWORD}
    REMOTE_HOST: ${DEPLOY_HOST}
    REMOTE_PORT: 22
    REMOTE_USER: ${DEPLOY_USER}
    REMOTE_PRIVATE_KEY: "${DEPLOY_KEY}"
    STACK_FILE: stacks/app.yml
    STACK_NAME: app
    DEPLOY_IMAGE: ghcr.io/kitconcept/docker-stack-deploy:latest
  script:
    - docker pull ${DEPLOY_IMAGE}
    - docker run --rm
       -v "$(pwd)":/github/workspace
       -v /var/run/docker.sock:/var/run/docker.sock
       -e REGISTRY=${REGISTRY}
       -e USERNAME=${USERNAME}
       -e PASSWORD=${PASSWORD}
       -e REMOTE_HOST=${REMOTE_HOST}
       -e REMOTE_PORT=${REMOTE_PORT}
       -e REMOTE_USER=${REMOTE_USER}
       -e REMOTE_PRIVATE_KEY="${REMOTE_PRIVATE_KEY}"
       -e STACK_FILE=${STACK_FILE}
       -e STACK_NAME=${STACK_NAME}
       -e DEBUG=1
       ${DEPLOY_IMAGE}

```

## Contribute

- [Issue Tracker](https://github.com/kitconcept/docker-stack-deploy/issues)
- [Source Code](https://github.com/kitconcept/docker-stack-deploy/)
- [Documentation](https://github.com/kitconcept/docker-stack-deploy/)

Please **DO NOT** commit to version branches directly. Even for the smallest and most trivial fix.

**ALWAYS** open a pull request and ask somebody else to merge your code. **NEVER** merge it yourself.

### Development

Both commands need Docker, and nothing else — there is no local toolchain to install.

```shell
make lint   # shellcheck the shell scripts
make test   # run the bats suite
```

`make test` builds the action image and then builds the test runner on top of
it, so the suite runs in the same environment the action ships. That matters:
the scripts rely on GNU `xargs` from `findutils`, and against the busybox
`xargs` in a plain Alpine image the tests fail for reasons that have nothing to
do with the code.

Tests live in `tests/` and use a fake `docker` CLI (`tests/helpers/bin/docker`)
that replays a scenario from `tests/fixtures/*.services`, so no Swarm is
needed. Each fixture describes one poll of the wait loop per section.

Tests that document a currently open bug call `skip` with a link to the issue.
They are written to assert the *desired* behaviour, so fixing the bug means
deleting the `skip` line rather than writing a new test.

### Change log

`CHANGELOG.md` is generated by [towncrier](https://towncrier.readthedocs.io/) —
do not edit it directly. Add a file to `news/` instead, named for the issue it
addresses, and CI will check that every pull request has one.

```
news/21.bugfix            # an issue number, when there is an issue
news/+test-harness.internal   # a short slug, when there is not
```

Types are `breaking`, `feature`, `bugfix`, `internal` and `documentation`. Write
one sentence in the past tense, describing the change from the user's side, and
sign it with your GitHub handle:

```
Fixed `env_file` values containing spaces being truncated. @ericof
```

Preview the result with `uvx towncrier build --draft --version <next>`. A pull
request that genuinely needs no entry can carry the `skip changelog` label.


## Credits

[![kitconcept GmbH](https://raw.githubusercontent.com/kitconcept/docker-stack-deploy/main/docs/kitconcept.png)](https://kitconcept.com)

This repository also uses the `docker-stack-wait` script, available at [GitHub](https://github.com/sudo-bmitch/docker-stack-wait).

The logo is based on [rocket icon](https://freeicons.io/seo/rocket-icon-24668#).
## License

The project is licensed under [MIT License](./LICENSE)

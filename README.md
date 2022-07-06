# Docker Stack Deploy Action

GitHub Action and Docker image used to deploy a Docker stack on a Docker Swarm.

## Inputs

## `registry`

When using private images, specify which registry to login to. If no value is provided, we fallback to Docker Hub.

To use GitHub Container registry, set the value to **ghcr.io**.

## `username`

When using private images, specify username to be used to log in.

## `password`

When using private images, specify password to be used to log in.

## `remote_host`

**Required** Hostname or address of the machine running the Docker Swarm manager node.

## `remote_port`

SSH port to connect on the the machine running the Docker Swarm manager node.

**Default value**: 22

## `remote_user`

**Required** User with SSH and Docker privileges on the machine running the Docker Swarm manager node.

## `remote_private_key`

**Required** Private key used for ssh authentication.

## `deploy_timeout`

Seconds, to wait until the deploy finishes.

**Default value**: 300

## `stack_file`

**Required** Path to the stack file used in the deploy.

## `stack_name`

**Required** Name of the stack to be deployed.


## Examples

### Deploying public images


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
        uses: actions/checkout@v2

      - name: Deploy
        uses: kitconcept/docker-stack-deploy@v1.0.0
        with:
          remote_host: ${{ secrets.REMOTE_HOST }}
          remote_user: ${{ secrets.REMOTE_USER }}
          remote_private_key: ${{ secrets.REMOTE_PRIVATE_KEY }}
          stack_file: "stacks/plone.yml"
          stack_name: "plone-staging"
```

### Deploying private images from GitHub Container Registry

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
        uses: actions/checkout@v2

      - name: Deploy
        uses: kitconcept/docker-stack-deploy@v1.0.0
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

## Contribute

- [Issue Tracker](https://github.com/kitconcept/docker-stack-deploy/issues)
- [Source Code](https://github.com/kitconcept/docker-stack-deploy/)
- [Documentation](https://github.com/kitconcept/docker-stack-deploy/)

Please **DO NOT** commit to version branches directly. Even for the smallest and most trivial fix.

**ALWAYS** open a pull request and ask somebody else to merge your code. **NEVER** merge it yourself.


## Credits

[![kitconcept GmbH](https://raw.githubusercontent.com/kitconcept/docker-stack-deploy/main/docs/kitconcept.png)](https://kitconcept.com)

This repository also uses the `docker-stack-wait` script, available at [GitHub](https://github.com/sudo-bmitch/docker-stack-wait).

## License

The project is licensed under the GPLv2.

FROM docker:29.1.3-cli-alpine3.23

LABEL maintainer="Erik Petrosyan <dev.erikpetrosyan@gmail.com>" \
      org.label-schema.name="docker-stack-deploy" \
      org.label-schema.description="Deploy docker stack" \
      org.label-schema.vendor="Erik Petrosyan" \
      org.opencontainers.image.source="https://github.com/PetrosyanDev/docker-stack-deploy" \
      org.label-schema.docker.cmd="docker run --rm -v \${PWD}:/github/workspace ghcr.io/petrosyandev/docker-stack-deploy"

RUN apk add --no-cache openssh-client findutils bash

COPY scripts/*.sh /

WORKDIR /github/workspace

ENTRYPOINT [ "/docker-entrypoint.sh" ]

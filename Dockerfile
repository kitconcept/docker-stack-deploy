FROM docker:29.1.3-cli-alpine3.23

LABEL maintainer="kitconcept GmbH <info@kitconcept.com>" \
      org.label-schema.name="docker-stack-deploy" \
      org.label-schema.description="Deploy docker stack" \
      org.label-schema.vendor="kitconcept GmbH" \
      org.opencontainers.image.source="https://github.com/kitconcept/docker-stack-deploy" \
      org.label-schema.docker.cmd="docker run -rm -v "$(PWD)":/github/workspace ghcr.io/kitconcept/docker-stack-deploy"

RUN apk add --no-cache openssh-client findutils bash

COPY scripts/*.sh /

WORKDIR /github/workspace

ENTRYPOINT [ "/docker-entrypoint.sh" ]

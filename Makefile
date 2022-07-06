## Defensive settings for make:
#     https://tech.davis-hansson.com/p/make/
SHELL:=bash
.ONESHELL:
.SHELLFLAGS:=-xeu -o pipefail -O inherit_errexit -c
.SILENT:
.DELETE_ON_ERROR:
MAKEFLAGS+=--warn-undefined-variables
MAKEFLAGS+=--no-builtin-rules

BASE_NAME=docker-stack-deploy
IMAGE_NAME=ghcr.io/kitconcept/$(BASE_NAME)

# We like colors
# From: https://coderwall.com/p/izxssa/colored-makefile-for-golang-projects
RED=`tput setaf 1`
GREEN=`tput setaf 2`
RESET=`tput sgr0`
YELLOW=`tput setaf 3`

ifndef VERSION
	VERSION=""
endif

.PHONY: all
all: help

# Add the following 'help' target to your Makefile
# And add help text after each target name starting with '\#\#'
.PHONY: help
help: # This help message
	@grep -E '^[a-zA-Z_-]+:.*?# .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?# "}; {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}'

.PHONY: build-image
build-image:  # Build Docker Image
	@echo "Building $(IMAGE_NAME)"
	docker build . -t $(IMAGE_NAME)

create-tag: # Create a new tag using git
	@test -n "$(VERSION)"
	if git show-ref --tags v$(VERSION) --quiet; \
	then \
		echo "$(VERSION) already exists"; \
	else \
		echo "Creating new tag $(VERSION)"; \
		sed -i 's/$(BASE_NAME):latest/$(BASE_NAME):$(VERSION)/' action.yml; \
		git commit -am "Prepare release $(VERSION)"; \
		git tag -a v$(VERSION) -m "Release $(VERSION)"; \
		git push && git push --tags; \
		sed -i 's/$(BASE_NAME):$(VERSION)/$(BASE_NAME):latest/' action.yml; \
		git commit -am "Back to development" && git push; \
	fi \

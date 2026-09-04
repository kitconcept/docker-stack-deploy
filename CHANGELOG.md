# Change log

<!-- You should *NOT* be adding new change log entries to this file.
     You should create a file in the news directory instead.
     See the Development section of README.md for the fragment types and
     naming convention.
-->

<!-- towncrier release notes start -->

## 1.5.0 (2026-09-04)


### Feature

- Added an `env_file_path` input, which reads the additional environment variables from a file instead of taking them as content. `env_file` keeps its current meaning, so nothing breaks; supplying both is an error. @ericof [#3](https://github.com/kitconcept/docker-stack-deploy/issues/3)


### Bugfix

- Fixed a stray newline or space in `remote_host` (or `registry`, `username`, `remote_port`, `remote_user`) breaking the deploy with an opaque `ssh: Could not resolve hostname`. Whitespace is now removed from those inputs, and the log says when it was. @ericof [#1](https://github.com/kitconcept/docker-stack-deploy/issues/1)
- Fixed the deploy waiting until it timed out on a `mode: replicated-job` service that had already run to completion. @ericof [#13](https://github.com/kitconcept/docker-stack-deploy/issues/13)
- Fixed the deploy waiting until it timed out on services the stack file scales to zero, and added the `docker stack ps` task list to the output when a deploy fails. @ericof [#19](https://github.com/kitconcept/docker-stack-deploy/issues/19)
- Fixed `env_file` values containing spaces being truncated to their first word. Each line is now read whole and the value taken verbatim, matching `docker --env-file`. @ericof [#21](https://github.com/kitconcept/docker-stack-deploy/issues/21)


### Internal

- Added a bats test suite for the shell scripts, run in CI together with shellcheck. @ericof 
- Added towncrier to manage the change log, with a CI check that every pull request carries a news fragment. @ericof 
- Updated the base image to `docker:29.5.3-cli-alpine3.23`. @dependabot 


### Documentation

- Documented how values reach the stack file, with worked examples for `env_file`, `env_file_path` and `stack_param`, and noted that `stack_param` is a one-variable special case of `env_file`. @ericof [#2](https://github.com/kitconcept/docker-stack-deploy/issues/2)

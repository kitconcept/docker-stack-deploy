#!/usr/bin/env bats
#
# Behaviour of scripts/stack-wait.sh, exercised against the fake docker CLI in
# tests/helpers/bin. The polling interval is kept at 1s (-s 1) so the suite
# stays fast; the script's default is 5s.

load test_helper

setup() {
  STACK_WAIT="$(script_path stack-wait.sh)"
}

@test "succeeds immediately when every service has already converged" {
  setup_stub converged
  run "${STACK_WAIT}" -s 1 -t 10 demo
  [ "$status" -eq 0 ]
  [[ "$output" == *"demo_backend state: deployed"* ]]
  [[ "$output" == *"demo_frontend state: completed"* ]]
}

@test "waits for a replicating service and then succeeds" {
  setup_stub replicating-then-done
  run "${STACK_WAIT}" -s 1 -t 20 demo
  [ "$status" -eq 0 ]
  # The transient state must be reported, then the settled one.
  [[ "$output" == *"demo_frontend state: replicating 1/3"* ]]
  [[ "$output" == *"demo_frontend state: completed"* ]]
}

@test "reports each state change only once" {
  setup_stub replicating-then-done
  run "${STACK_WAIT}" -s 1 -t 20 demo
  [ "$status" -eq 0 ]
  count=$(printf '%s\n' "$output" | grep -c "demo_backend state: deployed")
  [ "$count" -eq 1 ]
}

@test "fails immediately when an update is paused" {
  setup_stub paused
  run "${STACK_WAIT}" -s 1 -t 10 demo
  [ "$status" -eq 1 ]
  [[ "$output" == *"This deployment will not complete"* ]]
}

@test "treats a rollback as failure by default" {
  setup_stub rollback
  run "${STACK_WAIT}" -s 1 -t 10 demo
  [ "$status" -eq 1 ]
  [[ "$output" == *"This deployment will not complete"* ]]
}

@test "treats a rollback as success with -r" {
  setup_stub rollback
  run "${STACK_WAIT}" -r -s 1 -t 10 demo
  [ "$status" -eq 0 ]
  [[ "$output" == *"demo_backend state: rollback_completed"* ]]
}

@test "times out when a service never converges" {
  setup_stub stuck
  run "${STACK_WAIT}" -s 1 -t 3 demo
  [ "$status" -eq 1 ]
  [[ "$output" == *"Timeout exceeded"* ]]
}

@test "-n waits only for the named services" {
  setup_stub converged
  run "${STACK_WAIT}" -n backend -s 1 -t 10 demo
  [ "$status" -eq 0 ]
  [[ "$output" == *"demo_backend state: deployed"* ]]
  # frontend was not selected, so it must never be polled
  [[ "$output" != *"demo_frontend"* ]]
}

@test "-p prints service logs on success" {
  setup_stub converged
  run "${STACK_WAIT}" -p 5 -s 1 -t 10 demo
  [ "$status" -eq 0 ]
  [[ "$output" == *"stub: log line"* ]]
  [[ "$(stub_calls)" == *"service logs --tail 5"* ]]
}

@test "-p prints service logs on timeout" {
  setup_stub stuck
  run "${STACK_WAIT}" -p 5 -s 1 -t 3 demo
  [ "$status" -eq 1 ]
  [[ "$output" == *"Timeout exceeded"* ]]
  [[ "$output" == *"stub: log line"* ]]
}

@test "requires exactly one stack name" {
  setup_stub converged
  run "${STACK_WAIT}" -s 1 -t 10
  [ "$status" -eq 1 ]
  [[ "$output" == *"[opts] stack_name"* ]]
}

@test "rejects an unknown flag instead of ignoring it" {
  setup_stub converged
  run "${STACK_WAIT}" -Z -s 1 -t 10 demo
  [ "$status" -eq 1 ]
  [[ "$output" == *"[opts] stack_name"* ]]
}

@test "-h prints usage and exits zero" {
  setup_stub converged
  run "${STACK_WAIT}" -h demo
  [ "$status" -eq 0 ]
  [[ "$output" == *"[opts] stack_name"* ]]
}

# --- Services that are not meant to be running (issues #13, #19) -------------------------------

@test "a completed replicated-job counts as converged (issue #13)" {
  setup_stub replicated-job
  run "${STACK_WAIT}" -s 1 -t 5 demo
  [ "$status" -eq 0 ]
  [[ "$output" != *"Timeout exceeded"* ]]
}

@test "a service the stack file scales to zero does not block (issue #19)" {
  setup_stub zero-replicas
  run "${STACK_WAIT}" -s 1 -t 5 demo
  [ "$status" -eq 0 ]
  [[ "$output" != *"Timeout exceeded"* ]]
}

@test "the final stack state is logged on timeout (issue #19)" {
  setup_stub stuck
  run "${STACK_WAIT}" -s 1 -t 3 demo
  [ "$status" -eq 1 ]
  [[ "$(stub_calls)" == *"stack ps"* ]]
}

@test "a still-running replicated-job is waited for (issue #13)" {
  setup_stub running-job
  run "${STACK_WAIT}" -s 1 -t 20 demo
  [ "$status" -eq 0 ]
  # Reported as running while incomplete, then settled once it finishes.
  [[ "$output" == *"demo_migrate state: job_running 0/1"* ]]
  [[ "$output" == *"demo_migrate state: job_completed"* ]]
}

@test "a genuinely failed service still times out (issue #19 regression guard)" {
  # Same 0/1 as the zero-replica case, but the stack file wants 1 replica.
  # This must NOT be swallowed by the scaled_to_zero shortcut.
  setup_stub failed-start
  run "${STACK_WAIT}" -s 1 -t 3 demo
  [ "$status" -eq 1 ]
  [[ "$output" == *"Timeout exceeded"* ]]
}

@test "the final stack state is logged when a deployment cannot complete" {
  setup_stub paused
  run "${STACK_WAIT}" -s 1 -t 10 demo
  [ "$status" -eq 1 ]
  [[ "$output" == *"Stack state at failure:"* ]]
  [[ "$(stub_calls)" == *"stack ps"* ]]
}

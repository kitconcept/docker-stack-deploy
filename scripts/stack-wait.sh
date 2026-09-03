#!/bin/sh

# Originally by: Brandon Mitchell <public@bmitch.net>
# License: MIT
# Upstream repo: https://github.com/sudo-bmitch/docker-stack-wait
#
# Forked into this repository and maintained here. Changes are not
# automatically taken from upstream; see tests/stack-wait.bats for the
# behaviour this fork is expected to preserve.

set -e
trap "{ exit 1; }" TERM INT
opt_h=0
opt_r=0
opt_p=0
opt_s=5
opt_t=3600
start_epoc=$(date +%s)

usage() {
  echo "$(basename "$0") [opts] stack_name"
  echo "  -f filter: only wait for services matching filter, may be passed multiple"
  echo "             times, see docker stack services for the filter syntax"
  echo "  -h:        this help message"
  echo "  -n name:   only wait for specific service names, overrides any filters,"
  echo "             may be passed multiple times, do not include the stack name prefix"
  echo "  -p lines:  print last n lines of relevant service logs at end"
  echo "             passed to the '--tail' option of docker service logs"
  echo "  -r:        treat a rollback as successful"
  echo "  -s sec:    frequency to poll service state (default $opt_s sec)"
  echo "  -t sec:    timeout to stop waiting"
  [ "$opt_h" = "1" ] && exit 0 || exit 1
}
check_timeout() {
  # timeout when a timeout is defined and we will exceed the timeout after the
  # next sleep completes
  if [ "$opt_t" -gt 0 ]; then
    cur_epoc=$(date +%s)
    cutoff_epoc=$((start_epoc + opt_t - opt_s))
    if [ "$cur_epoc" -gt "$cutoff_epoc" ]; then
      echo "Error: Timeout exceeded"
      print_stack_state
      print_service_logs
      exit 1
    fi
  fi
}
get_service_ids() {
  if [ -n "$opt_n" ]; then
    service_list=""
    for name in $opt_n; do
      service_list="${service_list:+${service_list} }${stack_name}_${name}"
    done
    # Unquoted on purpose: service_list is a space-separated list of names.
    # shellcheck disable=SC2086
    docker service inspect --format '{{.ID}}' ${service_list}
  else
    # Unquoted on purpose: opt_f accumulates repeated "-f filter" pairs.
    # shellcheck disable=SC2086
    docker stack services ${opt_f} -q "${stack_name}"
  fi
}
service_state() {
  # output the state when it changes from the last state for the service
  service=$1
  # strip any invalid chars from service name for caching state
  service_safe=$(echo "$service" | sed 's/[^A-Za-z0-9_]/_/g')
  state=$2
  # Unquoted on purpose in both evals: service_safe is the sanitised service
  # name spliced into a variable name, not a value.
  # shellcheck disable=SC2086
  if eval [ \"\$cache_${service_safe}\" != \"\$state\" ]; then
    echo "Service $service state: $state"
    # shellcheck disable=SC2086
    eval cache_${service_safe}=\"\$state\"
  fi
}
print_stack_state() {
  # On failure the per-service state log only shows what changed, so the state
  # each service was left in has to be reconstructed by reading back through
  # it. Dump the task list instead: it names the service that stalled and
  # carries the error column.
  echo "Stack state at failure:"
  docker stack ps --no-trunc "${stack_name}" || true
}
print_service_logs() {
  if [ "$opt_p" != "0" ]; then
    service_ids=$(get_service_ids)
    for service_id in ${service_ids}; do
      docker service logs --tail "$opt_p" "$service_id"
    done
  fi
}

while getopts 'f:hn:p:rs:t:' opt; do
  case $opt in
    f) opt_f="${opt_f:+${opt_f} }-f $OPTARG";;
    h) opt_h=1;;
    n) opt_n="${opt_n:+${opt_n} } $OPTARG";;
    p) opt_p="$OPTARG";;
    r) opt_r=1;;
    s) opt_s="$OPTARG";;
    t) opt_t="$OPTARG";;
    *) usage;;
  esac
done
shift $((OPTIND - 1))

if [ $# -ne 1 ] || [ "$opt_h" = "1" ] || [ "$opt_s" -le "0" ]; then
  usage
fi

stack_name=$1

# 0 = running, 1 = success, 2 = error
stack_done=0
while [ "$stack_done" != "1" ]; do
  stack_done=1
  # run get_service_ids outside of the for loop to catch errors
  service_ids=$(get_service_ids)
  for service_id in ${service_ids}; do
    service_done=1
    service=$(docker service inspect --format '{{.Spec.Name}}' "$service_id")

    # hardcode a "deployed" state when UpdateStatus is not defined
    state=$(docker service inspect -f '{{if .UpdateStatus}}{{.UpdateStatus.State}}{{else}}deployed{{end}}' "$service_id")

    # check for failed update states
    case "$state" in
      paused|rollback_paused)
        service_done=2
        ;;
      rollback_*)
        if [ "$opt_r" = "0" ]; then
          service_done=2
        fi
        ;;
    esac

    # identify/report current state
    if [ "$service_done" != "2" ]; then
      # The whole field, which is "1/1" for a plain service but carries a
      # completion count for a job: "0/1 (1/1 completed)".
      replicas_full=$(docker service ls --format '{{.Replicas}}' --filter "id=$service_id")
      replicas=$(echo "$replicas_full" | cut -d' ' -f1)
      current=$(echo "$replicas" | cut -d/ -f1)
      target=$(echo "$replicas" | cut -d/ -f2)

      # Runs finished and runs wanted, for a `mode: replicated-job` service.
      # Empty for every other mode, which is what selects the branch below.
      job_done=$(echo "$replicas_full" | sed -n 's/.*(\([0-9]*\)\/[0-9]* completed).*/\1/p')
      job_total=$(echo "$replicas_full" | sed -n 's/.*([0-9]*\/\([0-9]*\) completed).*/\1/p')

      # Replicas the stack file asks for, which is not always what
      # `docker service ls` reports as the target yet: `docker stack deploy`
      # returns before the new spec has been applied, and an external
      # scheduler may have scaled the service in the meantime. Re-read every
      # poll so a stale target corrects itself.
      spec_replicas=$(docker service inspect \
        --format '{{if .Spec.Mode.Replicated}}{{.Spec.Mode.Replicated.Replicas}}{{end}}' \
        "$service_id" 2>/dev/null || echo "")

      if [ -n "$job_total" ]; then
        # A job is finished when every requested run has completed. Its
        # running count goes back to 0 and must not be read as "not started".
        if [ "$job_done" = "$job_total" ]; then
          state="job_completed"
        else
          service_done=0
          state="job_running $job_done/$job_total"
        fi
      elif [ "$spec_replicas" = "0" ]; then
        # Deliberately stopped by the stack file, so there is nothing to wait
        # for even if the target has not caught up yet.
        state="scaled_to_zero"
      elif [ "$current" != "$target" ]; then
        # actively replicating service
        service_done=0
        state="replicating $replicas"
      fi
    fi
    service_state "$service" "$state"

    # check for states that indicate an update is done
    # Keep this list in sync with the states assigned above: a state that is
    # settled but missing here falls into the catch-all and waits forever.
    if [ "$service_done" = "1" ]; then
      case "$state" in
        deployed|completed|rollback_completed|job_completed|scaled_to_zero)
          service_done=1
          ;;
        *)
          # any other state is unknown, not necessarily finished
          service_done=0
          ;;
      esac
    fi

    # update stack done state
    if [ "$service_done" = "2" ]; then
      # error condition
      stack_done=2
    elif [ "$service_done" = "0" ] && [ "$stack_done" = "1" ]; then
      # only go to an updating state if not in an error state
      stack_done=0
    fi
  done
  if [ "$stack_done" = "2" ]; then
    echo "Error: This deployment will not complete"
    print_stack_state
    print_service_logs
    exit 1
  fi
  if [ "$stack_done" != "1" ]; then
    check_timeout
    sleep "${opt_s}"
  fi
done

print_service_logs

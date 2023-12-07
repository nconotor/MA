#!/bin/bash

# Function to get current date and time in the format required by journalctl
current_datetime() {
    date +"%Y-%m-%d %H:%M:%S"
}

# Function to save the journalctl log
save_journalctl_log() {
    local start_time=$1
    local end_time=$2
    local journallog_file="$3/journallog"

    journalctl --since "$start_time" --until "$end_time" > "$journallog_file"
}

# Assure all features are activated
modprobe msr

# Default settings: all tests are off except for cyclictest
declare -A RUN_TESTS=(
    [HACKBENCH]=0
    [DD]=0
    [STRESS_NG]=0
    [STRESS]=0
    [LTP]=0
    [CYCLICTEST]=1  # Cyclictest always runs
)

CYCLICTEST_MODE="baremetal"
STRESS_NG_CUSTOM_OPTS="--class cpu,device,interrupt,network,pipe,scheduler,io,cpu-cache --all 1"
DURATION="210s"
LOOP_COUNT="1000000"
RUN_HWLATDETECT=0

# Parse command-line arguments
while (( "$#" )); do
    case "$1" in
        --hackbench) RUN_TESTS[HACKBENCH]=1 ;;
        --dd) RUN_TESTS[DD]=1 ;;
        --stress-ng) RUN_TESTS[STRESS_NG]=1 ;;
        --ltp) RUN_TESTS[LTP]=1 ;;
        --stress) RUN_TESTS[STRESS]=1 ;;
        --docker) CYCLICTEST_MODE="docker" ;;
        --duration) DURATION="$2"; shift ;;
        --loopcount) LOOP_COUNT="$2"; shift ;;
        --stress_ng_opt) STRESS_NG_CUSTOM_OPTS="$2"; shift ;;
        --hwlatdetect) RUN_HWLATDETECT=1 ;;
        *) echo "Error: Invalid option $1"; exit 1 ;;
    esac
    shift
done

#IFS=' ' read -r -a stress_ng_opts <<< "$STRESS_NG_CUSTOM_OPTS"

run_command() {
    local cmd=$1
    shift
    local args=("$@")
    local cmd_string="$cmd ${args[*]}"
    echo "Executing command: $cmd_string"
    timeout -k "$DURATION" "$DURATION" bash -c "$cmd_string > /dev/null 2>&1" &
}

# Create a timestamp
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# Format the duration and loop count for folder naming
FORMATTED_DURATION=${DURATION//[^0-9]/}
FORMATTED_LOOP_COUNT=${LOOP_COUNT//[^0-9]/}

# Create a folder name with loop count, runtime, and timestamp
OUTPUT_DIR="Output_loop${FORMATTED_LOOP_COUNT}_run${FORMATTED_DURATION}_$TIMESTAMP"
mkdir -p "$OUTPUT_DIR"

# Log file setup
LOG_FILE="$OUTPUT_DIR/log"
{
    echo "Duration: $DURATION"
    echo "Loop Count: $LOOP_COUNT"
    echo "Cyclictest Mode: $CYCLICTEST_MODE"
    echo "Stress-ng Custom Options: $STRESS_NG_CUSTOM_OPTS"
    echo "Run Hwlatdetect: $RUN_HWLATDETECT"
    for test in "${!RUN_TESTS[@]}"; do
        echo "Run $test: ${RUN_TESTS[$test]}"
    done
} > "$LOG_FILE"

# Record the start time
start_time=$(current_datetime)

# Run hwlatdetect if flag is set
if [[ $RUN_HWLATDETECT -eq 1 ]]; then
    echo "Running hwlatdetect for 60 seconds..." >> "$LOG_FILE"
    hwlatdetect --duration=60s >> "$LOG_FILE" 2>&1
fi

# Run selected tests
[[ ${RUN_TESTS[HACKBENCH]} -eq 1 ]] && run_command hackbench 20
[[ ${RUN_TESTS[DD]} -eq 1 ]] && run_command dd if=/dev/zero of=/dev/null bs=128M
[[ ${RUN_TESTS[STRESS_NG]} -eq 1 ]] && run_command stress-ng "${stress_ng_opts[@]}"
[[ ${RUN_TESTS[STRESS]} -eq 1 ]] && run_command stress --cpu 4 --vm 16 --vm-bytes 1G -t 1m
[[ ${RUN_TESTS[LTP]} -eq 1 ]] && run_command /opt/ltp/runltp -x 10 -R -q

# Run cyclictest based on mode
CYCLICTEST_PARAMS="-l$LOOP_COUNT --mlockall --smi --smp --priority=98 --interval=200 --distance=0 -h400 -v"
if [[ $CYCLICTEST_MODE == "docker" ]]; then
    docker run --cap-add=sys_nice --cap-add=ipc_lock --ulimit rtprio=99 --device-cgroup-rule='c 10:* rmw' -v /dev:/dev -v "$(pwd)/output:/output" --rm nconotor/rt-tests:r2 /bin/bash -c "cyclictest $CYCLICTEST_PARAMS" 2>> "$LOG_FILE" > "$OUTPUT_DIR/output"
else
    { time cyclictest $CYCLICTEST_PARAMS; } 2>> "$LOG_FILE" > "$OUTPUT_DIR/output"
fi

# Log CPU states
{
    echo "Online CPUs: $(cat /sys/devices/system/cpu/online)"
    echo "Offline CPUs: $(cat /sys/devices/system/cpu/offline)"
} >> "$LOG_FILE"

# Record the end time
end_time=$(current_datetime)
# Save the journalctl log in the output directory
echo "Saving journalctl log from $start_time to $end_time in $OUTPUT_DIR/journallog"
save_journalctl_log "$start_time" "$end_time" "$OUTPUT_DIR"

# Run plot.sh
cd "$OUTPUT_DIR"
../plot.sh
python3 ../info.py output

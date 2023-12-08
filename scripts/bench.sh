#!/bin/bash

# Function to get current date and time in the format required by journalctl
current_datetime() {
    date +"%Y-%m-%d %H:%M:%S"
}

run_command() {
    local cmd=$1
    shift
    local args=("$@")
    local cmd_string="$cmd ${args[*]}"
    local test_name="${cmd%% *}" # Get the first word in cmd_string as the test name
    local sanitized_test_name="${test_name//\//_}" # Replace slashes with underscores
    local log_file="$OUTPUT_DIR/${sanitized_test_name}.log" # Use sanitized test name as the log file name

    echo "Executing command: $cmd_string"
    echo "Saving log to $log_file"

    local duration_seconds=$(echo "$DURATION" | sed 's/[^0-9]*//g') # Convert DURATION to seconds
    local start_time=$(date +%s)

    (
        while true; do
            bash -c "$cmd_string >> $log_file 2>&1"

            local current_time=$(date +%s)
            local elapsed_time=$((current_time - start_time))

            if (( elapsed_time >= duration_seconds )); then
                break
            fi
        done
    ) &

    PIDS+=($!)  # Store PID of the subshell
}

# Assure all features are activated (needed for SMI detection in cyclictest)
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
DURATION=""
LOOP_COUNT="1000000"
RUN_HWLATDETECT=0
FACTOR=1/5000

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
        -d) DURATION="$2"; shift ;;
        --loopcount) LOOP_COUNT="$2"; shift ;;
        -l) LOOP_COUNT="$2"; shift ;;
        --stress_ng_opt) STRESS_NG_CUSTOM_OPTS="$2"; shift ;;
        --hwlatdetect) RUN_HWLATDETECT=1 ;;
        --factor) FACTOR="$2"; shift ;;
        *) echo "Error: Invalid option $1"; exit 1 ;;
    esac
    shift
done
IFS=' ' read -r -a stress_ng_opts <<< "$STRESS_NG_CUSTOM_OPTS"

# If no minute flag is given calculate the time needed
if [[ -z "$DURATION" ]]; then
    DURATION=$(echo "scale=0; $LOOP_COUNT * $FACTOR" | bc)"s"
fi

# Create an output folder
TEST_ABBREVIATIONS=""
for test in HACKBENCH DD STRESS_NG LTP STRESS; do
    if [[ ${RUN_TESTS[$test]} -eq 1 ]]; then
        TEST_ABBREVIATIONS+="${test:0:1}"
    fi
done
OUTPUT_DIR="Output_l${LOOP_COUNT//[^0-9]}_t${DURATION//[^0-9]}_${TEST_ABBREVIATIONS}_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$OUTPUT_DIR"

# Log file setup
LOG_FILE="$OUTPUT_DIR/log"
{
    echo "Duration: $DURATION"
    echo "Loop Count: $LOOP_COUNT"
    echo "Cyclictest Mode: $CYCLICTEST_MODE"
    echo "Stress-ng Custom Options: $STRESS_NG_CUSTOM_OPTS"
    echo "Run Hwlatdetect: $RUN_HWLATDETECT"
    echo "Factor: $FACTOR"
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

echo "Starting Stressors"
# Run selected tests
[[ ${RUN_TESTS[HACKBENCH]} -eq 1 ]] && run_command hackbench 20
[[ ${RUN_TESTS[DD]} -eq 1 ]] && run_command dd if=/dev/zero of=/dev/null bs=128M
[[ ${RUN_TESTS[STRESS_NG]} -eq 1 ]] && run_command stress-ng "${stress_ng_opts[@]}"
[[ ${RUN_TESTS[STRESS]} -eq 1 ]] && run_command stress --cpu 4 --vm 8 --vm-bytes 1G -t 1m
[[ ${RUN_TESTS[LTP]} -eq 1 ]] && run_command /opt/ltp/runltp -x 5 

echo "Starting Cyclictest"
# Run cyclictest based on mode
CYCLICTEST_PARAMS="-l$LOOP_COUNT --mlockall --smi --smp --priority=98 --interval=200 --distance=0 -h400 -v"
if [[ $CYCLICTEST_MODE == "docker" ]]; then
    docker run --cap-add=sys_nice --cap-add=ipc_lock --ulimit rtprio=99 --device-cgroup-rule='c 10:* rmw' -v /dev:/dev -v "$(pwd)/output:/output" --rm nconotor/rt-tests:r2 /bin/bash -c "cyclictest $CYCLICTEST_PARAMS" 2>> "$LOG_FILE" > "$OUTPUT_DIR/output"
else
    ( time cyclictest $CYCLICTEST_PARAMS ) >> "$LOG_FILE" 2>&1 > "$OUTPUT_DIR/output"
fi
echo "Done with Cyclictest"

for pid in "${PIDS[@]}"; do
    wait $pid
done

# Record the end time and save the journallog
end_time=$(current_datetime)
echo "Start Time: $start_time End Time: $end_time" >> "$LOG_FILE"

# Run plot.sh
cd "$OUTPUT_DIR"
#../plot.sh
python3 ../info.py output

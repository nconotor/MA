#!/bin/bash
# Assure all features are activated
modprobe msr

# Default settings: all tests are off except for cyclictest
declare -A RUN_TESTS=(
    [HACKBENCH]=0
    [DD]=0
    [STRESS_NG]=0
    [STRESS]=0
    [LTP]=0
    [LTP_RT]=0
    [CYCLICTEST]=1  # Cyclictest always runs
)

# Cyclictest mode: 'baremetal' or 'docker'
CYCLICTEST_MODE="baremetal"

# Default values
DURATION="210s"
LOOP_COUNT="1000000"

# Parse command-line arguments
while (( "$#" )); do
    case "$1" in
        --hackbench) RUN_TESTS[HACKBENCH]=1 ;;
        --dd) RUN_TESTS[DD]=1 ;;
        --stress-ng) RUN_TESTS[STRESS_NG]=1 ;;
        --ltp) RUN_TESTS[LTP]=1 ;;
        --ltp_rt) RUN_TESTS[LTP_RT]=1 ;;
        --stress) RUN_TESTS[STRESS]=1 ;;
        --docker) CYCLICTEST_MODE="docker" ;;
        --duration) DURATION="$2"; shift ;;
        --loopcount) LOOP_COUNT="$2"; shift ;;
        *) echo "Error: Invalid option $1"; exit 1 ;;
    esac
    shift
done

# Function to run a command in the background with timeout
run_command() {
    local cmd=$1
    timeout -k "$DURATION" "$DURATION" bash -c "while :; do $cmd > /dev/null 2>&1; done" &
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
    for test in "${!RUN_TESTS[@]}"; do
        echo "Run $test: ${RUN_TESTS[$test]}"
    done
} > "$LOG_FILE"

# Run hwlatdetect
echo "Running hwlatdetect for 60 seconds..." >> "$LOG_FILE"
hwlatdetect --duration=60s >> "$LOG_FILE" 2>&1

# Run selected tests
[[ ${RUN_TESTS[HACKBENCH]} -eq 1 ]] && run_command 'hackbench 20'
[[ ${RUN_TESTS[DD]} -eq 1 ]] && run_command 'dd if=/dev/zero of=/dev/null bs=128M'
[[ ${RUN_TESTS[STRESS_NG]} -eq 1 ]] && run_command 'stress-ng --all 1'
[[ ${RUN_TESTS[STRESS]} -eq 1 ]] && run_command 'stress --cpu 4 --vm 16 --vm-bytes 1G -t 1m'
[[ ${RUN_TESTS[LTP]} -eq 1 ]] && run_command '/opt/ltp/runltp -x 80 -R -q'

# Run LTP real-time test
if [[ ${RUN_TESTS[LTP_RT]} -eq 1 ]]; then
    CURRENT_DIR=$(pwd)
    LTP_SCRIPT_PATH="./ltp/testcases/realtime/run.sh"
    if [[ -f "$LTP_SCRIPT_PATH" ]]; then
        cd "$(dirname "$LTP_SCRIPT_PATH")"
        timeout -k "$DURATION" "$DURATION" bash -c 'while :; do ./run.sh -t all -l 1 > /dev/null 2>&1; done' &
        cd "$CURRENT_DIR"
    else
        echo "LTP script not found at $LTP_SCRIPT_PATH" >> "$LOG_FILE"
    fi
fi

# Run cyclictest based on mode
if [[ $CYCLICTEST_MODE == "docker" ]]; then
    docker run --cap-add=sys_nice --cap-add=ipc_lock --ulimit rtprio=99 --device-cgroup-rule='c 10:* rmw' -v /dev:/dev -v "$(pwd)/output:/output" --rm nconotor/rt-tests:r2 /bin/bash -c "cyclictest -l$LOOP_COUNT --mlockall --smi --smp --priority=98 --interval=200 --distance=0 -h400 -v" 2>> "$LOG_FILE" > "$OUTPUT_DIR/output"
else
    { time cyclictest -l$LOOP_COUNT --mlockall --smi --smp --priority=98 --interval=200 --distance=0 -h400 -v; } 2>> "$LOG_FILE" > "$OUTPUT_DIR/output"
fi

# Log CPU states
{
    echo "Online CPUs: $(cat /sys/devices/system/cpu/online)"
    echo "Offline CPUs: $(cat /sys/devices/system/cpu/offline)"
} >> "$LOG_FILE"

# Run plot.sh
cd "$OUTPUT_DIR"
../plot.sh
python3 ../info.py output

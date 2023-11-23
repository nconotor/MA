#!/bin/bash

# Default settings: all tests are off
RUN_HACKBENCH=0
RUN_DD=0
RUN_STRESS_NG=0
RUN_STRESS=0
RUN_CYCLICTEST=0
RUN_LTP=0 
RUN_LTP_RT=0 


# Set the duration for the stress tests
DURATION=${1:-5m}

# Set the loop count for cyclictest, defaulting to 10000000 if not provided
LOOP_COUNT=${2:-10000000}

# Parse additional command-line arguments
shift 2
while (( "$#" )); do
  case "$1" in
    --hackbench)
      RUN_HACKBENCH=1
      shift
      ;;
    --dd)
      RUN_DD=1
      shift
      ;;
    --stress-ng)
      RUN_STRESS_NG=1
      shift
      ;;
    --cyclictest)
      RUN_CYCLICTEST=1
      shift
      ;;
    --ltp)  
      RUN_LTP=1
      shift
      ;;
    --ltp_rt)  
      RUN_LTP_RT=1
      shift
      ;;
    --stress)  
      RUN_STRESS=1
      shift
      ;;
    *)
      echo "Error: Invalid option $1"
      exit 1
      ;;
  esac
done

# Create a timestamp
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# Format the duration and loop count for folder naming
FORMATTED_DURATION=$(echo $DURATION | sed 's/[^0-9]*//g')
FORMATTED_LOOP_COUNT=$(echo $LOOP_COUNT | sed 's/[^0-9]*//g')

# Create a folder name with loop count, runtime, and timestamp
OUTPUT_DIR="Output_loop${FORMATTED_LOOP_COUNT}_run${FORMATTED_DURATION}_$TIMESTAMP"
mkdir -p "$OUTPUT_DIR"

# Define file names for output and log
CYCLICTEST_OUTPUT_FILE="$OUTPUT_DIR/output"
TIME_LOG_FILE="$OUTPUT_DIR/time_log"
VAR_LOG_FILE="$OUTPUT_DIR/var_log"

# Log the variables
echo "Duration: $DURATION" > "$VAR_LOG_FILE"
echo "Loop Count: $LOOP_COUNT" >> "$VAR_LOG_FILE"
echo "Run Hackbench: $RUN_HACKBENCH" >> "$VAR_LOG_FILE"
echo "Run DD: $RUN_DD" >> "$VAR_LOG_FILE"
echo "Run Stress-ng: $RUN_STRESS_NG" >> "$VAR_LOG_FILE"
echo "Run Stress: $RUN_STRESS" >> "$VAR_LOG_FILE"
echo "Run Cyclictest: $RUN_CYCLICTEST" >> "$VAR_LOG_FILE"
echo "Run LTP: $RUN_LTP" >> "$VAR_LOG_FILE" 
echo "Run LTP_RT: $RUN_LTP_RT" >> "$VAR_LOG_FILE" 

# Run tests based on the flags set
if [ "$RUN_HACKBENCH" -eq 1 ]; then
    timeout $DURATION bash -c 'while :; do hackbench 20; done' > /dev/null 2>&1 &
    timeout $DURATION bash -c 'while :; do killall hackbench; sleep 5; done' > /dev/null 2>&1 &
fi

if [ "$RUN_DD" -eq 1 ]; then
    timeout $DURATION bash -c 'while :; do dd if=/dev/zero of=bigfile bs=1024000 count=1024; done' > /dev/null 2>&1 &
fi

if [ "$RUN_STRESS_NG" -eq 1 ]; then
    timeout $DURATION bash -c 'while :; do stress-ng --all 2; done' > /dev/null 2>&1 &
fi

if [ "$RUN_STRESS" -eq 1 ]; then
    timeout $DURATION bash -c 'while :; do stress --cpu 4 --vm 16 --vm-bytes 1G -t 1m; done' > /dev/null 2>&1 &
fi

if [ "$RUN_LTP" -eq 1 ]; then
    timeout $DURATION bash -c 'while :; do /opt/ltp/runltp -x 80 -R -q; done' > /dev/null 2>&1 &
fi

if [ "$RUN_LTP_RT" -eq 1 ]; then
    # Save the current directory
    CURRENT_DIR=$(pwd)

    # Define the LTP script path relative to the current directory
    LTP_SCRIPT_PATH="./ltp/testcases/realtime/run.sh"

    # Check if the LTP script exists
    if [ -f "$LTP_SCRIPT_PATH" ]; then
        # Change to the LTP directory
        cd $(dirname "$LTP_SCRIPT_PATH")

        # Execute the LTP script in a loop until the timeout
        timeout $DURATION bash -c 'while :; do ./run.sh -t all -l 1 > /dev/null 2>&1; done' &

        # Change back to the original directory
        cd "$CURRENT_DIR"
    else
        echo "LTP script not found at $LTP_SCRIPT_PATH"
    fi
fi

if [ "$RUN_CYCLICTEST" -eq 1 ]; then
    { time cyclictest -l$LOOP_COUNT --mlockall --smp --priority=80 --interval=200 --distance=0 -h400 -q; } 2> "$TIME_LOG_FILE" > "$CYCLICTEST_OUTPUT_FILE"
fi

# Change directory to the output directory
cd "$OUTPUT_DIR"

# Run plot.sh inside the output directory
../plot.sh

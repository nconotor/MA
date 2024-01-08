#!/bin/bash

OUTPUT_DIR=$1
LOOPCOUNT=$2

mkdir -p "$OUTPUT_DIR"

cyclictest -l $LOOPCOUNT --mlockall --smi --smp --priority=99 --interval=200 --distance=0 -h400 -v --json $OUTPUT_DIR/output.json > "$OUTPUT_DIR/output" &
CYCLICTEST_PID=$!

while kill -0 $CYCLICTEST_PID 2>/dev/null; do
    stress --cpu 4 --io 4 --vm 16 --vm-bytes 1G --timeout 60s > "$OUTPUT_DIR/stress_log.txt"
done

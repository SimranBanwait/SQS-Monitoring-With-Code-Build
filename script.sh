#!/bin/bash

QUEUE_NAME="${QUEUE_NAME:-not-provided}" 
EVENT_TYPE="${EVENT_TYPE:-unknown}"

echo "=========================================="
echo "Hello! This is my bash script running!"
echo "=========================================="

echo "Current date and time:"
date

echo "Files in this folder:"
ls -la

echo "Creating a test file..."
echo "This is a test" > output.txt

echo "Contents of the test file:"
cat output.txt

echo "=========================================="
echo "Queue Name: $QUEUE_NAME"
echo "Event Type: $EVENT_TYPE"
echo "Script completed successfully!"
echo "=========================================="
#!/bin/bash

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
echo "Script completed successfully!"
echo "=========================================="
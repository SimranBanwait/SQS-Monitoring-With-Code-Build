#!/bin/bash

set -euo pipefail  # Exit on error, undefined variables, and pipe failures

# Configuration
QUEUE_NAME="${QUEUE_NAME:-not-provided}"
EVENT_TYPE="${EVENT_TYPE:-unknown}"
AWS_REGION="${AWS_REGION:-us-west-2}"
ALARM_THRESHOLD="${ALARM_THRESHOLD:-5}"
SNS_TOPIC_ARN="${SNS_TOPIC_ARN:-arn:aws:sns:us-west-2:860265990835:test-topic}"

# Logging functions
log_info() {
    echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - $*"
}

log_error() {
    echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - $*" >&2
}

log_success() {
    echo "[SUCCESS] $(date '+%Y-%m-%d %H:%M:%S') - $*"
}

# Validation
validate_inputs() {
    log_info "Validating inputs..."
    
    if [[ "$QUEUE_NAME" == "not-provided" ]]; then
        log_error "QUEUE_NAME is not provided"
        exit 1
    fi
    
    if [[ "$EVENT_TYPE" != "CreateQueue" && "$EVENT_TYPE" != "DeleteQueue" ]]; then
        log_error "EVENT_TYPE must be either 'CreateQueue' or 'DeleteQueue', got: $EVENT_TYPE"
        exit 1
    fi
    
    log_success "Input validation passed"
}

# Get the full queue URL from queue name
get_queue_url() {
    local queue_name=$1
    log_info "Retrieving queue URL for: $queue_name"
    
    if ! queue_url=$(aws sqs get-queue-url --queue-name "$queue_name" --region "$AWS_REGION" --query 'QueueUrl' --output text 2>/dev/null); then
        log_error "Failed to retrieve queue URL for: $queue_name"
        return 1
    fi
    
    echo "$queue_url"
}

# Create CloudWatch alarm for SQS queue
create_alarm() {
    local queue_name=$1
    local alarm_name="SQS-HighMessageCount-${queue_name}"
    
    log_info "Creating CloudWatch alarm: $alarm_name"
    
    # Check if alarm already exists
    if aws cloudwatch describe-alarms --alarm-names "$alarm_name" --region "$AWS_REGION" --query 'MetricAlarms[0]' --output text 2>/dev/null | grep -q "$alarm_name"; then
        log_info "Alarm already exists: $alarm_name. Updating..."
    fi
    
    # Create the alarm with SNS notification
    if aws cloudwatch put-metric-alarm \
        --alarm-name "$alarm_name" \
        --alarm-description "Alert when SQS queue $queue_name has $ALARM_THRESHOLD or more messages available" \
        --namespace "AWS/SQS" \
        --metric-name "ApproximateNumberOfMessagesVisible" \
        --dimensions "Name=QueueName,Value=$queue_name" \
        --statistic "Average" \
        --period 60 \
        --evaluation-periods 1 \
        --threshold "$ALARM_THRESHOLD" \
        --comparison-operator "GreaterThanOrEqualToThreshold" \
        --treat-missing-data "notBreaching" \
        --alarm-actions "$SNS_TOPIC_ARN" \
        --ok-actions "$SNS_TOPIC_ARN" \
        --region "$AWS_REGION"; then
        
        log_success "CloudWatch alarm created/updated successfully: $alarm_name"
        log_info "Email notifications will be sent to: $SNS_TOPIC_ARN"
        
        # Tag the alarm for better management
        aws cloudwatch tag-resource \
            --resource-arn "arn:aws:cloudwatch:${AWS_REGION}:$(aws sts get-caller-identity --query Account --output text):alarm:${alarm_name}" \
            --tags "Key=ManagedBy,Value=EventBridge-CodeBuild" "Key=QueueName,Value=${queue_name}" \
            --region "$AWS_REGION" 2>/dev/null || log_info "Tagging skipped (might not have permissions)"
        
        return 0
    else
        log_error "Failed to create CloudWatch alarm: $alarm_name"
        return 1
    fi
}

# Delete CloudWatch alarm
delete_alarm() {
    local queue_name=$1
    local alarm_name="SQS-HighMessageCount-${queue_name}"
    
    log_info "Deleting CloudWatch alarm: $alarm_name"
    
    # Check if alarm exists
    if ! aws cloudwatch describe-alarms --alarm-names "$alarm_name" --region "$AWS_REGION" --query 'MetricAlarms[0]' --output text 2>/dev/null | grep -q "$alarm_name"; then
        log_info "Alarm does not exist (already deleted or never created): $alarm_name"
        return 0
    fi
    
    # Delete the alarm
    if aws cloudwatch delete-alarms --alarm-names "$alarm_name" --region "$AWS_REGION"; then
        log_success "CloudWatch alarm deleted successfully: $alarm_name"
        return 0
    else
        log_error "Failed to delete CloudWatch alarm: $alarm_name"
        return 1
    fi
}

# Main execution
main() {
    echo "=========================================="
    echo "SQS Queue CloudWatch Alarm Manager"
    echo "=========================================="
    
    log_info "Starting script execution..."
    log_info "Queue Name: $QUEUE_NAME"
    log_info "Event Type: $EVENT_TYPE"
    log_info "Region: $AWS_REGION"
    log_info "Threshold: $ALARM_THRESHOLD messages"
    log_info "SNS Topic: $SNS_TOPIC_ARN"
    
    # Validate inputs
    validate_inputs
    
    # Process based on event type
    case "$EVENT_TYPE" in
        CreateQueue)
            log_info "Processing CreateQueue event..."
            
            # Verify queue exists before creating alarm
            if get_queue_url "$QUEUE_NAME" >/dev/null; then
                create_alarm "$QUEUE_NAME"
            else
                log_error "Queue does not exist, cannot create alarm"
                exit 1
            fi
            ;;
            
        DeleteQueue)
            log_info "Processing DeleteQueue event..."
            delete_alarm "$QUEUE_NAME"
            ;;
            
        *)
            log_error "Unexpected event type: $EVENT_TYPE"
            exit 1
            ;;
    esac
    
    echo "=========================================="
    log_success "Script completed successfully!"
    echo "=========================================="
}

# Run main function
main
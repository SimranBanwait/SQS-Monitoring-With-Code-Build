# Automated SQS CloudWatch Alarm Management

## Overview

This project implements an automated workflow that creates and deletes CloudWatch alarms for SQS queues based on queue lifecycle events. When an SQS queue is created or deleted, the system automatically manages corresponding CloudWatch alarms that monitor message counts and send email notifications.

![image alt](https://github.com/SimranBanwait/SQS-Monitoring-With-Code-Build/blob/fca0c97e131327410ea66f19441c3c37df79e2a3/assets/Architecture.png)

## Architecture

```
SQS Queue Created/Deleted
    ↓
CloudTrail captures event
    ↓
EventBridge detects event
    ↓
CodeBuild triggered with queue details
    ↓
Bash script creates/deletes CloudWatch alarm
    ↓
CloudWatch alarm monitors queue (≥5 messages)
    ↓
SNS sends email notifications
```

## Features

- ✅ **Automatic Alarm Creation**: Creates CloudWatch alarms when SQS queues are created
- ✅ **Automatic Alarm Deletion**: Removes alarms when queues are deleted
- ✅ **Email Notifications**: Sends alerts via SNS when alarms trigger (IN ALARM state) or recover (OK state)
- ✅ **Idempotent Operations**: Safe to run multiple times
- ✅ **Error Handling**: Gracefully handles missing queues and alarms
- ✅ **Legacy Queue Support**: Works with pre-existing queues without errors

## Components

### 1. SQS Queue

![SQS Queue Creation](screenshots/sqs-queue.png)

Standard SQS queues that trigger the automation workflow when created or deleted.

### 2. CloudTrail

![CloudTrail Configuration](screenshots/cloudtrail.png)

CloudTrail captures all SQS API calls (CreateQueue, DeleteQueue) and logs them.

![CloudTrail S3 Path](screenshots/cloudtrail-s3.png)

Events are stored in S3 for audit and compliance purposes.

### 3. EventBridge Rule

![EventBridge Rule](screenshots/eventbridge-rule.png)

**Event Pattern:**
```json
{
  "source": ["aws.sqs"],
  "detail-type": ["AWS API Call via CloudTrail"],
  "detail": {
    "eventSource": ["sqs.amazonaws.com"],
    "eventName": ["CreateQueue", "DeleteQueue"]
  }
}
```

![EventBridge Event Pattern](screenshots/eventbridge-pattern.png)

**Input Transformer:**

![EventBridge Transformer](screenshots/eventbridge-transformer.png)

*Input Path:*
```json
{
  "eventName": "$.detail.eventName",
  "queueName": "$.detail.requestParameters.queueName",
  "queueUrl": "$.detail.requestParameters.queueUrl",
  "userName": "$.detail.userIdentity.userName"
}
```

*Input Template:*
```json
{
  "environmentVariablesOverride": [{
      "name": "QUEUE_NAME",
      "value": "<queueName>",
      "type": "PLAINTEXT"
    },
    {
      "name": "QUEUE_URL",
      "value": "<queueUrl>",
      "type": "PLAINTEXT"
    },
    {
      "name": "EVENT_TYPE",
      "value": "<eventName>",
      "type": "PLAINTEXT"
    }
  ]
}
```

![EventBridge Target](screenshots/eventbridge-target.png)

### 4. CodeBuild Project

![CodeBuild Execution](screenshots/codebuild-execution.png)

CodeBuild executes the bash script with environment variables passed from EventBridge.

**buildspec.yml:**
```yaml
version: 0.2

phases:
  install:
    commands:
      - echo "Step 1 - Installing packages..."
      - apt-get update
      - echo "AWS CLI version:"
      - aws --version

  pre_build:
    commands:
      - echo "Step 2 - Getting ready..."
      - echo "Current folder:"
      - pwd
      - echo "Validating AWS credentials..."
      - aws sts get-caller-identity

  build:
    commands:
      - echo "Step 3 - Running CloudWatch alarm management script..."
      - chmod +x ./script-2.sh
      - ./script-2.sh

  post_build:
    commands:
      - echo "Step 4 - All done!"
      - echo "Execution completed at $(date)"
```

### 5. CloudWatch Alarm

![CloudWatch Alarm](screenshots/cloudwatch-alarm.png)

The script creates alarms with the following configuration:
- **Metric**: `ApproximateNumberOfMessagesVisible`
- **Threshold**: ≥5 messages (configurable)
- **Period**: 60 seconds (1 minute)
- **Evaluation Period**: 1
- **Statistic**: Average
- **Actions**: Sends notifications to SNS on ALARM and OK states

### 6. SNS Topic

![SNS Topic](screenshots/sns-topic.png)

SNS topic handles email notifications:
- **Topic ARN**: `arn:aws:sns:us-west-2:860265990835:test-topic`
- **Subscriptions**: Email subscription for alerts
- **Protocol**: Email

## Files

### script-2.sh

The main automation script that:
1. Extracts queue name from queue URL (for delete events)
2. Validates input parameters
3. Creates CloudWatch alarms for new queues
4. Deletes CloudWatch alarms for deleted queues
5. Configures SNS notifications for both ALARM and OK states

Key features:
- Robust error handling with `set -euo pipefail`
- Detailed logging with timestamps
- Idempotent alarm creation/deletion
- Handles legacy queues gracefully

## Setup Instructions

### Prerequisites

1. **AWS Account** with appropriate permissions
2. **CloudTrail** enabled and logging to S3
3. **SNS Topic** created with email subscription verified
4. **CodeBuild Project** configured with source repository

### IAM Permissions

**CodeBuild Service Role:**
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ],
      "Resource": "arn:aws:logs:*:*:*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "sqs:GetQueueUrl",
        "sqs:GetQueueAttributes",
        "sqs:ListQueues"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "cloudwatch:PutMetricAlarm",
        "cloudwatch:DeleteAlarms",
        "cloudwatch:DescribeAlarms",
        "cloudwatch:TagResource"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "sns:Publish"
      ],
      "Resource": "arn:aws:sns:us-west-2:860265990835:test-topic"
    },
    {
      "Effect": "Allow",
      "Action": [
        "sts:GetCallerIdentity"
      ],
      "Resource": "*"
    }
  ]
}
```

**EventBridge Service Role:**
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "codebuild:StartBuild"
      ],
      "Resource": "arn:aws:codebuild:us-west-2:860265990835:project/YOUR_PROJECT_NAME"
    }
  ]
}
```

### Deployment Steps

1. **Clone the repository:**
   ```bash
   git clone <repository-url>
   cd <repository-name>
   ```

2. **Update configuration in script-2.sh:**
   ```bash
   # Modify these variables as needed
   AWS_REGION="us-west-2"
   ALARM_THRESHOLD="5"
   SNS_TOPIC_ARN="arn:aws:sns:us-west-2:860265990835:test-topic"
   ```

3. **Create CodeBuild project:**
   - Source: Connect to your GitHub repository
   - Environment: Ubuntu standard image
   - Buildspec: Use buildspec.yml from repository
   - Service role: Attach IAM policy from above

4. **Create EventBridge rule:**
   - Event pattern: Use JSON from EventBridge section
   - Target: Select your CodeBuild project
   - Input transformer: Configure as shown above

5. **Test the workflow:**
   ```bash
   # Create a test queue
   aws sqs create-queue --queue-name test-queue-automation
   
   # Wait for CodeBuild to complete
   # Check CloudWatch for the new alarm
   
   # Delete the test queue
   aws sqs delete-queue --queue-url <queue-url>
   
   # Verify alarm is deleted
   ```

## Configuration

### Environment Variables

The script uses these environment variables (passed from EventBridge):

| Variable | Description | Example |
|----------|-------------|---------|
| `QUEUE_NAME` | SQS queue name | `my-queue` |
| `QUEUE_URL` | Full SQS queue URL | `https://sqs.us-west-2.amazonaws.com/123456789/my-queue` |
| `EVENT_TYPE` | CloudTrail event name | `CreateQueue` or `DeleteQueue` |
| `AWS_REGION` | AWS region | `us-west-2` |
| `ALARM_THRESHOLD` | Message count threshold | `5` |
| `SNS_TOPIC_ARN` | SNS topic for notifications | `arn:aws:sns:...` |

### Customization

To modify alarm behavior, edit these values in `script-2.sh`:

```bash
# Change message threshold
ALARM_THRESHOLD="${ALARM_THRESHOLD:-200}"

# Change evaluation period (in seconds)
--period 300  # 5 minutes

# Change evaluation periods
--evaluation-periods 2  # Must breach twice
```

## Monitoring and Troubleshooting

### Check CodeBuild Logs

```bash
aws codebuild batch-get-builds --ids <build-id>
```

### Verify Alarm Creation

```bash
aws cloudwatch describe-alarms --alarm-name-prefix "SQS-HighMessageCount-"
```

### Test SNS Notifications

```bash
aws sns publish \
  --topic-arn arn:aws:sns:us-west-2:860265990835:test-topic \
  --message "Test notification"
```

### Common Issues

1. **"QUEUE_NAME is not provided" error**
   - Check EventBridge Input Transformer quotes around `<queueName>` and `<eventName>`
   - Verify CloudTrail is capturing SQS events

2. **Alarm not deleted for old queues**
   - This is expected behavior - script handles gracefully
   - Check logs: "Alarm does not exist (already deleted or never created)"

3. **No email notifications**
   - Verify SNS subscription is confirmed
   - Check SNS topic permissions
   - Verify CodeBuild role has `sns:Publish` permission

## Email Notification Examples

**ALARM State:**
```
Subject: ALARM: "SQS-HighMessageCount-my-queue" in US West (Oregon)

You are receiving this email because your Amazon CloudWatch Alarm 
"SQS-HighMessageCount-my-queue" in the US West (Oregon) region has 
entered the ALARM state, because "Threshold Crossed: 1 datapoint [210.0] 
was greater than or equal to the threshold (5.0)."
```

**OK State:**
```
Subject: OK: "SQS-HighMessageCount-my-queue" in US West (Oregon)

You are receiving this email because your Amazon CloudWatch Alarm 
"SQS-HighMessageCount-my-queue" in the US West (Oregon) region has 
returned to the OK state.
```

## Best Practices

1. **Tag your resources** for better cost tracking and management
2. **Use separate SNS topics** for different environments (dev, staging, prod)
3. **Set appropriate thresholds** based on your workload patterns
4. **Monitor CloudTrail costs** - consider using CloudWatch Events directly for high-volume workloads
5. **Version control your buildspec** and scripts for audit trail
6. **Test in non-production** before deploying to production

## Cost Considerations

- **CloudTrail**: $2.00 per 100,000 management events
- **EventBridge**: Free for custom rules
- **CodeBuild**: $0.005 per build minute (free tier: 100 minutes/month)
- **CloudWatch Alarms**: $0.10 per alarm per month
- **SNS**: $0.50 per 1 million requests + email delivery costs

Estimated cost for 100 queues: **~$10-15/month**

## Future Enhancements

- [ ] Support for FIFO queues
- [ ] Configurable alarm thresholds per queue (using tags)
- [ ] Dead Letter Queue (DLQ) alarm integration
- [ ] Slack/Teams notification support
- [ ] Multi-region support
- [ ] CloudFormation/Terraform templates
- [ ] Queue age monitoring alarms

## Contributing

Contributions are welcome! Please:
1. Fork the repository
2. Create a feature branch
3. Commit your changes
4. Push to the branch
5. Create a Pull Request

## License

MIT License - See LICENSE file for details

## Author

**DevOps Team**

For questions or support, please open an issue in the GitHub repository.

---

**Last Updated**: November 2025

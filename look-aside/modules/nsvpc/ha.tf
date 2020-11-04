# SNS Topic
resource aws_sns_topic nsva {
  count = local.create_nsva ? 1 : 0

  name = "nsva-health"
  tags = var.nsvpc_tags

  lifecycle {
    ignore_changes = [tags]
  }
}

# Cloudwatch Metric Alarm
resource aws_cloudwatch_metric_alarm nsva {
  for_each = local.create_nsva ? local.private_connection_subnets : {}

  alarm_name                = "nsva-cloudwatch-alarm-${each.key}"
  comparison_operator       = "GreaterThanOrEqualToThreshold"
  evaluation_periods        = "1"
  period                    = "10"
  metric_name               = "Health State"
  namespace                 = "Cloud One - Network Security"
  statistic                 = "Maximum"
  threshold                 = "1"
  alarm_description         = "This metric monitors the health of the NSVAs"
  datapoints_to_alarm       = "1"
  treat_missing_data        = "breaching"
  actions_enabled           = true
  alarm_actions             = [aws_sns_topic.nsva[0].arn]
  ok_actions                = [aws_sns_topic.nsva[0].arn]
  insufficient_data_actions = []
  tags                      = var.nsvpc_tags

  dimensions = {
    InstanceId = aws_instance.this[each.key].id
  }

  lifecycle {
    ignore_changes = [tags]
  }
}

# Lambda and related IAM 
resource aws_iam_policy nsva_ha_lambda_policy {
  name = "NetworkSecurity_HaLambdaInlinePolicy"

  policy = <<-EOF
    {
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "LambdaLogging",
            "Effect": "Allow",
            "Action": [
                "logs:CreateLogGroup",
                "logs:CreateLogStream",
                "logs:PutLogEvents",
                "logs:DescribeLogStreams"
            ],
            "Resource": "arn:aws:logs:*:*:*"
        },
        {
            "Sid": "ReplaceRoutes",
            "Effect": "Allow",
            "Action": [
                "ec2:ReplaceRoute",
                "ec2:DeleteRoute",
                "ec2:CreateRoute",
                "ec2:ReplaceRouteTableAssociation",
                "ec2:DescribeInstances",
                "ec2:DescribeRouteTables",
                "ec2:DescribeVpcs",
                "ssm:GetParameter",
                "ssm:PutParameter"
            ],
            "Resource": "*"
        }
      ]
    }
  EOF
}

resource aws_iam_role nsva_ha_lambda_role {
  name = "NetworkSecurity_HaLambdaRole"

  assume_role_policy = <<-EOF
    {
      "Version": "2012-10-17",
      "Statement": [
        {
          "Action": "sts:AssumeRole",
          "Principal": {
            "Service": "lambda.amazonaws.com"
          },
          "Effect": "Allow",
          "Sid": ""
        }
      ]
    }
  EOF
}

resource aws_iam_role_policy_attachment role_policy_attach {
  role       = aws_iam_role.nsva_ha_lambda_role.name
  policy_arn = aws_iam_policy.nsva_ha_lambda_policy.arn
}

# Lambda Function for HA
module lambda_nsva_ha {
  count = local.create_nsva ? 1 : 0

  source  = "terraform-aws-modules/lambda/aws"
  version = "~> 1.0"

  function_name                     = "NsvaHa"
  description                       = "Bypasses/unbypasses NSVAs for High Availability"
  handler                           = "bypass_inspection.nsva_ha_event"
  runtime                           = "python3.8"
  timeout                           = 20
  lambda_role                       = aws_iam_role.nsva_ha_lambda_role.arn
  create_role                       = false
  source_path                       = ["${path.module}/src/"]
  cloudwatch_logs_retention_in_days = 14

  environment_variables = {
    FAILOVER = var.nsva_failover ? "true" : "false"
  }

  tags = merge(var.nsvpc_tags, {
    Name="NsvaHa"
  })
}

# Allow SNS topic to invoke the NSVA HA Lambda
resource aws_lambda_permission allow_sns_to_lambda {
  count = local.create_nsva ? 1 : 0

  statement_id  = "AllowExecutionfromSNS"
  action        = "lambda:InvokeFunction"
  function_name = module.lambda_nsva_ha[0].this_lambda_function_name
  principal     = "sns.amazonaws.com"
  source_arn    = aws_sns_topic.nsva[0].arn
}

# NSVA HA Lambda function subscription to the SNS topic
resource aws_sns_topic_subscription nsva_lambda {
  count = local.create_nsva ? 1 : 0

  topic_arn = aws_sns_topic.nsva[0].arn
  protocol  = "lambda"
  endpoint  = module.lambda_nsva_ha[0].this_lambda_function_arn
}

# SSM Parameter controlling if the HA Lambda is enabled/disabled
resource aws_ssm_parameter ha_lambda_enable {
  count = local.create_nsva ? 1 : 0

  name        = "/nsva/ha_lambda_enabled"
  description = "If the NSVA HA Lambda is enabled"
  type        = "String"
  value       = var.enable_lambda ? "true" : "false"

  tags = var.nsvpc_tags

  lifecycle {
    ignore_changes = [tags]
  }
}
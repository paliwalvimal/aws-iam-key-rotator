provider "aws" {
  region  = var.region
  profile = var.profile
}

locals {
  lambda_assume_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Effect": "Allow"
    }
  ]
}
EOF
}

# DyanmoDb table for storing old keys
resource "aws_dynamodb_table" "iam_key_rotator" {
  name         = "iam-key-rotator"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "user"
  range_key    = "ak"

  attribute {
    name = "user"
    type = "S"
  }

  attribute {
    name = "ak"
    type = "S"
  }

  ttl {
    attribute_name = "delete_on"
    enabled        = true
  }

  stream_enabled   = true
  stream_view_type = "OLD_IMAGE"
}

# ====== iam-key-creator ======
resource "aws_iam_role" "iam_key_creator" {
  name                  = "iam-key-creator"
  assume_role_policy    = local.lambda_assume_policy
  force_detach_policies = true
}

resource "aws_iam_role_policy" "iam_key_creator_policy" {
  name = "iam-key-creator-policy"
  role = aws_iam_role.iam_key_creator.id

  policy = <<-EOF
  {
    "Version": "2012-10-17",
    "Statement": [
      {
        "Action": [
          "iam:ListUserTags",
          "iam:ListAccessKeys",
          "iam:ListUsers",
          "iam:CreateAccessKey"
        ],
        "Effect": "Allow",
        "Resource": "*"
      },
      {
        "Action": [
          "dynamodb:PutItem"
        ],
        "Effect": "Allow",
        "Resource": "${aws_dynamodb_table.iam_key_rotator.arn}"
      },
      {
        "Action": [
          "ses:SendEmail"
        ],
        "Effect": "Allow",
        "Resource": "*"
      }
    ]
  }
  EOF
}

resource "aws_iam_role_policy_attachment" "iam_key_creator_logs" {
  role       = aws_iam_role.iam_key_creator.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_cloudwatch_event_rule" "iam_key_creator" {
  name        = "IAMAccessKeyCreator"
  description = "Triggers a lambda function at 1200 hours UTC every day which creates a set of new access key pair for a user if the existing key pair is X days old"
  is_enabled  = true

  schedule_expression = "cron(0 12 * * ? *)"
}

resource "aws_cloudwatch_event_target" "iam_key_creator" {
  rule      = aws_cloudwatch_event_rule.iam_key_creator.name
  target_id = "TriggerIAMKeyCreatorLambda"
  arn       = aws_lambda_function.iam_key_creator.arn
}

resource "aws_lambda_permission" "iam_key_creator" {
  statement_id  = "AllowExecutionFromCloudWatch"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.iam_key_creator.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.iam_key_creator.arn
}

resource "aws_lambda_function" "iam_key_creator" {
  function_name    = "iam-key-creator"
  description      = "Create new access key pair"
  role             = aws_iam_role.iam_key_creator.arn
  filename         = "${path.module}/creator.zip"
  source_code_hash = filebase64sha256("creator.zip")
  handler          = "creator.handler"
  runtime          = var.lambda_runtime

  memory_size = var.function_memory_size
  timeout     = var.function_timeout

  environment {
    variables = {
      IAM_KEY_ROTATOR_TABLE = aws_dynamodb_table.iam_key_rotator.name
    }
  }

  depends_on = [
    data.archive_file.creator
  ]
}

# ====== iam-key-destructor ======
resource "aws_iam_role" "iam_key_destructor" {
  name                  = "iam-key-destructor"
  assume_role_policy    = local.lambda_assume_policy
  force_detach_policies = true
}

resource "aws_iam_role_policy" "iam_key_destructor_policy" {
  name = "iam-key-destructor-policy"
  role = aws_iam_role.iam_key_destructor.id

  policy = <<-EOF
  {
    "Version": "2012-10-17",
    "Statement": [
      {
        "Action": [
          "iam:DeleteAccessKey"
        ],
        "Effect": "Allow",
        "Resource": "*"
      },
      {
        "Action": [
          "dynamodb:PutItem"
        ],
        "Effect": "Allow",
        "Resource": [
          "${aws_dynamodb_table.iam_key_rotator.arn}"
        ]
      },
      {
        "Action": [
          "dynamodb:DescribeStream",
          "dynamodb:GetRecords",
          "dynamodb:GetShardIterator",
          "dynamodb:ListShards",
          "dynamodb:ListStreams"
        ],
        "Effect": "Allow",
        "Resource": [
          "${aws_dynamodb_table.iam_key_rotator.stream_arn}"
        ]
      },
      {
        "Action": [
          "ses:SendEmail"
        ],
        "Effect": "Allow",
        "Resource": "*"
      }
    ]
  }
  EOF
}

resource "aws_iam_role_policy_attachment" "iam_key_destructor_logs" {
  role       = aws_iam_role.iam_key_destructor.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_lambda_event_source_mapping" "iam_key_destructor" {
  event_source_arn  = aws_dynamodb_table.iam_key_rotator.stream_arn
  function_name     = aws_lambda_function.iam_key_destructor.arn
  starting_position = "LATEST"
}

resource "aws_lambda_function" "iam_key_destructor" {
  function_name    = "iam-key-destructor"
  description      = "Delete existing access key pair"
  role             = aws_iam_role.iam_key_destructor.arn
  filename         = "${path.module}/destructor.zip"
  source_code_hash = filebase64sha256("destructor.zip")
  handler          = "destructor.handler"
  runtime          = var.lambda_runtime

  memory_size = var.function_memory_size
  timeout     = var.function_timeout

  environment {
    variables = {
      IAM_KEY_ROTATOR_TABLE = aws_dynamodb_table.iam_key_rotator.name
    }
  }

  depends_on = [
    data.archive_file.destructor
  ]
}

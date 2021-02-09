terraform {
  backend "s3" {
    key            = "terraform.tfstate"
    bucket         = "tf-iam-key-rotator"
    profile        = "fme-infra"
    region         = "us-east-1"
    dynamodb_table = "tf-iam-key-rotator"
  }
}

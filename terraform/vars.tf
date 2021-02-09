variable "region" {
  default = "us-east-1"
}

variable "profile" {
  default = "fme-infra"
}

variable "lambda_runtime" {
  default = "python3.8"
}

variable "function_memory_size" {
  default = 128
}

variable "function_timeout" {
  default = 20
}

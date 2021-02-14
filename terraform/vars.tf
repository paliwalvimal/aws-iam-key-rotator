variable "region" {
  default = "us-east-1"
}

variable "profile" {
  default = null
}

variable "access_key" {
  default = null
}

variable "secret_key" {
  default = null
}

variable "session_token" {
  default = null
}

variable "table_name" {
  default = "iam-key-rotator"
}

variable "key_creator_role_name" {
  default = "iam-key-creator"
}

variable "key_creator_function_name" {
  default = "iam-key-creator"
}

variable "key_destructor_role_name" {
  default = "iam-key-destructor"
}

variable "key_destructor_function_name" {
  default = "iam-key-destructor"
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

variable "tags" {
  type    = map(any)
  default = {}
}

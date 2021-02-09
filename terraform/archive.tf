data "archive_file" "creator" {
  type        = "zip"
  source_file = "../creator.py"
  output_path = "${path.module}/creator.zip"
}

data "archive_file" "destructor" {
  type        = "zip"
  source_file = "../destructor.py"
  output_path = "${path.module}/destructor.zip"
}

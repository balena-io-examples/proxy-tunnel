variable "aws_region" {
  type = string
  default = "us-west-1"
}

variable "instance_type" {
  type = string
  default = "t3a.micro"
}

variable "key_pair" {
  type = string
}
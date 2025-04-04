# Variables
variable "app_name" {
  description = "Name of the application"
  default     = "medusa-backend"
}

variable "app_environment" {
  description = "Application environment"
  default     = "dev"
}

variable "dockerhub_username" {
  description = "DockerHub username"
}

variable "ec2_instance_type" {
  description = "EC2 instance type"
  default     = "t2.micro" # AWS Free Tier eligible
}

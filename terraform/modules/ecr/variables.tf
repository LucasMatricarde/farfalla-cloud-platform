variable "repositories" {
  description = "ECR repo names to create"
  type        = list(string)
  default     = ["farfalla-backend", "farfalla-frontend"]
}

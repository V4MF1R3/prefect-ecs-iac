output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.prefect_vpc.id
}

output "ecs_cluster_arn" {
  description = "ARN of the ECS cluster"
  value       = aws_ecs_cluster.prefect_cluster.arn
}

output "ecs_cluster_name" {
  description = "Name of the ECS cluster"
  value       = aws_ecs_cluster.prefect_cluster.name
}

output "private_subnet_ids" {
  description = "IDs of the private subnets"
  value       = aws_subnet.private_subnets[*].id
}

output "public_subnet_ids" {
  description = "IDs of the public subnets"
  value       = aws_subnet.public_subnets[*].id
}

output "service_discovery_namespace" {
  description = "Service discovery namespace"
  value       = aws_service_discovery_private_dns_namespace.prefect_namespace.name
}

output "task_execution_role_arn" {
  description = "ARN of the task execution role"
  value       = aws_iam_role.prefect_task_execution_role.arn
}

output "prefect_worker_service_name" {
  description = "Name of the Prefect worker ECS service"
  value       = aws_ecs_service.prefect_worker_service.name
}

output "verification_instructions" {
  description = "Instructions to verify the deployment"
  value = <<-EOT
    1. Check ECS Cluster in AWS Console:
       - Navigate to ECS Console > Clusters > prefect-cluster
       - Verify the cluster is running and the service is active
    
    2. Verify Prefect Cloud Work Pool:
       - Log into Prefect Cloud
       - Navigate to Work Pools
       - Check that '${var.work_pool_name}' is listed and shows workers as online
    
    3. View Worker Logs:
       - Go to CloudWatch Logs
       - Check log group: /ecs/prefect-worker
       - Look for successful worker startup messages
  EOT
}
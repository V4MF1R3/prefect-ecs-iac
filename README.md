# Prefect Worker on Amazon ECS - Infrastructure as Code

## Purpose

This Infrastructure as Code (IaC) solution deploys a Prefect worker on Amazon ECS using AWS Fargate. The setup includes a complete VPC with networking components, ECS cluster, IAM roles, and security configurations to run Prefect workflows in a scalable, serverless container environment.

## Tool Choice: Terraform

**Why Terraform over CloudFormation?**

1. **Cross-Cloud Compatibility**: Terraform works across multiple cloud providers, making it valuable for multi-cloud or hybrid environments
2. **Rich Ecosystem**: Extensive provider ecosystem and community modules
3. **State Management**: Superior state management with remote backends
4. **Language**: HCL (HashiCorp Configuration Language) is more readable and expressive than JSON/YAML
5. **Modularity**: Better support for reusable modules and code organization
6. **Plan Feature**: `terraform plan` provides excellent preview of changes before deployment

## Architecture Overview

The infrastructure includes:

- **VPC**: Custom VPC (10.0.0.0/16) with DNS hostnames enabled
- **Subnets**: 3 public and 3 private subnets across multiple AZs
- **Networking**: Internet Gateway, NAT Gateway, and route tables
- **Security**: Security groups with minimal required access
- **ECS**: Fargate cluster with service discovery namespace
- **IAM**: Task execution role with Secrets Manager permissions
- **Secrets**: Prefect API key stored securely in AWS Secrets Manager
- **Logging**: CloudWatch logs for monitoring and debugging

## Prerequisites

1. **AWS Account** with permissions to create:
   - VPC and networking resources
   - ECS clusters and services
   - IAM roles and policies
   - Secrets Manager secrets
   - CloudWatch log groups

2. **Tools Installation**:
   ```bash
   # Install Terraform (>= 1.2.0)
   # On macOS with Homebrew:
   brew install terraform
   
   # On Ubuntu/Debian:
   wget -O- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
   echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
   sudo apt update && sudo apt install terraform
   
   # Install AWS CLI
   curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
   unzip awscliv2.zip
   sudo ./aws/install
   ```

3. **AWS CLI Configuration**:
   ```bash
   aws configure
   # Enter your AWS Access Key ID, Secret Access Key, and default region
   ```

4. **Prefect Cloud Setup**:
   - Create account at [Prefect Cloud](https://app.prefect.cloud/)
   - Generate API key from Settings > API Keys
   - Note your Account ID and Workspace ID from the URL or dashboard

## Step-by-Step Deployment

### 1. Clone and Prepare Configuration

```bash
# Create project directory
mkdir prefect-ecs-deployment
cd prefect-ecs-deployment

# Copy the Terraform files (main.tf, variables.tf, outputs.tf)
# Create your variables file
cp terraform.tfvars.example terraform.tfvars
```

### 2. Configure Variables

Edit `terraform.tfvars` with your specific values:

```hcl
aws_region = "us-east-1"
prefect_api_key = "pnu_your_api_key_here"
prefect_account_id = "your-account-id"
prefect_workspace_id = "your-workspace-id"
work_pool_name = "ecs-work-pool"
```

**Finding Prefect Cloud Values**:
- **Account ID**: Found in URL after logging in: `https://app.prefect.cloud/account/{account-id}/...`
- **Workspace ID**: Found in workspace URL: `https://app.prefect.cloud/account/{account-id}/workspace/{workspace-id}/...`
- **API Key**: Settings > API Keys > Create API Key

### 3. Initialize and Deploy

```bash
# Initialize Terraform
terraform init

# Review the execution plan
terraform plan

# Deploy the infrastructure
terraform apply
# Type 'yes' when prompted
```

Deployment typically takes 5-10 minutes.

### 4. Create Prefect Work Pool

Before the worker can connect, create the work pool in Prefect Cloud:

```bash
# Install Prefect CLI locally (optional, for work pool creation)
pip install prefect

# Set up Prefect configuration
prefect cloud login

# Create the ECS work pool
prefect work-pool create ecs-work-pool --type ecs
```

Alternatively, create the work pool through the Prefect Cloud UI:
1. Navigate to Work Pools
2. Click "Create Work Pool"
3. Select "Amazon Elastic Container Service" type
4. Name it `ecs-work-pool`

## Verification Steps

### 1. AWS Console Verification

**ECS Cluster**:
1. Open AWS Console > ECS > Clusters
2. Click on `prefect-cluster`
3. Verify cluster is ACTIVE
4. Check Services tab - `prefect-worker-service` should be RUNNING
5. Click on the service > Tasks tab - task should be RUNNING

**CloudWatch Logs**:
1. Open AWS Console > CloudWatch > Log groups
2. Click on `/ecs/prefect-worker`
3. View recent log streams
4. Look for messages like "Worker 'dev-worker' started!"

### 2. Prefect Cloud Verification

1. Log into [Prefect Cloud](https://app.prefect.cloud/)
2. Navigate to Work Pools
3. Find `ecs-work-pool`
4. Verify it shows "Online" status with 1 worker

### 3. Test with Sample Flow (Optional)

Create a simple test flow:

```python
# test_flow.py
from prefect import flow, task

@task
def hello_task():
    print("Hello from ECS!")
    return "success"

@flow
def hello_flow():
    result = hello_task()
    return result

if __name__ == "__main__":
    hello_flow.serve(
        name="test-deployment",
        work_pool_name="ecs-work-pool"
    )
```

Deploy and run:
```bash
python test_flow.py
```

## Monitoring and Troubleshooting

### Common Issues

1. **Worker not connecting**:
   - Check API key in Secrets Manager
   - Verify work pool exists in Prefect Cloud
   - Check CloudWatch logs for error messages

2. **Task startup failures**:
   - Verify IAM permissions
   - Check container image availability
   - Review security group settings

3. **Network connectivity issues**:
   - Ensure NAT Gateway is properly configured
   - Verify route table associations
   - Check security group egress rules

### Useful Commands

```bash
# Check Terraform state
terraform show

# View specific resource
terraform state show aws_ecs_cluster.prefect_cluster

# Check logs
aws logs describe-log-groups --log-group-name-prefix "/ecs/prefect"

# List ECS services
aws ecs list-services --cluster prefect-cluster

# Describe ECS service
aws ecs describe-services --cluster prefect-cluster --services prefect-worker-service
```

## Resource Cleanup

**Important**: Always clean up resources to avoid ongoing charges.

```bash
# Destroy all resources
terraform destroy
# Type 'yes' when prompted

# Verify cleanup in AWS Console
# - Check ECS clusters are deleted
# - Verify VPC and subnets are removed
# - Confirm NAT Gateway and Elastic IP are released
```

**Manual Cleanup** (if needed):
1. Delete ECS services and tasks
2. Delete ECS cluster
3. Delete VPC and associated resources
4. Remove IAM roles and policies
5. Delete Secrets Manager secrets
6. Remove CloudWatch log groups

## Cost Considerations

**Estimated Monthly Costs** (us-east-1 region):
- **ECS Fargate**: ~$10-15/month for 0.25 vCPU, 0.5 GB RAM
- **NAT Gateway**: ~$32/month + data transfer costs
- **CloudWatch Logs**: ~$0.50/month for 1GB
- **Secrets Manager**: ~$0.40/month per secret
- **Total**: ~$43-48/month

**Cost Optimization Tips**:
- Use smaller Fargate tasks if sufficient
- Consider ECS on EC2 for higher workloads
- Implement auto-scaling based on work queue depth
- Use VPC endpoints to reduce NAT Gateway costs

## Security Best Practices

**Implemented**:
- API keys stored in AWS Secrets Manager
- Minimal IAM permissions
- Private subnets for worker containers
- Security groups with restrictive rules
- CloudWatch logging enabled

**Future Enhancements**:
- Enable VPC Flow Logs
- Implement AWS Config for compliance
- Add AWS WAF for additional protection
- Use AWS KMS for enhanced encryption

## Next Steps

1. **Auto-scaling**: Implement ECS service auto-scaling based on Prefect work queue metrics
2. **Monitoring**: Add CloudWatch alarms and SNS notifications
3. **CI/CD**: Integrate with GitHub Actions or AWS CodePipeline
4. **Multi-environment**: Create separate workspaces for dev/staging/prod
5. **High Availability**: Deploy across multiple regions

---

For questions or issues, refer to:
- [Terraform AWS Provider Documentation](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [Prefect Documentation](https://docs.prefect.io/)
- [AWS ECS Documentation](https://docs.aws.amazon.com/ecs/)
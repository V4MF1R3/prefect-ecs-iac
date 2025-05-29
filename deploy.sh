# Prefect ECS Worker Deployment Script
# This script automates the deployment process with proper error handling and validation

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if Terraform is installed
    if ! command -v terraform &> /dev/null; then
        log_error "Terraform is not installed. Please install Terraform >= 1.2.0"
        exit 1
    fi
    
    # Check Terraform version
    TERRAFORM_VERSION=$(terraform version -json | jq -r '.terraform_version')
    log_info "Terraform version: $TERRAFORM_VERSION"
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed. Please install AWS CLI"
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials not configured. Please run 'aws configure'"
        exit 1
    fi
    
    AWS_ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
    AWS_REGION=$(aws configure get region)
    log_info "AWS Account: $AWS_ACCOUNT"
    log_info "AWS Region: $AWS_REGION"
    
    # Check if terraform.tfvars exists
    if [ ! -f "terraform.tfvars" ]; then
        log_error "terraform.tfvars file not found. Please create it from terraform.tfvars.example"
        exit 1
    fi
    
    log_success "All prerequisites checked successfully"
}

# Function to initialize Terraform
init_terraform() {
    log_info "Initializing Terraform..."
    
    if terraform init; then
        log_success "Terraform initialized successfully"
    else
        log_error "Terraform initialization failed"
        exit 1
    fi
}

# Function to validate Terraform configuration
validate_terraform() {
    log_info "Validating Terraform configuration..."
    
    if terraform validate; then
        log_success "Terraform configuration is valid"
    else
        log_error "Terraform configuration validation failed"
        exit 1
    fi
}

# Function to plan Terraform deployment
plan_terraform() {
    log_info "Creating Terraform execution plan..."
    
    if terraform plan -out=tfplan; then
        log_success "Terraform plan created successfully"
        
        # Show summary of changes
        log_info "Plan Summary:"
        terraform show -json tfplan | jq -r '
            .resource_changes[] | 
            select(.change.actions[] | . != "no-op") |
            "\(.change.actions | join(",")) \(.address)"
        ' | sort
        
        echo ""
        read -p "Do you want to proceed with the deployment? (yes/no): " confirm
        if [ "$confirm" != "yes" ]; then
            log_warning "Deployment cancelled by user"
            exit 0
        fi
    else
        log_error "Terraform planning failed"
        exit 1
    fi
}

# Function to apply Terraform configuration
apply_terraform() {
    log_info "Applying Terraform configuration..."
    
    if terraform apply tfplan; then
        log_success "Infrastructure deployed successfully"
        
        # Clean up plan file
        rm -f tfplan
        
        # Show outputs
        log_info "Deployment outputs:"
        terraform output
    else
        log_error "Terraform apply failed"
        exit 1
    fi
}

# Function to verify deployment
verify_deployment() {
    log_info "Verifying deployment..."
    
    # Get cluster name from Terraform output
    CLUSTER_NAME=$(terraform output -raw ecs_cluster_name 2>/dev/null || echo "prefect-cluster")
    
    # Check ECS cluster status
    log_info "Checking ECS cluster status..."
    CLUSTER_STATUS=$(aws ecs describe-clusters --clusters "$CLUSTER_NAME" --query 'clusters[0].status' --output text 2>/dev/null || echo "NOT_FOUND")
    
    if [ "$CLUSTER_STATUS" = "ACTIVE" ]; then
        log_success "ECS cluster is active"
    else
        log_warning "ECS cluster status: $CLUSTER_STATUS"
    fi
    
    # Check ECS service status
    log_info "Checking ECS service status..."
    SERVICE_STATUS=$(aws ecs describe-services --cluster "$CLUSTER_NAME" --services prefect-worker-service --query 'services[0].status' --output text 2>/dev/null || echo "NOT_FOUND")
    
    if [ "$SERVICE_STATUS" = "ACTIVE" ]; then
        log_success "ECS service is active"
        
        # Check running tasks
        RUNNING_TASKS=$(aws ecs describe-services --cluster "$CLUSTER_NAME" --services prefect-worker-service --query 'services[0].runningCount' --output text 2>/dev/null || echo "0")
        log_info "Running tasks: $RUNNING_TASKS"
    else
        log_warning "ECS service status: $SERVICE_STATUS"
    fi
    
    # Check CloudWatch logs
    log_info "Checking CloudWatch logs..."
    LOG_GROUP="/ecs/prefect-worker"
    
    if aws logs describe-log-groups --log-group-name-prefix "$LOG_GROUP" --query 'logGroups[0].logGroupName' --output text &> /dev/null; then
        log_success "CloudWatch log group exists"
        
        # Get recent log events
        log_info "Recent log entries:"
        aws logs describe-log-streams --log-group-name "$LOG_GROUP" --order-by LastEventTime --descending --max-items 1 --query 'logStreams[0].logStreamName' --output text | xargs -I {} aws logs get-log-events --log-group-name "$LOG_GROUP" --log-stream-name {} --limit 5 --query 'events[].message' --output text | head -5
    else
        log_warning "CloudWatch log group not found or empty"
    fi
}

# Function to show post-deployment instructions
show_instructions() {
    log_info "Post-deployment instructions:"
    echo ""
    echo "1. Create Prefect Work Pool:"
    echo "   - Log into Prefect Cloud (https://app.prefect.cloud/)"
    echo "   - Navigate to Work Pools"
    echo "   - Create a new work pool named 'ecs-work-pool' with type 'Amazon Elastic Container Service'"
    echo ""
    echo "2. Verify worker connection:"
    echo "   - Check that the work pool shows 1 online worker"
    echo "   - Monitor CloudWatch logs: /ecs/prefect-worker"
    echo ""
    echo "3. Test with sample flow:"
    echo "   - Run: python sample_flow.py"
    echo ""
    echo "4. Monitor resources:"
    echo "   - ECS Console: https://console.aws.amazon.com/ecs/home?region=$(aws configure get region)#/clusters/prefect-cluster"
    echo "   - CloudWatch Logs: https://console.aws.amazon.com/cloudwatch/home?region=$(aws configure get region)#logsV2:log-groups/log-group/\$252Fecs\$252Fprefect-worker"
}

# Function to handle cleanup
cleanup() {
    log_warning "Deployment interrupted. Cleaning up..."
    rm -f tfplan
    exit 1
}

# Main deployment function
main() {
    log_info "Starting Prefect ECS Worker Deployment"
    echo "========================================"
    
    # Set up signal handlers
    trap cleanup SIGINT SIGTERM
    
    # Run deployment steps
    check_prerequisites
    init_terraform
    validate_terraform
    plan_terraform
    apply_terraform
    verify_deployment
    show_instructions
    
    log_success "Deployment completed successfully!"
    echo ""
    echo "Next steps:"
    echo "1. Create the work pool in Prefect Cloud"
    echo "2. Test with the sample flow"
    echo "3. Monitor the worker in CloudWatch logs"
}

# Command line options
case "${1:-deploy}" in
    "deploy")
        main
        ;;
    "destroy")
        log_warning "Destroying infrastructure..."
        read -p "Are you sure you want to destroy all resources? (yes/no): " confirm
        if [ "$confirm" = "yes" ]; then
            terraform destroy
            log_success "Infrastructure destroyed"
        else
            log_info "Destruction cancelled"
        fi
        ;;
    "plan")
        check_prerequisites
        init_terraform
        validate_terraform
        terraform plan
        ;;
    "status")
        verify_deployment
        ;;
    "help"|"--help"|"-h")
        echo "Usage: $0 [command]"
        echo ""
        echo "Commands:"
        echo "  deploy    Deploy the infrastructure (default)"
        echo "  destroy   Destroy all resources"
        echo "  plan      Show deployment plan"
        echo "  status    Check deployment status"
        echo "  help      Show this help message"
        ;;
    *)
        log_error "Unknown command: $1"
        echo "Use '$0 help' for usage information"
        exit 1
        ;;
esac
"""
Sample Prefect flow for testing the ECS worker deployment.
This flow demonstrates basic functionality and helps verify the worker is properly connected.
"""

from prefect import flow, task
import platform
import os
import json
from datetime import datetime

@task(name="system-info")
def get_system_info():
    """Gather system information from the container environment."""
    info = {
        "timestamp": datetime.now().isoformat(),
        "platform": platform.platform(),
        "python_version": platform.python_version(),
        "container_hostname": os.environ.get("HOSTNAME", "unknown"),
        "aws_region": os.environ.get("AWS_DEFAULT_REGION", "unknown"),
        "prefect_api_url": os.environ.get("PREFECT_API_URL", "not_set"),
        "task_family": os.environ.get("ECS_TASK_FAMILY", "unknown"),
        "cluster_name": os.environ.get("ECS_CLUSTER", "unknown")
    }
    
    print("🔍 System Information:")
    for key, value in info.items():
        print(f"  {key}: {value}")
    
    return info

@task(name="connectivity-test")
def test_connectivity():
    """Test network connectivity and external service access."""
    import urllib.request
    import urllib.error
    
    tests = []
    
    # Test internet connectivity
    try:
        response = urllib.request.urlopen("https://httpbin.org/ip", timeout=10)
        ip_info = json.loads(response.read().decode())
        tests.append({
            "test": "internet_connectivity",
            "status": "success",
            "result": ip_info
        })
    except Exception as e:
        tests.append({
            "test": "internet_connectivity", 
            "status": "failed",
            "error": str(e)
        })
    
    # Test AWS metadata service (if available)
    try:
        # ECS Task Metadata Endpoint v4
        metadata_uri = os.environ.get("ECS_CONTAINER_METADATA_URI_V4")
        if metadata_uri:
            response = urllib.request.urlopen(f"{metadata_uri}/task", timeout=5)
            task_metadata = json.loads(response.read().decode())
            tests.append({
                "test": "ecs_metadata",
                "status": "success",
                "result": {
                    "task_arn": task_metadata.get("TaskARN"),
                    "cluster": task_metadata.get("Cluster"),
                    "family": task_metadata.get("Family")
                }
            })
    except Exception as e:
        tests.append({
            "test": "ecs_metadata",
            "status": "failed", 
            "error": str(e)
        })
    
    print("Connectivity Test Results:")
    for test in tests:
        status_emoji = "✅" if test["status"] == "success" else "❌"
        print(f"  {status_emoji} {test['test']}: {test['status']}")
        if test["status"] == "failed":
            print(f"    Error: {test.get('error', 'Unknown error')}")
    
    return tests

@task(name="resource-check")
def check_resources():
    """Check container resource usage and limits."""
    import psutil
    
    # Get CPU and memory information
    cpu_percent = psutil.cpu_percent(interval=1)
    memory = psutil.virtual_memory()
    disk = psutil.disk_usage('/')
    
    resources = {
        "cpu_percent": cpu_percent,
        "memory_total_gb": round(memory.total / (1024**3), 2),
        "memory_used_gb": round(memory.used / (1024**3), 2),
        "memory_percent": memory.percent,
        "disk_total_gb": round(disk.total / (1024**3), 2),
        "disk_used_gb": round(disk.used / (1024**3), 2),
        "disk_percent": round((disk.used / disk.total) * 100, 2)
    }
    
    print("Resource Usage:")
    print(f"  CPU: {resources['cpu_percent']}%")
    print(f"  Memory: {resources['memory_used_gb']}GB / {resources['memory_total_gb']}GB ({resources['memory_percent']}%)")
    print(f"  Disk: {resources['disk_used_gb']}GB / {resources['disk_total_gb']}GB ({resources['disk_percent']}%)")
    
    return resources

@flow(name="ecs-worker-validation", 
      description="Validation flow for ECS Prefect worker deployment")
def validation_flow():
    """
    Main validation flow that tests various aspects of the ECS worker environment.
    This flow helps verify that the worker is properly deployed and functioning.
    """
    print("Starting ECS Worker Validation Flow")
    print("=" * 50)
    
    # Run all validation tasks
    system_info = get_system_info()
    connectivity_results = test_connectivity()
    resource_info = check_resources()
    
    # Summary
    summary = {
        "flow_status": "completed",
        "timestamp": datetime.now().isoformat(),
        "system_info": system_info,
        "connectivity_tests": connectivity_results,
        "resource_usage": resource_info,
        "validation_success": all(
            test["status"] == "success" for test in connectivity_results
        )
    }
    
    print("\n" + "=" * 50)
    print("Validation Summary:")
    if summary["validation_success"]:
        print("All tests passed! ECS worker is functioning correctly.")
    else:
        print("Some tests failed. Check the logs above for details.")
    
    return summary

# For local testing
if __name__ == "__main__":
    print("Running validation flow locally...")
    result = validation_flow()
    print(f"\nFlow completed with result: {result['validation_success']}")

# For deployment to Prefect Cloud
def deploy_flow():
    """Deploy this flow to Prefect Cloud for scheduled execution."""
    validation_flow.serve(
        name="ecs-worker-validation-deployment",
        work_pool_name="ecs-work-pool",
        description="Automated validation of ECS worker deployment",
        tags=["validation", "ecs", "monitoring"]
    )

# Uncomment the following line to deploy the flow
# deploy_flow()
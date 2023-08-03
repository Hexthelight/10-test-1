# Test 1 - Updated Notes
## Important Considerations of task / pod replica counts
When configuring your ECS Service / EKS Deployments, it is important to understand the sort of tasks / pods that you will be adding to these as, if you're creating a container that is naturally short lived (i.e. it executes a command and then shuts down), then as soon as it is completed, the service will then try and spin up another task in order to maintain the desired task count.

As a result, ECS Services should only be used for long lived services such as web servers like Nginx or Apache and instead for short-lived services you can trigger the tasks manually.

In order to fully test the scaling and load balancing capabilities of ECS and EKS, I will be setting up two basic Apache web servers which I can then update to demo the load balancing and auto scaling accordingly.
# ECS
## Considerations for deploying on EC2
In order to allow the EC2 instance to be configured as a container instance for your ECS services, a couple of things need to happen:
#### 1. Configure an Auto-scaling group
To start, your EC2 instance needs to be provisioned through an auto-scaling group, so that your ECS service can increase your instance count in order to support your task requirements.
#### 2. Install the ECS Container Agent
In your EC2 userdata, add the following:
```bash
#!/bin/bash
...
amazon-linux-extras disable docker
amazon-linux-extras install -y ecs; systemctl enable --now --no-block ecs.service
...
```
#### 3. inject your ECS Cluster details into your EC2
Also done as part of your EC2 userdata, if deploying via Terraform, include this line in your userdata:
```shell
echo ECS_CLUSTER=${aws_ecs_cluster.cluster.name} >> /etc/ecs/ecs.config
```

### IAM Policies
If running your ECS clusters on EC2 instances, then an important point to note is any roles that you need to attach to your ECS task also needs to be attached to your EC2 instance as well.

So, for example, if your task requires full access to DynamoDB, then you will need to attach the `AmazonDynamoDBFullAccess` policy to both your ECS task role and your EC2 instance role to allow your task to access Dynamo accordingly.
### Task Replicas
If you're hosting your ECS tasks on EC2 and they require a port on the container to be exposed, then an issue will appear in your services where only one task will be able to run, as that task will take control of the port and will prevent other tasks from being able to run as they will not be able to access that same port.

This can be circumvented by using something called "Dynamic Port Mapping", which allows your ECS cluster to automatically create a port mapping between the container port, and an ephemeral port on the host, thus allowing for multiple tasks to exist in tandem.

For example using Apache web server, the default port that the container communicates on is port 80, so if you want to create multiple Apache task on the same EC2 instance, if the port is already claimed by another task, then it will stop the production of any containers that require port 80.

However, by using dynamic port mapping, each container will have a mapping that essentially runs like `35768:80`, this means that the ELB will forward traffic from port 80 of the ELB to the port 35768 on your EC2 instance, which will then forward that traffic over to port 80 of the container, and then render the page accordingly.

>[!important]+
>It is important to note that in order for this to work successfully, your SG for your ELB and your EC2 needs to be configured to allow communication over those ephemeral ports, otherwise the health checks will fail and ECS will delete the task and restart them constantly!

The terraform configuration to enable this is as follows:
```hcl
resource "aws_ecs_task_definition" "example" {
  family = "example-family"
  execution_role_arn = aws_iam_role.example-role.arn
  container_definitions = jsonencode([
    {
      name = "web-app"
      image = "<IMAGE-URL>"
      portMappings = [
        {
          containerPort = 80
          hostPort = 0
        }
      ]
    }
  ])
}
``` 

The primary change that denotes this as a dynamic port map is setting the `hostPort` to 0.
#### Resources
- [b] [Dynamic Port Mapping helpguide](https://repost.aws/knowledge-center/dynamic-port-mapping-ecs)
- [b] [Dynamic Port Mapping Official Documentation](https://docs.aws.amazon.com/AmazonECS/latest/APIReference/API_PortMapping.html)

## Load Balancing
### Proving the Load Balancer works
In order to prove that the load balancer is working as expected (after confirming healthy tasks in the target group section of the ALB), a typical solution can be to change the index.html of one of the container instances to something unique.

In order to do so, the following steps need to be carried out:
1. Connect to your EC2 instance either via SSH or EC2 Instance Connect
2. run `sudo docker ps` to get your container ID for one of your containers
3. run `sudo docker exec -it <containerID>` to open up the executable shell of the container
4. run `cat >> /usr/local/apache2/htdocs/index.html`
5. In the prompt that follows, enter your text, such as "This is container 1!" and then press ctrl+D to save your changes

Once this is done you should be able to navigate back to your web page and refresh a couple of times and eventually your changes will appear, you should now be able to click refresh multiple times and your web servers alternate with each refresh.

# EKS
## Creating the EKS Cluster
Instead of creating an auto-scaling config like ECS, in EKS if you're not using Fargate then you need to define an "EKS Node Group" to allow EKS to create the initial pods and deployments that is necessary for EKS to run correctly.

Unlike an auto scaling group, node groups are more prescriptive with your AMI type, so instead of passing in an AMI like "i-123456789", you pass in your AMI type, such as "AL2_x86_64", which will mean that the node group provisions the relevant image based on Amazon Linux.

Similarly to your ASG however, you need to define a scaling configuration, such as the below:

```hcl
resource "aws_eks_node_group" "node_group" {
  cluster_name = "test"
  ...

  scaling_config {
    desired_size = 1
    min_size = 1
    max_size = 2
  }
}
```

In order to get your EKS cluster to communicate properly with your EC2 instances and vise versa, a few IAM policies need to be attached:

| Policy Name                        | Service to attach to |
| ---------------------------------- | -------------------- |
| AmazonEKSClusterPolicy             | EKS                  |
| AmazonEKSWorkerNodePolicy          | EC2                  |
| AmazonEKS_CNI_Policy               | EC2                  |
| AmazonEC2ContainerRegistryReadOnly | EC2                  | 

### Verifying your Node Group using eksctl
Eksctl is a command line utility for managing your EKS clusters, and can be used to verify that your EKS cluster was created correctly by running the following command: `eksctl get nodegroup --name=eks-cluster`

Because it leverages the aws-cli, you can pass in arguments such as which profile to use such as `eksctl get nodegroup --profile=project-10`

### Verifying and using kubectl with EKS
On top of using `eksctl`, which is specifically used for managing EKS clusters, you can utilise `kubectl`, the standard Kubernetes CLI tool with your EKS cluster remotely, by running the following command on your machine:
`aws eks update-kubeconfig --region <region-name> --name <cluster-name> --profile "<profile-name>"`

Running this command then allows you to run kubectl as normal and it will return all the details of your EKS cluster, so `kubectl get nodes` will return all of the nodes in your EKS Node Group.
## Creating your Kubernetes Files
For this particular test, as we are just deploying a basic Apache web server we will need a Deployment file, which is the blueprint for our pods, and a Service file which combines these into a singular service which can then be serviced through a singular route of ingress.
### Deployment
The Deployment file is as follows:
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: myapp
spec:
  replicas: 2
  selector:
    matchLabels:
      app: myapp
  template:
    metadata:
      labels:
		app: myapp
    spec:
	  containers:
	  - name: myapp
		image: httpd
		ports:
		- containerPort: 80
```

This Deployment will create 2 Apache pods and expose port 80 on each
### Service
The Service file is as follows:
```yaml
apiVersion: v1
kind: Service
metadata:
  name: myapp
spec:
  selector:
    app: myapp
  type: NodePort
  ports:
  - port: 80
	targetPort: 80
```

This Service file will pick up any pods with the label `app: myapp` and manage them as a single service.

The `type: NodePort` exposes the service to external access by exposing an ephemeral port on your node that forwards any traffic to your K8s pods.

The service file acts as a pseudo load balancer as well, 
### Applying the deployment files
Once the cluster has been created and you can verify your nodes are up and running you can then apply your kubernetes documents, first your deployment and then your service, by running the following command: `kubectl apply -f apache-deployment.yaml`

This can be used to apply your service as well.

### I'm accessing the right IP and port, why isn't it working?!
When you create an EKS Node Group, you need to be sure to add a security group that will allow access from that port, as the Node Group does not do this itself!

---
- [b] [[Test 1 - Replicas and Internal Load Balancing|Original Notes]]
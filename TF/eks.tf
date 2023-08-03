# resource "aws_eks_cluster" "example" {
#     name = "EKS-apache"
#     role_arn = aws_iam_role.eks-role.arn

#     vpc_config {
#         subnet_ids = [ aws_subnet.main-1.id, aws_subnet.main-2.id ]
#     }
# }

# resource "aws_eks_node_group" "eks_node_group" {
#     cluster_name = aws_eks_cluster.example.name
#     node_group_name = "EKS-apache"
#     node_role_arn = aws_iam_role.ec2-eks.arn
#     subnet_ids = [ aws_subnet.main-1.id, aws_subnet.main-2.id ]

#     ami_type = "AL2_x86_64"

#     instance_types = [ "t3.medium" ]

#     scaling_config {
#         desired_size = 1
#         min_size = 1
#         max_size = 2
#     }
# }

# # IAM

# data "aws_iam_policy_document" "eks" {
#   statement {
#     actions = ["sts:AssumeRole"]

#     principals {
#       type        = "Service"
#       identifiers = ["eks.amazonaws.com"]
#     }
#   }
# }

# data "aws_iam_policy_document" "ec2-eks" {
#     statement {
#         actions = ["sts:AssumeRole"]

#         principals {
#             type = "Service"
#             identifiers = ["ec2.amazonaws.com"]
#         }
#     }
# }

# resource "aws_iam_role" "eks-role" {
#     name = "eks-role"
#     assume_role_policy = data.aws_iam_policy_document.eks.json
# }

# resource "aws_iam_role" "ec2-eks" {
#     name = "ec2-node-group"
#     assume_role_policy = data.aws_iam_policy_document.ec2-eks.json
# }

# resource "aws_iam_role_policy_attachment" "eks-cluster-attachment" {
#     role = aws_iam_role.eks-role.name
#     policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
# }

# resource "aws_iam_role_policy_attachment" "example-AmazonEKSWorkerNodePolicy" {
#   policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
#   role       = aws_iam_role.ec2-eks.name
# }

# resource "aws_iam_role_policy_attachment" "example-AmazonEKS_CNI_Policy" {
#   policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
#   role       = aws_iam_role.ec2-eks.name
# }

# resource "aws_iam_role_policy_attachment" "example-AmazonEC2ContainerRegistryReadOnly" {
#   policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
#   role       = aws_iam_role.ec2-eks.name
# }
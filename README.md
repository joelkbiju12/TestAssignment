PREREQUISITES

1. Server containing aws credentials, github ssh key and kubeconfig file is used to run the serviceCreation.sh script.
2. Repository url, AWS account id, AWS region, EKS cluster name and image tag should be hard coded as variables at the beginning of  bash script.

ASSUMPTIONS

1. We are deploying the code into an existing EKS cluster.
2. serviceCreation.sh script is a one time script used to create a Kubernetes deployment, service and AWS NLB load balancer for the new application
3. Dockerfile and Github action files will be created by this script which will need to pushed to the Github repo containing the code or used accordingly.

INTRODUCTION

1. serviceCreation.sh script is used for creating and deploying the application for the first time in an existing EKS cluster

2. The  Github action yml file outputted by the script should be pushed to the code repo and as a workflow which will build and deploy updated image with all the new pushes to the main branch.

3. Kubernetes deployment and loadbalancer yaml files are created by this script.


DESCRIPTION

serviceCreation.sh 

1. Create a new kubernetes service in an existing EKS cluster for deploying our application for the first time.
2. Output the dockerfile for building the application.
3. Push the new docker image to AWS ECR repository.
4. Install kubectl ,eksctl and helm chart.
5. Create serviceaccount, IAM role for the new Kubernetes service
6. Create AWS Load balancer controller for provisioning AWS external Network load balancer along with Kubernetes load balancer service.
7. Create Kubernetes deployment and Kubernetes load balancer using yaml file for the creation of this service

NOTE: 
1. This github action commands and steps needed to setup and configure Kubernetes cluster has been written after referring to multiple sources from the web.
2. I couldn’t run or test serviceCreation.sh and Github actions due to absence of a paid AWS account to test out using EKS cluster, AWS Network load balancer and IAM.

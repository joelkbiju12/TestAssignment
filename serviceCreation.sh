#!/bin/bash

aws_account_id="123456789"
aws_region="ap-south-1"
repoUrl="https://github.com/sahiljanbandhu/Matrix-Multiplication.git"
repository="java-app"
tag="latest"
cluster_name="india_prod_cluster"


#Cloning repository

git clone $repoUrl

if [ $? -eq 0 ] 
then 
  echo "Repository cloning completed" 
else 
  echo "Repository cloning failed" >&2 
  exit 1
fi

#Creating Dockerfile

cat > Dockerfile << EOF
FROM maven
RUN apt-get update && apt-get install git
RUN mkdir /app
WORKDIR /app
RUN git clone ${repoUrl}
RUN chmod +x /app/build/libs/project.jar
EXPOSE 9000
CMD ["java", "-jar", "/app/build/libs/project.jar"]
EOF



docker build -t java-app .

if [ $? -eq 0 ] 
then 
  echo "Image created succesfully" 
else 
  echo "Image creation failed" >&2 
  exit 1
fi

#Tagging image to push to ECR

docker tag java-app ${aws_account_id}.dkr.ecr.${region}.amazonaws.com/my-repository:tag

docker push ${aws_account_id}.dkr.ecr.region.amazonaws.com/${repository}:${tag}

#Creating Github actions yml for deploying in kubernetes

cat > cd.yml <<EOF
name: cd

on:
  push:
    branches:
      - master

env: 
  AWS_REGION: ap-south-1
  ECR_REPOSITORY: java-app
  SHORT_SHA: $(echo \${{ github.sha }} | cut -c 1-8)

jobs:
  run-tests:
    runs-on: ubuntu-latest
    steps:
    - name: Clone
      uses: actions/checkout@v2

  build:
    runs-on: ubuntu-latest
    if: github.ref == 'refs/heads/master'
    needs:
      - run-tests

    steps:
    - name: Clone
      uses: actions/checkout@v2

    - name: Configure AWS credentials
      uses: aws-actions/configure-aws-credentials@v1
      with:
        aws-access-key-id: \${{ secrets.AWS_ACCESS_KEY_ID }}
        aws-secret-access-key: \${{ secrets.AWS_SECRET_ACCESS_KEY }}
        aws-region: \${{ env.AWS_REGION }}
      
    - name: Login to Amazon ECR
      id: login-ecr
      uses: aws-actions/amazon-ecr-login@v1

    - name: Build, tag, and push image to Amazon ECR
      id: build-image
      env:
        ECR_REGISTRY: \${{ steps.login-ecr.outputs.registry }}
        ECR_REPOSITORY: \${{ secrets.REPO_NAME }}
        IMAGE_TAG: latest
      run: |
        # Build a docker container and push it to ECR 
        docker build -t \$ECR_REGISTRY/\$ECR_REPOSITORY:\$IMAGE_TAG .
        echo "Pushing image to ECR..."
        docker push \$ECR_REGISTRY/\$ECR_REPOSITORY:\$IMAGE_TAG
        echo "::set-output name=image::\$ECR_REGISTRY/\$ECR_REPOSITORY:\$IMAGE_TAG"

    - name: Install kubectl
      run: |
        VERSION=$(curl --silent https://storage.googleapis.com/kubernetes-release/release/stable.txt)
        # https://github.com/aws/aws-cli/issues/6920#issuecomment-1117981158
        VERSION=v1.23.6
        curl https://storage.googleapis.com/kubernetes-release/release/\$VERSION/bin/linux/amd64/kubectl \
          --progress-bar \
          --location \
          --remote-name
        chmod +x kubectl
        sudo mv kubectl /usr/local/bin/
        echo \${{ secrets.KUBECONFIG }} | base64 --decode > kubeconfig.yaml
        
    - name: Deploy
      env:
        ECR_REGISTRY: \${{ steps.login-ecr.outputs.registry }}
        ECR_REPOSITORY: \${{ secrets.REPO_NAME }}
        IMAGE_TAG: latest
      run: |
        export ECR_REPOSITORY=\${{ env.ECR_REGISTRY }}/\${{ env.ECR_REPOSITORY }}
        export IMAGE_TAG=\${{ env.SHORT_SHA }}
        export KUBECONFIG=kubeconfig.yaml
        kubectl set image deployment/java-app app=\$ECR_REGISTRY/\$ECR_REPOSITORY:\$IMAGE_TAG 
EOF

#Installing kubectl
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
curl -LO "https://dl.k8s.io/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl.sha256"
echo "$(cat kubectl.sha256)  kubectl" | sha256sum --check
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl

# Installing eksctl
curl --silent --location "https://github.com/weaveworks/eksctl/releases/latest/download/eksctl_$(uname -s)_amd64.tar.gz" | tar xz -C /tmp
sudo mv /tmp/eksctl /usr/local/bin

#Assuming kubeconfig file is installed in the machine
aws eks --region region update-kubeconfig --name ${cluster_name}


eksctl utils associate-iam-oidc-provider \
    - region ${aws_region} \
    - cluster ${cluster_name} \
    - approve

curl -o iam_policy.json https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v2.2.0/docs/install/iam_policy.json
aws iam create-policy \
  - policy-name AWSLoadBalancerControllerIAMPolicy \
  - policy-document file://iam_policy.json

eksctl create iamserviceaccount \
--cluster ${cluster_name} - region ${aws_region} \
--namespace kube-system \
--name aws-load-balancer-controller \
--attach-policy-arn arn:aws:iam::${aws_account_id}:policy/AWSLoadBalancerControllerIAMPolicy \
--override-existing-serviceaccounts \
--approve

#Installing Helm 
curl https://baltocdn.com/helm/signing.asc | gpg --dearmor | sudo tee /usr/share/keyrings/helm.gpg > /dev/null
sudo apt-get install apt-transport-https --yes
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/helm.gpg] https://baltocdn.com/helm/stable/debian/ all main" | sudo tee /etc/apt/sources.list.d/helm-stable-debian.list
sudo apt-get update
sudo apt-get install helm

if [ $? -eq 0 ] 
then 
  echo "Helm installed successfully" 
else 
  echo "Helm installation failed" >&2 
  exit 1
fi



#Creating AWS LB Controller 
helm repo add eks https://aws.github.io/eks-charts
helm repo update
helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  - set clusterName=${cluster} \
  - set serviceAccount.create=false \
  - set serviceAccount.name=aws-load-balancer-controller


if [ $? -eq 0 ] 
then 
  echo "AWS load balancer controller deployed successfully" 
else 
  echo "AWS load balancer controller deployment failed" >&2 
  exit 1
fi

#Create Kubernetes deployment and loadbalancer resource using yaml

cat > javaAppDeployment.yaml <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: java-app-deployment
  labels:
    app: java-app
spec:
  replicas: 3
  selector:
    matchLabels:
      app: java-app
  template:
    metadata:
      labels:
        app: java-app
    spec:
      containers:
      - name: java-app
        image: ${aws_account_id}.dkr.ecr.${aws_region}.amazonaws.com/${my-repository}:latest
        ports:
        - containerPort: 80
EOF

cat > javaAppLoadBalancer.yaml <<EOF
apiVersion: v1
kind: Service
metadata:
  name: nlb
  annotations:
    service.beta.kubernetes.io/aws-load-balancer-type: external 
    service.beta.kubernetes.io/aws-load-balancer-name : mynlb 
    service.beta.kubernetes.io/aws-load-balancer-scheme: internet-facing 
    service.beta.kubernetes.io/aws-load-balancer-nlb-target-type: ip 
  namespace: workshop
  labels:
    app: nlb
spec:
  type: LoadBalancer
  ports:
    - port: 80 
      targetPort: 9000 
      name: http
  selector:
    app: java-app 
EOF 

kubectl apply -f javaAppDeployment.yaml

if [ $? -eq 0 ] 
then 
  echo "Deployment created succesfully" 
else 
  echo "Deployment failed" >&2 
  exit 1
fi


kubectl apply -f javaAppLoadBalancer.yaml

if [ $? -eq 0 ] 
then 
  echo "Network load balancer and Kubernetes service created succesfully" 
else 
  echo "Network load balancer and Kubernetes service failed" >&2 
  exit 1
fi

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
FROM openjdk:8-jre-alpine
RUN mkdir /app
WORKDIR /app
VOLUME Matrix-Multiplication .
RUN chmod +x /app/Matrix-Multiplication/Matrix/dist/Matrix.jar
EXPOSE 9000
CMD ["java", "-jar", "/app/Matrix-Multiplication/Matrix/dist/Matrix.jar"]
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

#docker push $(aws_account_id).dkr.ecr.region.amazonaws.com/$(repository):$(tag)

#Creating Github actions yml for deploying in kubernetes

#Installing kubectl
VERSION=v1.23.6
curl https://storage.googleapis.com/kubernetes-release/release/$VERSION/bin/linux/amd64/kubectl \
  --progress-bar \
  --location \
  --remote-name
chmod +x kubectl
sudo mv kubectl /usr/local/bin/
echo ${{ secrets.KUBECONFIG }} | base64 --decode > kubeconfig.yaml

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
      targetPort: 9000 #The port on the pod which is backing this service. If not specified, it is assumed to be the same as the service port.
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

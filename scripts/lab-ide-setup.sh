# Lab IDE setup from IDE-Build script
#title           lab-ide-setup.sh
#description     This script will setup the Cloud9 IDE with the prerequisite packages and code for the AWS Tech Summit 2018 K8s workshop.
#author          @buzzsurfr
#contributors    @buzzsurfr @dalbhanj @cloudymind
#Modifier        @yjeong
#date            2018-08-11
#version         0.3
#original script usage curl -sSL https://s3.amazonaws.com/lab-ide-theomazonian/lab-ide-build.sh | bash -s stable
#==============================================================================

# Install jq
sudo yum -y install jq

# Update awscli
sudo -H pip install -U awscli

# Install bash-completion
sudo yum install bash-completion -y

# Install kubectl
cat <<EOF > ./kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://packages.cloud.google.com/yum/repos/kubernetes-el7-x86_64
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://packages.cloud.google.com/yum/doc/yum-key.gpg https://packages.cloud.google.com/yum/doc/rpm-package-key.gpg
EOF
sudo mv ./kubernetes.repo /etc/yum.repos.d
sudo yum install -y kubectl
echo "source <(kubectl completion bash)" >> ~/.bashrc

# Install Heptio Authenticator
go get -u -v github.com/kubernetes-sigs/aws-iam-authenticator/cmd/aws-iam-authenticator
sudo mv ~/go/bin/aws-iam-authenticator /usr/local/bin/

# Install kops
curl -LO https://github.com/kubernetes/kops/releases/download/$(curl -s https://api.github.com/repos/kubernetes/kops/releases/latest | grep tag_name | cut -d '"' -f 4)/kops-linux-amd64
chmod +x kops-linux-amd64
sudo mv kops-linux-amd64 /usr/local/bin/kops

# Configure AWS CLI
availability_zone=$(curl http://169.254.169.254/latest/meta-data/placement/availability-zone)
export AWS_DEFAULT_REGION=${availability_zone%?}

# Lab-specific configuration
export AWS_AVAILABILITY_ZONES="$(aws ec2 describe-availability-zones --query 'AvailabilityZones[].ZoneName' --output text | awk -v OFS="," '$1=$1')"
export AWS_INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)
aws ec2 describe-instances --instance-ids $AWS_INSTANCE_ID > /tmp/instance.json
export AWS_STACK_NAME=$(jq -r '.Reservations[0].Instances[0]|(.Tags[]|select(.Key=="aws:cloudformation:stack-name")|.Value)' /tmp/instance.json)
export AWS_ENVIRONMENT=$(jq -r '.Reservations[0].Instances[0]|(.Tags[]|select(.Key=="aws:cloud9:environment")|.Value)' /tmp/instance.json)
export AWS_MASTER_STACK=${AWS_STACK_NAME%$AWS_ENVIRONMENT}
export AWS_MASTER_STACK=${AWS_MASTER_STACK%?}
export AWS_MASTER_STACK=${AWS_MASTER_STACK#aws-cloud9-}
export KOPS_STATE_STORE=s3://$(aws cloudformation describe-stack-resource --stack-name $AWS_MASTER_STACK --logical-resource-id "KopsStateStore" | jq -r '.StackResourceDetail.PhysicalResourceId')

# EKS-specific variables from CloudFormation
export EKS_VPC_ID=$(aws cloudformation describe-stacks --stack-name $AWS_MASTER_STACK | jq -r '.Stacks[0].Outputs[]|select(.OutputKey=="EksVpcId")|.OutputValue')
export EKS_SUBNET_IDS=$(aws cloudformation describe-stacks --stack-name $AWS_MASTER_STACK | jq -r '.Stacks[0].Outputs[]|select(.OutputKey=="EksVpcSubnetIds")|.OutputValue')
export EKS_SECURITY_GROUPS=$(aws cloudformation describe-stacks --stack-name $AWS_MASTER_STACK | jq -r '.Stacks[0].Outputs[]|select(.OutputKey=="EksVpcSecurityGroups")|.OutputValue')
export EKS_SERVICE_ROLE=$(aws cloudformation describe-stacks --stack-name $AWS_MASTER_STACK | jq -r '.Stacks[0].Outputs[]|select(.OutputKey=="EksServiceRoleArn")|.OutputValue')

# Persist lab variables
echo "AWS_DEFAULT_REGION=$AWS_DEFAULT_REGION" >> ~/.bashrc
echo "AWS_AVAILABILITY_ZONES=$AWS_AVAILABILITY_ZONES" >> ~/.bashrc
echo "AWS_STACK_NAME=$AWS_STACK_NAME" >> ~/.bashrc
echo "AWS_MASTER_STACK=$AWS_MASTER_STACK" >> ~/.bashrc
echo "KOPS_STATE_STORE=$KOPS_STATE_STORE" >> ~/.bashrc

# Persist EKS variables
echo "EKS_VPC_ID=$EKS_VPC_ID" >> ~/.bashrc
echo "EKS_SUBNET_IDS=$EKS_SUBNET_IDS" >> ~/.bashrc
echo "EKS_SECURITY_GROUPS=$EKS_SECURITY_GROUPS" >> ~/.bashrc
echo "EKS_SERVICE_ROLE=$EKS_SERVICE_ROLE" >> ~/.bashrc

# EKS-Optimized AMI
if [ "$AWS_DEFAULT_REGION" == "us-east-1" ]; then
#  export EKS_WORKER_AMI=ami-dea4d5a1
    export EKS_WORKER_AMI=ami-0b2ae3c6bda8b5c06
elif [ "$AWS_DEFAULT_REGION" == "us-west-2" ]; then
#  export EKS_WORKER_AMI=ami-73a6e20b
    export EKS_WORKER_AMI=ami-08cab282f9979fc7a
fi
echo "EKS_WORKER_AMI=$EKS_WORKER_AMI" >> ~/.bashrc

# Create SSH key
ssh-keygen -t rsa -N "" -f ~/.ssh/id_rsa

# Create EC2 Keypair
aws ec2 create-key-pair --key-name ${AWS_STACK_NAME} --query 'KeyMaterial' --output text > $HOME/.ssh/k8s-workshop.pem
chmod 0400 $HOME/.ssh/k8s-workshop.pem

if [ ! -d "aws-techsummit2018-kubernetes-workshop" ]; then
  # Download scripts
  git clone https://github.com/cristov/aws-techsummit2018-kubernetes-workshop.git

  # Read viriable for script
  source ~/.bashrc
fi

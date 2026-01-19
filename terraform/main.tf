provider "aws" {
  region = "ap-south-1"
}

resource "aws_instance" "ci_cd_server" {
  ami           = "ami-0f5ee92e2d63afc18"
  instance_type = "t2.medium"  # Minikube needs 2GB RAM
  key_name      = var.key_name

  user_data = <<-EOF
              #!/bin/bash
              set -e
              exec > /var/log/user-data.log 2>&1  # Log everything
              
              echo "=== Starting Full K8s Setup ==="
              
              # -----------------------------------------
              # Step 1: Install Docker
              # -----------------------------------------
              echo "Installing Docker..."
              apt update -y
              apt install -y docker.io curl conntrack
              systemctl start docker
              systemctl enable docker
              usermod -aG docker ubuntu
              
              # -----------------------------------------
              # Step 2: Install kubectl
              # -----------------------------------------
              echo "Installing kubectl..."
              curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
              install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
              rm kubectl
              
              # -----------------------------------------
              # Step 3: Install Minikube
              # -----------------------------------------
              echo "Installing Minikube..."
              curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
              install minikube-linux-amd64 /usr/local/bin/minikube
              rm minikube-linux-amd64
              
              # -----------------------------------------
              # Step 4: Start Minikube (as ubuntu user)
              # -----------------------------------------
              echo "Starting Minikube..."
              sudo -u ubuntu bash -c 'minikube start --driver=docker --force'
              
              # Wait for Minikube to be ready
              sleep 30
              
              # -----------------------------------------
              # Step 5: Pull and Load Docker Image
              # -----------------------------------------
              echo "Pulling Docker image..."
              docker pull divpandey/ci-cd-node-backend:latest
              
              echo "Loading image into Minikube..."
              sudo -u ubuntu bash -c 'minikube image load divpandey/ci-cd-node-backend:latest'
              
              # -----------------------------------------
              # Step 6: Deploy to Kubernetes
              # -----------------------------------------
              echo "Creating K8s deployment..."
              sudo -u ubuntu bash -c 'cat << DEPLOY_EOF | kubectl apply -f -
              apiVersion: apps/v1
              kind: Deployment
              metadata:
                name: node-backend
                labels:
                  app: node-backend
              spec:
                replicas: 2
                selector:
                  matchLabels:
                    app: node-backend
                template:
                  metadata:
                    labels:
                      app: node-backend
                  spec:
                    containers:
                    - name: node-backend
                      image: divpandey/ci-cd-node-backend:latest
                      imagePullPolicy: Never
                      ports:
                      - containerPort: 3000
              DEPLOY_EOF'
              
              echo "Creating K8s service..."
              sudo -u ubuntu bash -c 'cat << SVC_EOF | kubectl apply -f -
              apiVersion: v1
              kind: Service
              metadata:
                name: node-backend-service
              spec:
                type: NodePort
                selector:
                  app: node-backend
                ports:
                - protocol: TCP
                  port: 3000
                  targetPort: 3000
                  nodePort: 30000
              SVC_EOF'
              
              # Wait for pods to be ready
              echo "Waiting for pods to be ready..."
              sudo -u ubuntu bash -c 'kubectl rollout status deployment/node-backend --timeout=120s'
              
              # -----------------------------------------
              # Step 7: Setup Port Forwarding as a Service
              # -----------------------------------------
              echo "Setting up port forwarding service..."
              cat << 'SYSTEMD_EOF' > /etc/systemd/system/k8s-port-forward.service
              [Unit]
              Description=Kubernetes Port Forward for Node Backend
              After=network.target
              
              [Service]
              Type=simple
              User=ubuntu
              ExecStartPre=/bin/sleep 10
              ExecStart=/usr/local/bin/kubectl port-forward --address 0.0.0.0 svc/node-backend-service 30000:3000
              Restart=always
              RestartSec=10
              
              [Install]
              WantedBy=multi-user.target
              SYSTEMD_EOF
              
              systemctl daemon-reload
              systemctl enable k8s-port-forward
              systemctl start k8s-port-forward
              
              # -----------------------------------------
              # Step 8: Create helper scripts
              # -----------------------------------------
              echo "Creating helper scripts..."
              
              # Script to check status
              cat << 'STATUS_EOF' > /home/ubuntu/status.sh
              #!/bin/bash
              echo "=== Minikube Status ==="
              minikube status
              echo ""
              echo "=== Pods ==="
              kubectl get pods
              echo ""
              echo "=== Services ==="
              kubectl get services
              echo ""
              echo "=== Port Forward Status ==="
              systemctl status k8s-port-forward --no-pager
              STATUS_EOF
              chmod +x /home/ubuntu/status.sh
              
              # Script to redeploy (pull latest image)
              cat << 'REDEPLOY_EOF' > /home/ubuntu/redeploy.sh
              #!/bin/bash
              echo "Pulling latest image..."
              docker pull divpandey/ci-cd-node-backend:latest
              minikube image load divpandey/ci-cd-node-backend:latest
              kubectl rollout restart deployment/node-backend
              kubectl rollout status deployment/node-backend
              echo "✅ Redeployment complete!"
              REDEPLOY_EOF
              chmod +x /home/ubuntu/redeploy.sh
              
              chown ubuntu:ubuntu /home/ubuntu/*.sh
              
              echo "=== Setup Complete! ==="
              echo "App will be available at http://$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4):30000"
              EOF

  vpc_security_group_ids = [aws_security_group.allow_ssh_http.id]

  tags = {
    Name = "ci-cd-k8s-server"
  }
}

resource "aws_security_group" "allow_ssh_http" {
  name = "allow_ssh_http"

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "App Port"
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "K8s NodePort"
    from_port   = 30000
    to_port     = 30000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

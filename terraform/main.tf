provider "aws" {
  region = "ap-south-1"
}

resource "aws_instance" "ci_cd_server" {
  ami           = "ami-0f5ee92e2d63afc18"
  instance_type = "t2.medium"  # Upgraded for Minikube (needs 2GB RAM)
  key_name      = var.key_name

  user_data = <<-EOF
              #!/bin/bash
              set -e
              
              # Update system
              apt update -y
              apt install -y docker.io curl conntrack
              
              # Start Docker
              systemctl start docker
              systemctl enable docker
              usermod -aG docker ubuntu
              
              # Install kubectl
              curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
              install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
              
              # Install Minikube
              curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
              install minikube-linux-amd64 /usr/local/bin/minikube
              
              # Start Minikube as ubuntu user (will run on first SSH)
              echo '#!/bin/bash
              if ! minikube status | grep -q "Running"; then
                minikube start --driver=docker --force
              fi' > /home/ubuntu/start-minikube.sh
              chmod +x /home/ubuntu/start-minikube.sh
              chown ubuntu:ubuntu /home/ubuntu/start-minikube.sh
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

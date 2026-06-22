pipeline {
    agent any

    environment {
        AWS_REGION      = 'eu-central-1'
        AWS_ACCOUNT_ID  = '309797288544'
        ECR_REGISTRY    = "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
        BACKEND_REPO    = 'fincorp/loan-api'
        FRONTEND_REPO   = 'fincorp/loan-ui'
        // Tag combines build number + short commit SHA for full traceability.
        IMAGE_TAG       = "${env.BUILD_NUMBER}-${env.GIT_COMMIT?.take(7) ?: 'local'}"
    }

    stages {

        stage('Checkout') {
            steps {
                checkout scm
            }
        }

        stage('Build Images') {
            // Build both images in parallel to reduce pipeline wall-clock time.
            parallel {
                stage('Build Backend') {
                    steps {
                        sh """
                            docker build \
                              -t ${ECR_REGISTRY}/${BACKEND_REPO}:${IMAGE_TAG} \
                              -t ${ECR_REGISTRY}/${BACKEND_REPO}:latest \
                              ./backend
                        """
                    }
                }
                stage('Build Frontend') {
                    steps {
                        sh """
                            docker build \
                              --build-arg REACT_APP_API_URL='' \
                              -t ${ECR_REGISTRY}/${FRONTEND_REPO}:${IMAGE_TAG} \
                              -t ${ECR_REGISTRY}/${FRONTEND_REPO}:latest \
                              ./frontend
                        """
                    }
                }
            }
        }

        stage('Security Scan (Trivy)') {
            // --exit-code 1 makes Trivy fail the build on HIGH or CRITICAL findings.
            // Images never reach ECR if this stage fails — the pipeline stops here.
            parallel {
                stage('Scan Backend') {
                    steps {
                        sh """
                            trivy image \
                              --exit-code 1 \
                              --severity HIGH,CRITICAL \
                              --ignorefile .trivyignore \
                              --no-progress \
                              --format table \
                              --cache-dir /tmp/trivy-cache-backend \
                              ${ECR_REGISTRY}/${BACKEND_REPO}:${IMAGE_TAG}
                        """
                    }
                }
                stage('Scan Frontend') {
                    steps {
                        sh """
                            trivy image \
                              --exit-code 1 \
                              --severity HIGH,CRITICAL \
                              --ignorefile .trivyignore \
                              --no-progress \
                              --format table \
                              --cache-dir /tmp/trivy-cache-frontend \
                              ${ECR_REGISTRY}/${FRONTEND_REPO}:${IMAGE_TAG}
                        """
                    }
                }
            }
        }

        stage('Push to ECR') {
            // Uses short-lived ECR token (12h) — no long-lived Docker credentials stored.
            steps {
                withCredentials([[
                    $class: 'AmazonWebServicesCredentialsBinding',
                    credentialsId: 'indestructible-creds'
                ]]) {
                    sh """
                        aws ecr get-login-password --region ${AWS_REGION} | \
                          docker login --username AWS --password-stdin ${ECR_REGISTRY}

                        docker push ${ECR_REGISTRY}/${BACKEND_REPO}:${IMAGE_TAG}
                        docker push ${ECR_REGISTRY}/${FRONTEND_REPO}:${IMAGE_TAG}
                    """
                }
            }
        }
        stage('Deploy to EC2') {
            // SSHs into the app server and restarts containers with the newly pushed images.
            steps {
                withCredentials([
                    sshUserPrivateKey(
                        credentialsId: 'indestructible-ssh',
                        keyFileVariable: 'EC2_KEY'
                    ),
                    string(credentialsId: 'indestructible-ec2', variable: 'EC2_IP')
                ]) {
                    // Write compose file locally first, then scp it — avoids heredoc quoting issues over SSH.
                    sh """
                        cat > /tmp/docker-compose-deploy.yml << 'COMPOSE'
services:
  backend:
    image: ${ECR_REGISTRY}/${BACKEND_REPO}:${IMAGE_TAG}
    container_name: fincorp-api
    restart: unless-stopped

  frontend:
    image: ${ECR_REGISTRY}/${FRONTEND_REPO}:${IMAGE_TAG}
    container_name: fincorp-ui
    ports:
      - "80:80"
    depends_on:
      - backend
    restart: unless-stopped
COMPOSE
                        scp -o StrictHostKeyChecking=no -i \$EC2_KEY \
                          /tmp/docker-compose-deploy.yml ec2-user@\$EC2_IP:/tmp/docker-compose.yml

                        ssh -o StrictHostKeyChecking=no -i \$EC2_KEY ec2-user@\$EC2_IP \
                          "aws ecr get-login-password --region ${AWS_REGION} | \
                            docker login --username AWS --password-stdin ${ECR_REGISTRY} && \
                           docker rm -f fincorp-api fincorp-ui 2>/dev/null || true && \
                           docker compose -p fincorp -f /tmp/docker-compose.yml pull && \
                           docker compose -p fincorp -f /tmp/docker-compose.yml up -d"
                    """
                }
            }
        }
    }

    post {
        // Always clean up local images to keep the Jenkins agent disk free.
        always {
            sh """
                docker rmi ${ECR_REGISTRY}/${BACKEND_REPO}:${IMAGE_TAG} || true
                docker rmi ${ECR_REGISTRY}/${FRONTEND_REPO}:${IMAGE_TAG} || true
            """
        }
        success {
            echo "Pipeline succeeded. Images pushed with tag: ${IMAGE_TAG}"
        }
        failure {
            echo "Pipeline FAILED. Check Trivy scan results above — High/Critical vulnerabilities block the push."
        }
    }
}

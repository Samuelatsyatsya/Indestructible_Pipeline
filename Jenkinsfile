pipeline {
    agent any

    environment {
        AWS_REGION      = 'eu-central-1'
        AWS_ACCOUNT_ID  = '309797288544'
        ECR_REGISTRY    = "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
        BACKEND_REPO    = 'fincorp/loan-api'
        FRONTEND_REPO   = 'fincorp/loan-ui'
        // CodeArtifact npm registry — all dependency installs route through here
        // so builds survive public npmjs outages and pull from a single audited source.
        CA_DOMAIN       = 'fincorp'
        CA_REPO         = 'fincorp-npm'
        NPM_REGISTRY    = "https://${CA_DOMAIN}-${AWS_ACCOUNT_ID}.d.codeartifact.${AWS_REGION}.amazonaws.com/npm/${CA_REPO}/"
        // BuildKit is required for `docker build --secret` (keeps the CodeArtifact token out of image layers).
        DOCKER_BUILDKIT = '1'
        // Tag combines build number + short commit SHA for full traceability.
        IMAGE_TAG       = "${env.BUILD_NUMBER}-${env.GIT_COMMIT?.take(7) ?: 'local'}"
    }

    stages {

        stage('Checkout') {
            steps {
                checkout scm
            }
        }

        stage('CodeArtifact Login') {
            // Fetch a short-lived npm auth token for the FinCorp CodeArtifact repo.
            // Written to a file (chmod 600) so the parallel docker builds can mount it
            // as a BuildKit secret — the token never appears in a build-arg or image layer.
            steps {
                withCredentials([[
                    $class: 'AmazonWebServicesCredentialsBinding',
                    credentialsId: 'indestructible-creds'
                ]]) {
                    sh """
                        aws codeartifact get-authorization-token \
                          --domain ${CA_DOMAIN} \
                          --domain-owner ${AWS_ACCOUNT_ID} \
                          --region ${AWS_REGION} \
                          --query authorizationToken \
                          --output text > /tmp/ca-token.txt
                        chmod 600 /tmp/ca-token.txt
                    """
                }
            }
        }

        stage('Build Images') {
            // Build both images in parallel to reduce pipeline wall-clock time.
            // Each install routes through CodeArtifact (NPM_REGISTRY); the auth token
            // is mounted as a BuildKit secret, not baked into the image.
            parallel {
                stage('Build Backend') {
                    steps {
                        sh """
                            docker build \
                              --secret id=codeartifact_token,src=/tmp/ca-token.txt \
                              --build-arg NPM_REGISTRY='${NPM_REGISTRY}' \
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
                              --secret id=codeartifact_token,src=/tmp/ca-token.txt \
                              --build-arg NPM_REGISTRY='${NPM_REGISTRY}' \
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
        // Always clean up local images and the CodeArtifact token to keep the agent clean.
        always {
            sh """
                rm -f /tmp/ca-token.txt || true
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

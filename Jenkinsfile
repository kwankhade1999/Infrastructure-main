pipeline {

    parameters {
        choice(
            name: 'terraformAction',
            choices: ['apply', 'destroy'],
            description: 'Choose your terraform action'
        )
    }

    environment {
        AWS_ACCESS_KEY_ID     = credentials('AWS_ACCESS_KEY_ID')
        AWS_SECRET_ACCESS_KEY = credentials('AWS_SECRET_ACCESS_KEY')
        AWS_DEFAULT_REGION    = 'ap-south-1'
        TF_STATE_BUCKET       = 'quantamvector-infra-statefile-backup-kunal-2026'
    }

    agent any

    stages {

        stage('Checkout') {
            steps {
                script {
                    dir('terraform') {
                        git url: 'https://github.com/kwankhade1999/Infrastructure-main.git', branch: 'main'
                    }
                }
            }
        }

        stage('AWS Debug') {
            steps {
                sh '''
                    echo "AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY_ID"
                    aws sts get-caller-identity
                '''
            }
        }

        // ─── APPLY STAGES ─────────────────────────────────────────────────────

        stage('Plan: 0-bootstrap') {
            when { expression { params.terraformAction == 'apply' } }
            steps {
                sh 'cd terraform/0-bootstrap && terraform init -input=false'

                // FIX: corrected bucket name to include -kunal-2026 suffix
                sh 'cd terraform/0-bootstrap && terraform import aws_s3_bucket.tf_state quantamvector-infra-statefile-backup-kunal-2026 || true'
                sh 'cd terraform/0-bootstrap && terraform import aws_dynamodb_table.tf_lock quantamvector-terraform-locks || true'

                sh 'cd terraform/0-bootstrap && terraform plan -out tfplan'
                sh 'cd terraform/0-bootstrap && terraform show -no-color tfplan > tfplan.txt'
            }
        }

        stage('Approval: 0-bootstrap') {
            when { expression { params.terraformAction == 'apply' } }
            steps {
                script {
                    def plan = readFile 'terraform/0-bootstrap/tfplan.txt'
                    input message: '[0-bootstrap] Approve to proceed',
                          parameters: [text(name: 'Plan', description: 'Terraform Plan Output', defaultValue: plan)]
                }
            }
        }

        stage('Apply: 0-bootstrap') {
            when { expression { params.terraformAction == 'apply' } }
            steps {
                sh 'cd terraform/0-bootstrap && terraform apply -input=false tfplan'
            }
        }

        stage('Plan: 1-network') {
            when { expression { params.terraformAction == 'apply' } }
            steps {
                sh 'cd terraform/1-network && terraform init -input=false'
                sh 'cd terraform/1-network && terraform plan -out tfplan'
                sh 'cd terraform/1-network && terraform show -no-color tfplan > tfplan.txt'
            }
        }

        stage('Approval: 1-network') {
            when { expression { params.terraformAction == 'apply' } }
            steps {
                script {
                    def plan = readFile 'terraform/1-network/tfplan.txt'
                    input message: '[1-network] Approve to proceed',
                          parameters: [text(name: 'Plan', description: 'Terraform Plan Output', defaultValue: plan)]
                }
            }
        }

        stage('Apply: 1-network') {
            when { expression { params.terraformAction == 'apply' } }
            steps {
                sh 'cd terraform/1-network && terraform apply -input=false tfplan'
            }
        }

        stage('Plan: 2-eks') {
            when { expression { params.terraformAction == 'apply' } }
            steps {
                sh 'cd terraform/2-eks && terraform init -input=false'

                // Import existing resources BEFORE planning to avoid AlreadyExists errors
                sh 'cd terraform/2-eks && terraform import \'module.eks.module.kms.aws_kms_alias.this["cluster"]\' alias/eks/quantamvector || true'
                sh 'cd terraform/2-eks && terraform import \'module.eks.aws_eks_cluster.this[0]\' quantamvector || true'

                sh 'cd terraform/2-eks && terraform plan -out tfplan'
                sh 'cd terraform/2-eks && terraform show -no-color tfplan > tfplan.txt'
            }
        }

        stage('Approval: 2-eks') {
            when { expression { params.terraformAction == 'apply' } }
            steps {
                script {
                    def plan = readFile 'terraform/2-eks/tfplan.txt'
                    input message: '[2-eks] Approve to proceed',
                          parameters: [text(name: 'Plan', description: 'Terraform Plan Output', defaultValue: plan)]
                }
            }
        }

        stage('Apply: 2-eks') {
            when { expression { params.terraformAction == 'apply' } }
            steps {
                sh 'cd terraform/2-eks && terraform apply -input=false tfplan'
            }
        }

        // ─── DESTROY STAGES (reverse order) ───────────────────────────────────

        stage('Destroy: 2-eks') {
            when { expression { params.terraformAction == 'destroy' } }
            steps {
                sh 'cd terraform/2-eks && terraform init -input=false'
                // FIX: added -lock=false in case DynamoDB lock table is unavailable
                sh 'cd terraform/2-eks && terraform destroy -auto-approve -lock=false'
            }
        }

        stage('Destroy: 1-network') {
            when { expression { params.terraformAction == 'destroy' } }
            steps {
                sh 'cd terraform/1-network && terraform init -input=false'
                // FIX: added -lock=false in case DynamoDB lock table is unavailable
                sh 'cd terraform/1-network && terraform destroy -auto-approve -lock=false'
            }
        }

        stage('Destroy: 0-bootstrap') {
            when { expression { params.terraformAction == 'destroy' } }
            steps {
                sh 'cd terraform/0-bootstrap && terraform init -input=false'

                // FIX: empty S3 bucket before destroying (AWS blocks deletion of non-empty buckets)
                // Step 1: delete all object versions
                sh '''
                    VERSIONS=$(aws s3api list-object-versions \
                        --bucket ${TF_STATE_BUCKET} \
                        --query '{Objects: Versions[].{Key:Key,VersionId:VersionId}}' \
                        --output json 2>/dev/null)
                    if [ "$VERSIONS" != "null" ] && [ -n "$VERSIONS" ] && [ "$(echo $VERSIONS | python3 -c "import sys,json; d=json.load(sys.stdin); print(len(d.get(\'Objects\') or []))")" -gt "0" ]; then
                        aws s3api delete-objects --bucket ${TF_STATE_BUCKET} --delete "$VERSIONS" --region ap-south-1
                        echo "Deleted object versions."
                    else
                        echo "No object versions to delete."
                    fi
                '''

                // Step 2: delete all delete markers
                sh '''
                    MARKERS=$(aws s3api list-object-versions \
                        --bucket ${TF_STATE_BUCKET} \
                        --query '{Objects: DeleteMarkers[].{Key:Key,VersionId:VersionId}}' \
                        --output json 2>/dev/null)
                    if [ "$MARKERS" != "null" ] && [ -n "$MARKERS" ] && [ "$(echo $MARKERS | python3 -c "import sys,json; d=json.load(sys.stdin); print(len(d.get(\'Objects\') or []))")" -gt "0" ]; then
                        aws s3api delete-objects --bucket ${TF_STATE_BUCKET} --delete "$MARKERS" --region ap-south-1
                        echo "Deleted delete markers."
                    else
                        echo "No delete markers to delete."
                    fi
                '''

                // Step 3: now destroy bootstrap resources
                sh 'cd terraform/0-bootstrap && terraform destroy -auto-approve -lock=false'
            }
        }

    }

    post {
        success {
            echo "Terraform ${params.terraformAction} completed successfully."
        }
        failure {
            echo "Pipeline failed. Check the stage logs above."
        }
    }
}
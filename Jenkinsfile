// Runs on Jenkins' built-in node, labeled 'build' — controller and build
// execution are the same single EC2 instance, with a real Docker daemon.
// Jenkins/AWS infra lives in the separate cicd-pipeline-jfrog repo, see
// infra/jenkins-ecs/agent-ec2.tf there.
//
// Branch decides the destination repo: feature/* (and anything else not
// explicitly listed below) builds into artifact-sandbox and stops there
// — validation only, no deploy. develop/master build straight into
// artifact-release and auto-deploy to production once the Xray gate
// passes — no manual approval step.
//
// Requires a Multibranch Pipeline job (not a plain Pipeline job), so
// env.BRANCH_NAME is populated per branch.
//
// Before first run, fill in:
//   - JF_URL / DOCKER_REGISTRY  (your JFrog Cloud instance)
//   - ECS_CLUSTER / prod service name (once the app's own ECS service
//     exists — not part of this scaffold yet)
// And create Jenkins credentials:
//   - jfrog-access-token   (Secret text)

pipeline {
  agent { label 'build' }

  environment {
    JF_URL          = 'https://trialkj7tft.jfrog.io'
    DOCKER_REGISTRY = 'trialkj7tft.jfrog.io'
    APP_NAME        = 'shipit'
    SANDBOX_REPO    = 'artifact-sandbox'
    RELEASE_REPO    = 'artifact-release'
    ECS_CLUSTER     = 'jfrog-demo-app'
    AWS_DEFAULT_REGION = 'us-east-1'

    GIT_SHA   = "${env.GIT_COMMIT ? env.GIT_COMMIT.take(7) : 'local'}"
    IMAGE_TAG = "${GIT_SHA}-${env.BUILD_NUMBER}"
    BRANCH    = "${env.BRANCH_NAME ?: 'unknown'}"

    // jf's config is normally a single file shared by every build on this
    // node (~/.jfrog). Concurrent builds (e.g. master and a feature
    // branch overlapping) would otherwise race on the same "jfrog-server"
    // entry — one build's post-cleanup can delete it while another is
    // mid-flight. Isolating it per-build-per-workspace avoids that.
    JFROG_CLI_HOME_DIR = "${env.WORKSPACE}/.jfrog-cli-home"
  }

  stages {

    stage('Checkout') {
      steps { checkout scm }
    }

    stage('JFrog CLI setup') {
      steps {
        withCredentials([string(credentialsId: 'jfrog-access-token', variable: 'JF_ACCESS_TOKEN')]) {
          sh 'jf c add jfrog-server --url=$JF_URL --access-token=$JF_ACCESS_TOKEN --interactive=false'
          sh 'jf c use jfrog-server'
        }
      }
    }

    stage('Route by branch') {
      steps {
        script {
          env.IS_RELEASE  = (env.BRANCH in ['develop', 'master']).toString()
          env.TARGET_REPO = (env.IS_RELEASE == 'true') ? env.RELEASE_REPO : env.SANDBOX_REPO
          // Separate build names so each route gets its own Xray watch —
          // sandbox and release are gated separately even though both
          // currently block at the same Critical/High threshold (a
          // stricter Medium threshold on release was tried and dropped:
          // most real-world Medium findings on a Debian base image are
          // OS packages with no fix version available at all).
          env.BUILD_NAME  = (env.IS_RELEASE == 'true') ? "${env.APP_NAME}-release" : "${env.APP_NAME}-sandbox"
          // jf build-scan evaluates Xray's "build" resource type, which
          // — on this account — never actually computes violations
          // (stuck at "Not Scanned" no matter how many times it's
          // triggered), unlike the "repository" resource type, which
          // does. Gate on the pushed image directly instead, scoped to
          // the matching watch.
          env.WATCH_NAME  = (env.IS_RELEASE == 'true') ? 'release-xray-gate' : 'sandox-xray-gate'
          echo "Branch '${env.BRANCH}' -> ${env.TARGET_REPO}, build '${env.BUILD_NAME}', watch '${env.WATCH_NAME}' (release=${env.IS_RELEASE})"
        }
      }
    }

    stage('Build image') {
      steps {
        script {
          env.BASE_IMAGE = sh(
            script: "grep -oP '(?<=PYTHON_VERSION=).*' base-image.env",
            returnStdout: true
          ).trim()
        }
        sh """
          DOCKER_BUILDKIT=1 docker build \
            --provenance=false \
            --build-arg PYTHON_VERSION=${BASE_IMAGE} \
            --build-arg GIT_COMMIT=${GIT_SHA} \
            --build-arg BUILD_NUMBER=${BUILD_NUMBER} \
            --build-arg IMAGE_TAG=${IMAGE_TAG} \
            -t ${DOCKER_REGISTRY}/${TARGET_REPO}/${APP_NAME}:${IMAGE_TAG} \
            .
        """
      }
    }

    stage('Push + publish build-info') {
      steps {
        sh "jf docker push ${DOCKER_REGISTRY}/${TARGET_REPO}/${APP_NAME}:${IMAGE_TAG} --build-name=${BUILD_NAME} --build-number=${BUILD_NUMBER}"
        sh "jf rt build-collect-env ${BUILD_NAME} ${BUILD_NUMBER}"
        sh "jf rt build-add-git ${BUILD_NAME} ${BUILD_NUMBER}"
        sh "jf rt build-publish ${BUILD_NAME} ${BUILD_NUMBER}"
      }
    }

    stage('Xray scan — gate') {
      steps {
        sh "jf docker scan ${DOCKER_REGISTRY}/${TARGET_REPO}/${APP_NAME}:${IMAGE_TAG} --watches=${WATCH_NAME} --fail=true"
      }
    }

    stage('Deploy to ECS production') {
      when { environment name: 'IS_RELEASE', value: 'true' }
      steps {
        sh "aws ecs update-service --cluster ${ECS_CLUSTER} --service shipit-production --force-new-deployment"
      }
    }
  }

  post {
    always {
      sh 'jf c remove jfrog-server || true'
    }
  }
}

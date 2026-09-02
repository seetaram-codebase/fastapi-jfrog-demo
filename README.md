# fastapi-jfrog-demo

A small FastAPI app — source in `app/`, `Dockerfile`/`requirements.txt`/
`base-image.env` at repo root (the Docker build context) — and the
`Jenkinsfile` that builds it, scans it with JFrog Xray, and — depending
on branch — pushes it to `artifact-sandbox` or `artifact-release` on
JFrog Artifactory.

Jenkins and its AWS infra (the EC2 instance, security groups, etc.) live
in a separate repo: [cicd-pipeline-jfrog](https://github.com/seetaram-codebase/cicd-pipeline-jfrog).
This repo is just the application + pipeline definition Jenkins builds.

## Branch routing

| Branch | Pushes to | Deploys to prod? |
|---|---|---|
| `feature/*` (or anything else) | `artifact-sandbox` | No — stops after the Xray gate |
| `develop`, `master` | `artifact-release` (built directly, no promotion) | Yes — automatically, if the gate passes |

See `cicd-pipeline-jfrog`'s `SPEC.md` for the full gate/policy details.

## Local dry run (no Jenkins)

```
docker build --build-arg PYTHON_VERSION=3.11-slim-bookworm -t shipit:local .
docker run -p 8000:8000 shipit:local
curl localhost:8000/version
curl localhost:8000/ping
```

## Demo the Xray gate

`base-image.env` starts pinned to `3.9-slim-buster` (EOL, trips the
Xray Critical/High gate on purpose). Run `scripts/break-the-build.sh` to
toggle it to a patched base image (`3.11-slim-bookworm`), commit, push —
that's the live "blocked → fixed" demo beat.

## Jenkins setup

This repo needs to be added as the source for a Jenkins **Multibranch
Pipeline** job (not a plain Pipeline job — the `Jenkinsfile`'s
branch-routing logic depends on `env.BRANCH_NAME`, which only multibranch
jobs populate). See `cicd-pipeline-jfrog`'s `README.md` for the full
Jenkins-side setup walkthrough.

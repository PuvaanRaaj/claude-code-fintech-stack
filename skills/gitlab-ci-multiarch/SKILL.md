---
name: gitlab-ci-multiarch
description: Migrate a Fiuu/Razer GitLab CI pipeline to build multi-arch Docker images (linux/amd64 + linux/arm64) using the .build_multiarch template from server/yml backend.prepare.yml.
origin: fintech-stack
---

# GitLab CI Multi-Arch Build Migration

Migrate a `.gitlab-ci.yml` that uses the shared `server/yml` templates to build multi-arch Docker images using `.build_multiarch` instead of the single-arch `.build` + `.push` flow.

## When to Activate

- User asks to add multi-arch Docker builds to a GitLab CI pipeline
- User is migrating a service to AWS ECS (Graviton/arm64 nodes) and needs multi-arch images
- User mentions `.build_multiarch`, `buildx`, or `linux/arm64` in the context of GitLab CI

---

## What `.build_multiarch` does (from `server/yml/backend.prepare.yml`)

```yaml
.build_multiarch:
  stage: prepare
  resource_group: "MR-${CI_MERGE_REQUEST_IID}-B-${CI_COMMIT_REF_SLUG}-J-${CI_JOB_NAME}"
  variables:
    DOCKERFILE: "Dockerfile"
    BUILDX_PLATFORMS: "linux/amd64,linux/arm64"
    BUILDX_BUILDER_NAME: "buildx-${CI_PROJECT_ID}-${CI_RUNNER_ID}"
  before_script:
    - *docker_login_git2u
    - docker buildx version
    - docker buildx create --use --name ${BUILDX_BUILDER_NAME} || docker buildx use ${BUILDX_BUILDER_NAME}
    - docker buildx inspect --bootstrap
  script:
    - IMAGE_TAG=$CI_COMMIT_REF_NAME
    - if [[ "$CI_COMMIT_BRANCH" != "" ]]; then IMAGE_TAG=$CI_COMMIT_BRANCH; fi;
    # builds AND pushes to registry in one step using --push --platform
  after_script:
    - docker buildx rm ${BUILDX_BUILDER_NAME} || true
  rules:
    - *prepare_rules
  tags:
    - shell
```

Key difference from `.build`: **combines build + push in one step**. A separate `push` job is no longer needed for the main image.

---

## Migration Steps

### Step 1 — Read `.gitlab-ci.yml`

Identify:
- The `build` job (likely `extends: .build`)
- The `push` job (likely `extends: .push`)
- Any jobs with `needs: ["push"]` or `dependencies: [push]`

### Step 2 — Switch the build job

```yaml
# Before
build:
  extends: .build
  needs: ["composer", "node_modules"]
  dependencies:
    - composer
    - node_modules

# After
build:
  extends: .build_multiarch
  needs: ["composer", "node_modules"]
  dependencies:
    - composer
    - node_modules
```

Keep all existing `needs` and `dependencies` — `.build_multiarch` still requires artifacts from prior jobs.

### Step 3 — Update downstream job dependencies

Any job that previously `needed: ["push"]` should now `need: ["build"]`, because `.build_multiarch` pushes during build (no separate push step).

```yaml
# Before
some_job:
  needs: ["push"]
  dependencies:
    - push

# After
some_job:
  needs: ["build"]
  dependencies:
    - build
```

Common jobs to check: `pre-owaspzap-scan`, `owaspzap-scan`, `grype-scan`, any custom security or staging jobs.

### Step 4 — Keep the `push` job

Leave `push: extends: .push` in place. It may still be referenced by shared template jobs or security scans via the shared `backend.security.yml` or `backend.staging.yml`. Removing it can break template-defined job chains.

---

## Verification Checklist

- [ ] `build` job extends `.build_multiarch`
- [ ] No job still has `needs: ["push"]` unless intentional
- [ ] `push` job remains (do not delete)
- [ ] ECR push jobs (`push_ecr_*`) are unaffected — they pull from `CI_REGISTRY_IMAGE` which now has a multi-arch manifest

---

## Notes

- Requires a `shell`-tagged runner with Docker buildx installed
- `BUILDX_PLATFORMS` defaults to `linux/amd64,linux/arm64` — override in job variables if needed
- The `grype-scan-multiarch` job (from `backend.security.yml`) expects a job named `build` — naming the job `build` (not `build_image` etc.) satisfies this
- Builder name is scoped per project + runner to avoid conflicts in parallel pipelines

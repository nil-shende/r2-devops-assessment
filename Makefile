# Convenience wrappers - every target just calls a script in ./scripts
ENV ?= dev
TAG ?= $(shell git rev-parse HEAD 2>/dev/null)

.PHONY: test lint bootstrap build infra-plan infra deploy rollback first-deploy destroy local
test:         ; bash scripts/test.sh
lint:         ; bash scripts/validate-templates.sh && shellcheck -x -S warning scripts/*.sh deploy/codedeploy/scripts/*.sh
bootstrap:    ; bash scripts/bootstrap.sh $(GITHUB_OWNER) $(GITHUB_REPO)
build:        ; bash scripts/build-and-push.sh $(TAG)
infra-plan:   ; bash scripts/deploy-infra.sh $(ENV) plan
infra:        ; bash scripts/deploy-infra.sh $(ENV) apply
deploy:       ; bash scripts/deploy-app.sh $(ENV) $(TAG)
rollback:     ; bash scripts/rollback-app.sh $(ENV) $(ROLLBACK_TAG)
first-deploy: ; bash scripts/first-deploy.sh $(ENV)
destroy:      ; bash scripts/destroy.sh $(ENV)
local:        ; docker compose up --build

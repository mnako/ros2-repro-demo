export SOURCE_REVISION := $(shell git rev-parse HEAD)
export SOURCE_DATE_EPOCH := $(shell git show -s --format=%ct HEAD)
export OUTPUT_DIR ?= release/artifacts
# Resolve after each recipe so `make build smoke-test` sees the new archive.
export ARCHIVE ?= $(notdir $(shell printf '%s\n' "$(OUTPUT_DIR)"/demo_talker-*-$(SOURCE_REVISION)-linux-amd64.tar.gz))
export CERTIFICATE_IDENTITY ?= $(GITHUB_SERVER_URL)/$(GITHUB_WORKFLOW_REF)
export CERTIFICATE_OIDC_ISSUER ?= https://token.actions.githubusercontent.com
export REPO ?= $(GITHUB_REPOSITORY)

.PHONY: build smoke-test verify-checksum sign verify-signature publish
build:
	docker buildx bake release

smoke-test: verify-checksum
	docker buildx bake smoke-test

verify-checksum:
	cd "$$OUTPUT_DIR" && shasum -a 256 --check "$$ARCHIVE.sha256"

sign: verify-checksum
	cosign sign-blob --yes \
		--bundle "$$OUTPUT_DIR/$$ARCHIVE.sigstore.json" "$$OUTPUT_DIR/$$ARCHIVE"

verify-signature: verify-checksum
	cosign verify-blob \
		--bundle "$$OUTPUT_DIR/$$ARCHIVE.sigstore.json" \
		--certificate-identity "$$CERTIFICATE_IDENTITY" \
		--certificate-oidc-issuer "$$CERTIFICATE_OIDC_ISSUER" \
		"$$OUTPUT_DIR/$$ARCHIVE"

publish:
	gh release create \
		--generate-notes \
		--repo "$$REPO" \
		--title "$$TAG" \
		--verify-tag \
		-- "$$TAG" \
		"$$OUTPUT_DIR/$$ARCHIVE" \
		"$$OUTPUT_DIR/$$ARCHIVE.sha256" \
		"$$OUTPUT_DIR/$$ARCHIVE.sigstore.json"

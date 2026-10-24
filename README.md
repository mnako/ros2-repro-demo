# ROS 2 reproducible-build demo

A single C++ ROS 2 package, `demo_talker`, built for Linux AMD64 in a
digest-pinned ROS Humble environment.

## Summary

This repository demonstrates how to build, package, test, and release a C++ ROS 2
component with controlled inputs and verifiable artifacts:

- **Controlled builds:** Linux AMD64, a digest-pinned ROS environment, and offline
  compilation using the same Make/Bake build locally and in CI.
- **Reproducible artifacts:** the complete installed package is archived with
  normalized metadata, using the source commit's timestamp and pinned tar/gzip
  tools. The archive is the deliverable; ROS and system dependencies remain external.
- **Artifact testing:** a fresh ROS environment loads the exported package and
  checks message delivery, message content, and clean process shutdown.
- **Signed releases:** the tag workflow signs with GitHub Actions OIDC, verifies
  the expected workflow/tag identity, and publishes the archive, checksum, and
  Sigstore bundle to a GitHub Release.

Verify reproducibility by rebuilding the same source twice with the build cache
disabled and comparing the complete archives byte for byte. The
[verification procedure](#verify-reproducibility) below uses the existing Bake
release target. Matching archives demonstrate reproducibility for those inputs
and environments; repeating the comparison on separate machines provides stronger
evidence. A passing smoke test or valid signature alone does not establish this.
The tag workflow currently builds once and does not perform that comparison.

## Local build

Requirements: Git, Make, and Docker with Buildx/Bake.
On ARM hosts, Docker must support Linux AMD64 emulation.

```sh
make build
```

The archive and checksum are exported directly to `release/artifacts/`:

```text
demo_talker-<version>-<commit>-linux-amd64.tar.gz
demo_talker-<version>-<commit>-linux-amd64.tar.gz.sha256
```

Make reads the revision from `git rev-parse HEAD` and `SOURCE_DATE_EPOCH` from that commit's timestamp.

The Dockerfile reads the version from the installed `package.xml` using `xmllint`
inside the pinned ROS image.

The manifest also declares exact direct dependency versions: `rclcpp` 16.0.21 and
`std_msgs` 4.9.2, matching the pinned image. CMake reads these `version_eq`
attributes through `ament_package_xml()` and requires exact matches during
configuration; a mismatch fails the build before compilation. The numbers live
only in the manifest for build configuration. When upgrading the base image,
update these constraints deliberately if the dependency versions change.
The image digest additionally fixes transitive dependencies and distribution
package revisions that the ROS version numbers alone do not identify. The
manifest constraints do not enforce versions when launching an extracted package.

Local builds use the working tree, so commit release inputs first if the commit
in the filename is to identify everything being built.

The archive contains the complete isolated `demo_talker/` install directory:
the executable, metadata, resources, and package environment scripts. ROS 2 and
system dependencies are not bundled; running it requires a compatible Linux AMD64
ROS 2 Humble environment. Generated files under `release/` are excluded from Git.

Run the smoke test after building:

```sh
make smoke-test
```

It checks the archive checksum, then starts a fresh container from the same pinned
Linux AMD64 ROS image. It extracts the exported archive under `/tmp/installed`,
sources ROS and the package environment, starts `demo_talker`, and requires a
`release candidate message #<number>` message on `/demo_messages` within 15 seconds.

ROS 2's `launch_testing` manages process startup and shutdown; `WaitForTopics` from
`launch_testing_ros` checks message delivery. The test also checks the message
content and clean process exit. The test runner has a 25-second timeout.

Test logic lives in
`tests/test_installed_package.py` and is linted with `ament_flake8` inside the pinned
image. Bake controls the image and artifact input. `OUTPUT_DIR` and `ARCHIVE` can
select a different exported package.

`.github/workflows/test.yml` runs the build and smoke test on pull requests and
branch pushes, using a native Linux AMD64 runner with read-only repository
permissions.

The Makefile also provides `make verify-checksum`, `make sign`,
`make verify-signature`, and `make publish`. Signing and signature verification
check the checksum first; the workflow verifies the signature before publishing.
These targets select the exported Linux AMD64 archive matching the current commit.
If multiple package versions were built at the same commit, specify `ARCHIVE`
explicitly. `shasum` is used for checksum verification on both macOS and Ubuntu.

To verify a downloaded release using the Makefile from the repository root:

```sh
OUTPUT_DIR=downloaded-release \
ARCHIVE='demo_talker-0.1.0-<commit>-linux-amd64.tar.gz' \
CERTIFICATE_IDENTITY=https://github.com/OWNER/REPOSITORY/.github/workflows/release.yml@refs/tags/v0.1.0 \
make verify-signature
```

Replace the example archive and identity with the expected release values.
`make sign` uses Cosign's keyless authentication, which is automatic in Actions
and interactive locally. A local signature has the local signer's identity.
For local signatures, set both `CERTIFICATE_IDENTITY` and
`CERTIFICATE_OIDC_ISSUER` to the expected signer and identity provider when using
`make verify-signature`. The issuer defaults to GitHub Actions for release builds.

`make publish` takes `TAG` and `REPO`; in Actions, the repository and expected
certificate identity default to the workflow environment. Release notes are
generated by GitHub. Before local publication, run `make verify-signature` with the
expected `CERTIFICATE_IDENTITY`, then use `make publish` with an authenticated
GitHub CLI.

## Tagged releases

Pushing any tag triggers `.github/workflows/release.yml`. Branch pushes and tag
deletions do not build a release. The workflow must exist in the tagged commit.

The workflow checks out the triggering commit and runs `make build` once on an
Ubuntu AMD64 runner. It runs `make smoke-test` before `make sign`,
`make verify-signature`, and
`make publish` to check the archive checksum, sign with the GitHub Actions
identity, verify the signature,
and publish a GitHub Release named after the existing tag.

Each release has three assets:

```text
demo_talker-<version>-<commit>-linux-amd64.tar.gz
demo_talker-<version>-<commit>-linux-amd64.tar.gz.sha256
demo_talker-<version>-<commit>-linux-amd64.tar.gz.sigstore.json
```

The Sigstore bundle contains the signature and verification material. No private
signing-key secret is needed: the job uses `id-token: write` for signing and
`contents: write` with the automatic `GITHUB_TOKEN` for publication. Sigstore's
public transparency service records signing information, including the workflow
identity. The official actions are pinned to release commit SHAs; Cosign is pinned
to version 3.1.4.

Build, smoke-test, checksum, or signature failures stop publication. An existing
release makes creation fail; the workflow does not replace its assets. Assets are kept as GitHub Release downloads rather
than retention-limited Actions artifacts. This first workflow performs one build;
it does not claim to verify reproducibility by comparing independent builds.

## Download and verify a release

With GitHub CLI and Cosign 3.1.4 installed, replace the repository and tag below.
Use a new directory for each download:

```sh
REPO=OWNER/REPOSITORY
TAG=v0.1.0
mkdir downloaded-release
cd downloaded-release
gh release download "$TAG" --repo "$REPO" \
  --pattern '*.tar.gz' --pattern '*.tar.gz.sha256' --pattern '*.tar.gz.sigstore.json'

sha256sum --check ./*.sha256
# On macOS, use: shasum -a 256 --check ./*.sha256

for archive in ./*.tar.gz; do
  cosign verify-blob \
    --bundle "${archive}.sigstore.json" \
    --certificate-identity "https://github.com/${REPO}/.github/workflows/release.yml@refs/tags/${TAG}" \
    --certificate-oidc-issuer "https://token.actions.githubusercontent.com" \
    "$archive"
done
```

The checksum checks file integrity. Signature verification authenticates the
archive against the expected repository, workflow, and tag identity. A modified
archive fails signature verification; a signature does not prove reproducibility.

## Verify reproducibility

Run this from a clean checkout of the commit being verified, with the default
build inputs. Keep the source unchanged between builds. Each build exports into
a new directory, and `--no-cache` forces compilation and packaging to run again:

```sh
(
  set -eu
  export SOURCE_REVISION="$(git rev-parse HEAD)"
  export SOURCE_DATE_EPOCH="$(git show -s --format=%ct HEAD)"
  mkdir -p release
  verification_dir="$(mktemp -d "$PWD/release/reproducibility.XXXXXX")"

  OUTPUT_DIR="$verification_dir/first" docker buildx bake --no-cache release
  OUTPUT_DIR="$verification_dir/second" docker buildx bake --no-cache release

  cmp "$verification_dir/first/"*.tar.gz "$verification_dir/second/"*.tar.gz
  shasum -a 256 "$verification_dir/first/"*.tar.gz \
    "$verification_dir/second/"*.tar.gz
  printf 'Reproducibility check passed: byte-identical archives.\n'
)
```

`cmp` exits unsuccessfully if the archive bytes differ. Both outputs remain under `release/` for
inspection. These commands supply the same Git metadata as Make and use the same
Bake target as `make build`, with caching disabled for this check.

For independent verification, repeat an uncached build on another machine using
the same commit, pinned image, and Linux AMD64 target, then compare its archive
with the first machine's archive. To verify a published release is reproducible,
check out its tagged commit and compare the rebuilt archive with the downloaded,
signature-verified release archive. Compare the `.tar.gz` files; signatures use
per-signing identity and time information and are not expected to be byte-identical.

## Build process

```text
Compile → install → deterministic archive → export to release/
```

The Dockerfile builds with colcon and packages with GNU tar/gzip inside the pinned
image. Bake specifies the platform, build arguments, and local exporter. Compilation
and packaging have networking disabled; Docker may contact the registry for the
base image. The final `scratch` stage exports only the archive and checksum.

The archive recipe normalizes entry ordering, timestamps, numeric ownership, PAX
header names, and gzip metadata while preserving file contents and permissions.
See the [GNU tar reproducibility guidance](https://www.gnu.org/software/tar/manual/html_node/Reproducibility.html).

# image-build-calico-operator

This repo builds a hardened, statically-linked Go binary from
[github.com/tigera/operator](https://github.com/tigera/operator) and packages it in a minimal SLE BCI
(`registry.suse.com/bci/bci-nano`) based image.

Binaries are compiled against [`rancher/hardened-build-base`](https://github.com/rancher/image-build-base),
which provides the latest supported Go toolchain (FIPS/BoringCrypto-enabled on amd64).

## Images produced

- `rancher/hardened-calico-operator` — Calico operator (Tigera operator)

## Building locally

```sh
make build-image         # build for the host architecture
make image-scan          # run Trivy against the built image(s)
```

The upstream version is controlled by the [`TAG`](./TAG) file.
A `-buildYYYYMMDD` suffix (`BUILD_META`) is appended automatically and is required on
release tags.

## Exact Calico component tags

This hardened operator adds the downstream runtime setting
`CALICO_IMAGE_TAG_OVERRIDES`. Upstream does not provide this environment interface.
Set it on the operator Deployment to a JSON object mapping upstream Calico image
basenames to complete image tags:

```yaml
tigeraOperator:
  env:
    - name: CALICO_IMAGE_TAG_OVERRIDES
      value: '{"calico":"v3.33.0-build20261022","node":"v3.33.0-build20261022","third-party-cni-plugins":"v3.33.0-build20261022"}'
```

The existing chart forwards `tigeraOperator.env`; no chart change is required.

Resolution order:

1. A selected ImageSet retains upstream digest resolution and validation.
   Missing entries and invalid ImageSets remain errors; overrides cannot provide
   a fallback.
2. Without an ImageSet, an explicitly configured Calico component uses its exact
   tag, after existing component replacement selection.
3. Unlisted components retain their compiled upstream versions.

### Downstream patch and tests

The version-specific [patch](./patches/0001-calico-image-tag-overrides.patch)
adds startup validation and the final tag-selection hook without changing
upstream component definitions. 

### Debugging and updating the patch

The `operator-dev` target provides the patched checkout and build dependencies
**before tests and compilation**, even when Go code is broken.

```sh
make build-dev
make dev-shell
```

Edit source, use the upstream Makefile, or run:

```sh
go test -p 2 ./pkg/components ./pkg/render ./pkg/render/kubecontrollers \
  ./pkg/render/whisker ./pkg/controller/utils/imageset
```

Export from a **second host terminal** while the container runs:

```sh
make export-patch
```

Export replaces `patches/0001-calico-image-tag-overrides.patch`; use
`PATCH_FILE=review.patch` to save separately. 

Exiting preserves edits. Resume instead of creating another container:

```sh
docker start -ai calico-operator-dev
```
Review the exported patch, then run `make build-dev` to check application and
`make build-image` for tests and hardened compilation. Builds use exported
patches, not container edits.

## Automated updates

[Updatecli](./updatecli) keeps two things current via daily PRs:

- the upstream `calico-operator` version (`TAG`), and
- the `rancher/hardened-build-base` version (`Dockerfile` `GO_IMAGE`).

## CI

- **Build**: builds the image and runs a [Trivy](https://github.com/aquasecurity/trivy) scan
  (`CRITICAL,HIGH`) on every PR/push.
- **Release**: on a published GitHub release, builds multi-arch images and pushes them to
  the Rancher Prime registry (`registry.rancher.com/rancher/hardened-calico-operator`).

# Third-Party Notices

This repository builds and publishes container images that include third-party open-source software.

The notices below are provided for attribution and license transparency. They do not replace the full license texts of the referenced projects or packages.

## RocksDB

- Project: RocksDB
- Upstream: https://github.com/facebook/rocksdb
- License: Apache License 2.0
- Copyright: Facebook, Inc. and its affiliates

Rockspack builds and packages RocksDB shared libraries and public headers for reusable Linux container images.

RocksDB is licensed under the Apache License, Version 2.0. A copy of the license should be included in this repository or image distribution when required by the applicable license obligations.

## Ubuntu Base Image

- Project: Ubuntu
- Upstream: https://ubuntu.com
- Container image source: https://hub.docker.com/_/ubuntu
- License: Multiple open-source licenses, depending on included packages

Rockspack images are built from Ubuntu container base images. Ubuntu base images include packages from the Ubuntu archive, each distributed under their own applicable licenses.

## System and Build Dependencies

Rockspack images may include runtime or build dependencies installed through Ubuntu package repositories, including but not limited to:

- `ca-certificates`
- `build-essential`
- `git`
- `make`
- `libbz2-dev`
- `libgflags-dev`
- `liblz4-dev`
- `libsnappy-dev`
- `libzstd-dev`
- `zlib1g-dev`

Each package is distributed under its own license as provided by the Ubuntu package metadata and upstream project sources.

## Notes for Image Consumers

Rockspack is not affiliated with Meta, Facebook, the official RocksDB project, Canonical, or Ubuntu.

Consumers should review the license metadata of the specific image tag they use, especially when redistributing derived images or using Rockspack images in commercial products.

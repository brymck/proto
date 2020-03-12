protobufs
=========

![Go](https://github.com/brymck/proto/workflows/Go/badge.svg)
![Java](https://github.com/brymck/proto/workflows/Java/badge.svg)
![Python](https://github.com/brymck/proto/workflows/Python/badge.svg)

[Protobufs][protobufs] for brymck.io. This is both something I use both for personal projects and to demonstrate
professionally how you can organize service definitions in a robust way.

Table of contents
-----------------

* [Overview](#overview)
* [Building](#building)

Overview
--------

This library is a monorepo housing Protobuf definitions. Its goal is to allow myself and contributors to define services
that are

* Easy to write and maintain
* Efficient in production
* Easy for others to discover
* Easy for downstream users, both service developers and API consumers, to use

To accomplish these goals, I use Google's [Protobufs][protobufs] as the IDL (interface description language) and
[gRPC][grpc] as our RPC framework. Protobufs are language-neutral and come with a rich ecosystem of tools for code
generation that allow serializing structured data. gRPC is a high performance RPC (remote procedure call) framework that
supports multiple languages, using Protobufs for service definitions. To ensure we follow common practices, we lint and
compile Protobufs with [Prototool][prototool].

When the full CI/CD process is run, it will:

* Lint Protobuf definitions
* Generate, build and deploy Go, Java, Node.js and Python libraries for each Protobuf package
* Generate, build and deploy a [Protobuf registry][proto-registry] web site

The repo is laid out as follows:

* `.github/` - GitHub Actions CI/CD configuration
* `bin/` - Python helper scripts for the build process
* `config/` - Configuration for [Google Cloud Endpoints][endpoints], Maven, etc.
* `proto/` - Protobuf service definition files
* `templates/` - Templates for code generation not handled by `protoc`
* `Makefile` - Directives for building and deploying libraries

Building
--------

Prerequisites:

* [Docker](https://www.docker.com/)
* [Go](https://golang.org/dl/)
* [Node.js](https://nodejs.org/en/download/)
* [OpenJDK](https://openjdk.java.net/install/) or some other Java installation
* [Python](https://www.python.org/downloads/)

To generate all code and build the resulting libraries (in some cases installing them locally), run:

```bash
make
```

This will build the following targets:

* `make dependencies` - Create Protobuf descriptor sets and dependency lists for each package
* `make generate` - Use [Prototool][prototool] (and [Proto Registry][proto-registry]) to generate code
* `make package` - Reorganize code into directories for each language + package that contain complete package
  descriptions, using [Jinja][jinja] for templating
* `make build` - Build each package

Note that `package` and `build` can all be appended with `-go`, `-java`, `-node` and `-python` to only run the
language-specific sections of each.

### Other targets

#### `make proto/brymck/foo/v1/foo.proto`

Create a new Protobuf file with basic information filled in based on the contents of `proto/prototool.yaml`. Follow the
convention of `proto/brymck/<package>/v<version>/<service>.proto`.

#### `make lint`

Validate your Protobuf files.

#### `make deploy`

In general this should only run as part of CI/CD. Similar to `package` and `build`, you can provide the
language-appropriate suffix to this target to only deploy for that language.

#### `make clean`

Remove any generated files.

[endpoints]: https://cloud.google.com/endpoints
[grpc]: https://grpc.io/
[jinja]: https://jinja.palletsprojects.com/
[protobufs]: https://developers.google.com/protocol-buffers
[proto-registry]: https://github.com/spotify/proto-registry
[prototool]: https://github.com/uber/prototool

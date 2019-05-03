# go-rpm-macros

The *go-rpm-macros* project provides files needed to automate Go (Golang) rpm
packaging:

- default filesystem locations,
- architecture-specific settings,
- dependency automation (*Provides*, *Requires*, *BuildRequires*),
- macros to simplify and standardize Go spec files, for all rpm build stages, including the srpm stage,
- documented templates to showcase how to use the result.

It uses [golist](https://pagure.io/golist) to analyse Go codebases.

## Usage

1. The *templates* directory contains documented examples that take advantage of this automation.
2. To deploy the project outside Fedora Linux, take a look at the corresponding spec file on [src.fedoraproject.org](https://src.fedoraproject.org/rpms/go-rpm-macros).

## Licensing

*go-rpm-macros* is licensed under the GPL version 3 or later. The `spec` templates are licensed under the MIT license.

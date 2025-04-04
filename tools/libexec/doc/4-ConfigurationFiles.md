# The Tools Project: a Tools System and Paradigm for IT Production

## Summary

[Introduction](#introduction)

[General syntax](#general-syntax)

[Search order](#search-order)

[Site configuration](#site-configuration)

[Node configuration](#node-configuration)

[Service configuration](#service-configuration)

## Introduction

__TheToolsProject__ is meant to be highly and safely, configurable, in such a way that:

- configuration files are either global (configuring the whole __TTP__ system), or dedicated to a particular execution node; they are stored together in the `[TTPROOT]>/etc/` trees;

- configuration files may (and actually should) be released in all machines/hosts/nodes, and so on.

Only `.sample.json` and `.sample.ini` configuration files are released with __TheToolsProject__. A parallel __TTP__ tree should be created for hosting the site-specific configuration files.

## General syntax

Historically the configuration files are sample colon (`:`) separated `.ini` text files.

Though they were named with a `.ini` suffix, they are NOT like Windows `.ini` files as they do not manage groups. They are more like CSV files: a list of lines, each line being itself a list of colon (`:`) separated values, spaces around the `:` value separator being not signifiant.

Comments are identified by the `#` character, and continue until the end of line.

Starting with v4, __TheToolsProject__ now prefers `.json` JSON files which take precedence over `.ini` files.

## Search order

Configurations are managed for:

- the global site itself,
- the nodes,
- the services.

They are searched for in `[TTPROOT]>/etc/` trees, in the order of their definition at bootstrap time.

The first file found wins, even if it is empty. Other files with the same name, which may be adressed later in the list of __TTP__ trees, are ignored.

## Site configuration

The site configuration MUST be defined in a `site.json` or a `site.ini` file. It is searched for in `[TTPROOT]>/etc/ttp/` trees.

It can use `"include": "another_name.json"` directives, the targeted file being searched for in the canonical order in these same `[TTPROOT]>/etc/ttp/` trees.

Unless otherwise specified, most of the parameters defined in this site configuration can be overriden on a per-node basis.

When using JSON configuration (which is the preferred way starting with v4), the site integrator MUST define the __TTP__ parameters inside of a `TTP` top-level key. This let him, if needs arise, to also define - for exammple - a `site` top-level key for own and specific needs of the site.

## Node configuration

The node configuration MUST be defined in a `<node>.json` or a `<node>.ini` file. It is searched for in `[TTPROOT]>/etc/nodes/` trees.

## Service configuration

The service configuration MUST be defined in a `<service>.json` or a `<service>.ini` file. It is searched for in `[TTPROOT]>/etc/services/` trees.

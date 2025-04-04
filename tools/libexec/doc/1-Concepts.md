# The Tools Project - Tools System and Working Paradigm for IT Production

## Summary

[Site](#site)

[Environment](#environment)

[Service](#service)

[Execution node](#execution-node)

[Commands and verbs](#commands-and-verbs)

### Site

The topmost element of your organization.

__TheToolsProject__ reasons at the site level. Commands and configurations are defined and thought at this level too.

## Environment

An environment (or an execution environment to distinguish it from *nix user environment) is identified by a name and mainly qualified by a Service Level Agreement (SLA).

This is mostly an homogeneous execution unit. Say for example what Wikipedia says about [deployment environments](https://en.wikipedia.org/wiki/Deployment_environment).

Commonly used environments are 'Production', Pre-production', 'Test' and so on.

As long as __TheToolsProject__ is concerned, you can define and use as many environments as you wish.

I personally have seen sites with 15 or 20 distinct environments, even if not all complete.

__TheToolsProject__ manages the site environments in two ways:

- when a user identifies its current execution node (see below), he/she gains access to all services of the environment of this node;

- if the environment spreads among several machines, __TheToolsProject__ takes care of going to the right machine in the same environment when asking for a particular service;

- there is no way - and no risk - the user does something on another environment than the one attached to his/her execution node.

__TheToolsProject__ maje sure no one inadvertently executes a command in another environment that the one he/she has logged in.

- the commands are agnostic between environments;

This is very important and a great added value of The Tools Project, so let emphasize this:

    All comands written in the applications scripts are environment-agnostic: they do not change when the script is moved from an environment to another.

The environment is defined at execution-node level, in the node configuration file.

Unless a very particular reason, for example if you are in the process of deploying a new __TTP__ version, you will have the very same __TTP__ tree in all environments, with the very same configuration files.

It is so not rare at all that a site defines a common __TTP__ tree installed on a NFS share, available in all nodes. In this configuration, we have most often a common share per environment for security reasons.

## Service

A service is any product or feature we want manage.

In a typical site, there are many services, e.g.:

- a file transfert monitor,
- a scheduler
- a 'Sales' DBMS
- a 'Suppliers' DBMS
- and so on.

__TheToolsProject__ identifies a service by a name.

The service is typically defined is several environments.

For a given environment, __TheToolsProject__ requires that the service be hosted on a single node.

Through the node configuration files, each of them being attached to its own environment, we are so able to provide to the same service distinct property values dependant of the environment.

## Execution node

An execution node is an ensemble of services, on a single host, in a single environment.

For [historical reasons](./historic.md), we still provide a logical machine notion. But nowadays we are most often talking of a (physical or virtual) operating system.

As of its 2.x version, __TheToolsProject__ manages two types of nodes:

- the host (standard *nix host) and there will be one execution node of this host;

- the logical machine and there may be several execution nodes on an host

Whether it is a logical machine or a host, __TTP__ considers it as an execution node as soon as its properties are described in a `[TTPROOT]/etc/nodes/<name>.ini` configuration file.

The execution node is identified by its DNS short name.

In other words, the name of the node must be resolvable by the local resolv library to a reachable IP address.

See docs/3-LogicalMachine for an in-depth overview of the logical machine paradigm, and how __TheToolsProject__ manages it.

As a last word, and that is all to say about this, __TheToolsProject__ does not make any difference between a physical or a virtual machine to which it connects to, or whether it is on the LAN or the WAN or the cloud: these are both an host with an OS.

## Commands and verbs

Commands and verbs are the executable interface of the library.

Their execution is always logged.

They are safe to be run without any argument.

They are self-explanatory.

All commands are of the form:

```sh
   $ command.sh verb <options>
```

As a general philosophy, entering any command, or any command + verb, without any optional nor positional argument, is safe and only displays a contextual help.

Example:

```sh
   [toto@local ~] $ svn.sh
   svn.sh: Subversion management
     dump: dump the last commit(s) of the named SVN repository
     list: list known SVN repositories

   [toto@local ~] $ svn.sh list
    list: list known SVN repositories
      usage: svn.sh list [options]
      where options are:
        --[no]help                  display this online help and gracefully exit [no]
        --service=<mnemo>           service mnemonic []
        --columns={NAME,PATH,URL}   displayed columns as a comma-separated list [ALL]
        --[no]headers               display headers [yes]
        --format={CSV|TABULAR}      output format [TABULAR]

   [toto@local ~] $ ttp.sh list -commands
   [ttp.sh list] displaying available commands...
     svn.sh: Subversion management
     ttp.sh: The Tools Project (TTP) management
```

# TheToolsProject - Tools System and Working Paradigm for IT Production

## Summary

[Introduction](#introduction)

[Identifying available logical machines](#identifying-available-logical-machines)

[Default logical at login time](#default-logical-at-login-time)

[Why do not install TheToolsProject inside the logical tree ?](#why-do-not-install-the-tools-project-inside-the-logical-tree-)

## Introduction

Logical machines are historic components of high-availability clusters. Strictly speaking, a logical machine is fully determined with:

- a dedicated IP address, and a corresponding dedicated name in the DNS

- a filesystem, mounted on '/<name>'.

They are said 'logical' because they do not have an OS by themselves, but take advantage of the host's OS.

Due to the storage nature, the logical machine may be successively switched to different hosts, the move being due to maintenance, performance or availability reasons. 

There may be several logical machines hosted on a single host, each one belonging to a different environment.

As a consequence, it is possible that several execution environments be found on a single host.

From __TheToolsProject__ point of view, a logical machine is an execution node by itself, whatever be the host, and so has (must have) its own node configuration file.

The notion of a "logical machine" has some inherent drawbacks, that __TTP__ must deal with:

- as the logical machine must come with all its resources when it is moved from a physical host to another, all services, applications and more generally all managed softwares should/must be installed under the /<name> root filesystem (not really an issue from __TTP__ point of view, but can be for integrators);

- when examining the process list, __TTP__ must deal with many processes which are not run from the current logical machine; this may be an inconvenience when trying to identify a system resource (used CPU, or IPC, or somewhat);

- as all logical machines share the same operating system, __TTP__ cannot know which will be the current logical machine when it connects to a host; a special bootstrap process must be setup, and a special 'switch' verb is required in order to address a logical machine or another;

- last, __TTP__ requires that all logical machine names be identified by a regular expression written in `[TTPROOT]/etc/ttp/logicals.re` (or its JSON equivalent).

## Identifying available logical machines

Though an host name may be identified at runtime just by running a standard *nix command (uname), __TheToolsProject__ relies on a provided regular expression to identify the logical machine.

This regular expression must be specified in the site-wide `[TTPROOT]/etc/ttp/logicals.re` (or its JSON equivalent) configuration file. If the file is not found or empty, then __TheToolsProject__ will consider that the site does not use the logical machine paradigm.

Contrarily, if the `[TTPROOT]/etc/ttp/logicals.re` (or its JSON equivalent) configuration file exists and is not empty, then the found regular expression is used to identify the name of the logical machines by comparing it to the filesystems mounted on the root (/).

The comparison applies on the first directory level, after having removed the leading slash.

This way, __TheToolsProject__ is able to automatically determine the list of logical machines available on the host.

As a summary, logical machines available on a host are identified as:
 
1. a non-empty regular expression is found in `[TTPROOT]/etc/ttp/logicals.re` (or its JSON equivalent);

2. a file system is mounted under /<name>, where <name> satisfies the previously found regular expression;

3. a node configuration file exists.

## Default logical at login time

When a user logs into a host, he/she cannot choose his/her initial execution node. Instead __TheToolsProject__ does its best to propose and setup a default execution node.

At login time, the default execution node is the first node found when enumerating:

1. the logical machines available on the host (if any)
2. the host itself.

It may so happen that no execution node may be set of this host.

When the user wishes change his/her current execution node, it must executes the command:

   `. ttp.sh switch -node <node>`

Note the leading dot, as this command is expected to modify the user environment.

This command is useless in a site which does not make use of the logical machine paradigm, but is still used internally by __TheToolsProject__ in remote executions.

## Why do not install TheToolsProject inside the logical tree ?

The bootstrapping process at login time involves some __TTP__ code.

Adressing this code at login may fail if the logical machine is not present at this time on the host.

As another drawback, when the logical machine paradigm is used in a site, there is typically many more logical machines that hosts.

Distributing a new version of TheToolsProject may so be (much) longer.

For these two reasons, it is always better to install __TheToolsProject__ either in the hosts, on in a centralized NFS place (or as a mix of the two solutions).

---
P. Wieser
- Last updated on 2025, Apr. 4th

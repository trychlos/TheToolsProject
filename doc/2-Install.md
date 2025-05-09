# TheToolsProject - Tools System and Working Paradigm for IT Production

## Summary

[Liminaries](#liminaries)

[Prerequisites](#prerequisites)

[The TTP tree](#the-ttp-tree)

[Bootstrapping](#bootstrapping)

[Per-user configuration](#per-user-configuration)

## Liminaries

We are going here to deep dive into bootstrapping details of both:

- shell-based and Perl-based __TTP__ flavors
- on shell-based and cmd-based OS flavors.

## Prerequisites

### Shell-based OS (any unix-like)

- latest ksh-93 available as /bin/ksh
- latest perl 5 available as /usr/bin/perl

### cmd-based OS (any windows-like)

- latest [Strawberry Perl](https://strawberryperl.com/)

## The TTP tree

Once installed, __TheToolsProject__ tree exhibits the following structure:

```
  [TTPROOT]/
   |
   +- maintainer/
   |
   +- site.samples/
   |
   +- tools/
   |  |
   |  +- bin/                 Hosts the commands
   |  |                       This must be adressed by the PATH variable
   |  |
   |  +- etc/                 Configuration files
   |  |  |
   |  |  +- nodes/            The nodes configuration files
   |  |  |
   |  |  +- private/          Passwords and other credentials
   |  |  |
   |  |  +- services/         The services configuration files
   |  |  |
   |  |  +- ttp/              Global TTP configuration
   |  |
   |  +- libexec/             Functions and subroutines
   |  |  |
   |  |  +- bootstrap/        The bootstrapping code
   |  |  |
   |  |  +- doc/              This documentation directory
   |  |  |
   |  |  +- sh/               Shell resources
   |  |  |                    This is automatically adressed by the FPATH variable in shell-based __TTP__ flavor
   |  |  |
   |  |  +- perl/             Perl resources
   |  |     |                 This is automatically adressed by the PERL5LIB variable in Perl-based __TTP__ flavor
   |  |     +- TTP/
   |  |
   |  +- <command1>/          The verbs for the <command1> command
   |  |
   |  +- <command2>/          The verbs for the <command2> command
```

The above structure explains the reason for why a command name cannot be in `bin`, `etc` or `libexec`: one could not create the corresponding verb directory.

Users of __TheToolsProject__ must have read permissions on all of each TTP trees, plus execute permission on `bin/` subdirectories.

It is be a good idea too to define a group and an account which will be the owner of each __TTP__ trees, and to make sure all users of __TheToolsProject__ are members of this group.

Several trees can be defined and addressed, each of them being more or less complete. Each time a file is needed, __TheToolsProject__ searches for it in the list of trees, taking into account the first one found. This way, several trees may address differents needs (say, e.g., a development tree, a configuration tree, a production code tree).

## Bootstrapping

__TheToolsProject__ requires :

- a `TTP_ROOTS` environment variable which addresses the available layers of code

- an up-to-date `PATH` variable to address the `bin/` directories which contain the executable commands

- an up-to-date `FPATH` variable to address the `libexec/sh/` directory which contains the KornShell functions

- an up-to-date `PERL5LIB` variable to address the `libexec/perl/TTP/` directories which contain the Perl modules.

Though these variables can be manually defined at the OS level by the adminitrator, letting each user define his/her own personalization, they can also be built by the bootstrapping script provided by __TheToolsProject__. This bootstrapping process is run every time a user logs-in on the node, and initialize the execution environment.

It tries to minimize hard-coded, difficult to maintain, paths, while keeping dynamic and be as much auto-discoverable than possible.

The general principle is that:

- the site integrator installs a small bootstrap script at the OS level

- this script manages both shell-based and Perl-based flavors; it addresses a site-level drop-in directory where `.conf` files define the to-be-addressed __TTP__ trees.

Yes, this is an example of the usual chicken-and-egg problem: trying to auto-discover all available __TTP__ layers, we have to hard-code the path to a first __TTP__ tree!

### Shell-based OS (any unix-like)

Say that the site integrator has decided to install:

- __TheToolsProject__ released scripts, commands and verbs in `/opt/TTP`

- the site configuration in `/usr/share/site/ttp`.

1. Define the bootstrap script

As root, create `/etc/profile.d/ttp.sh`, which will address the drop-in directories:

```sh
  $ cat /etc/profile.d/ttp.sh
# Address the installed (standard) version of TheToolsProject
. /opt/TTP/tools/libexec/sh/bootstrap
```

And that's all.

The provided `bootstrap` script accepts in the command-line a list of drop-in directories to examine for __TTP__ paths. If no argument is specified, this list defaults to `${HOME}/.ttp.d /etc/ttp.d`.

Please note that this script has been validated with a bash-like login shell. Using another (say ksh-like or csh-like) may require minor adjustments.

2. Define configuration drop-ins

Install in `/etc/ttp.d` default drop-in directory a configuration to address the __TheToolsProject__ scripts, and another configuration to address site specifics:

```sh
    $ LANG=C ls -1 /etc/ttp.d/*.conf
/etc/ttp.d/TTP.conf
/etc/ttp.d/site.conf
    $
    $ cat /etc/ttp.d/TTP.conf
# Address the installed (standard) version of TheToolsProject
/opt/TTP/tools
    $
    $ cat /etc/ttp.d/site.conf
# Address site configuration
/usr/share/site/ttp
```

The files are read in C lexical order.

We suggest that each configuration file should address one __TTP__ tree even if __TTP__ itself treats each non-comment-non-blank line as a path to an individual __TTP__ tree.

### cmd-based OS (any windows-like)

Like sh-based TTP, the cmd-based flavor must be bootstrapped one way or another. As of v4.9, the site integrator has two ways to initialize TTP:

- first is the historical way, and is just setting environment variables at the machine level in the registry,

- second is new as of v4.9, and tries to mimic the sh-based behavior. Note however that it can have some unpredictable side effects, and is not really suggested!

#### Setting environment variables

TTP needs following environment variables, which must be set in any user environment:

- `TTP_ROOTS` a semi-colon-separated (`;`) of each TTP tree, in the order they should be considered

- `PATH` must be updated accordingly with each `(TTP_ROOT)\bin` directory

- `PERL5LIB` must be updated accordingly with each `(TTP_ROOT)\libexec\perl` directory.

These three environment variables are mandatory for TTP to work. The site integrator can also set `TTP_NODE` variable, which defaults to `%COMPUTERNAME%`.

#### bootstrap.cmd

As of v4.9, TTP provides a `(TTP_ROOT)\libexec\cmd\bootstrap.cmd` which mimics the sh-based bootstrap behavior by reading and interepting the `*.conf` files it finds in a predefined (though modifiable) list of directories, and building with them the `TTP_ROOTS` variable, along with corresponding `PATH` and `PERL5LIB`.

Predefined list of directories are:

- `C:\ProgramData\ttp.d`

- `%USERPROFILE\.ttp.d`.

This predefined list can be replaced by providing another list as `bootstrap.cmd` command-line arguments.

Each `.conf` file found in these directories is interpreted, considering that lines starting with `#` are comments and must be ignored. Other non-blank lines are expected to be path to a `TTP_ROOT` directory, and is appended to current `TTP_ROOTS`. If the line is prepended with a dash (`-`), then the path is prepended to `TTP_ROOTS`.

Though killing and restarting `explorer.exe` could work, it often fails due to explorer not correctly restarting.

Please note that, unless you are working inside of a Windows domain, the group policy logon doesn't work. Only a task scheduled to run at any user logon can run reliably.

#### IMPORTANT NOTE

__As a site integrator, you have to choose one of the two above strategies. It is useless and counterproductive to implement both as the bootstrap.cmd commes as an add-on to system environment variables.__

#### Example

Say that the site integrator has decided to install:

- the drop-in in `C:\ProgramData\ttp.d`

- __TheToolsProject__ released scripts, commands and verbs in `C:\ProgramData\TTP`

- the site configuration in `C:\ProgramData\Site`.

```sh
  C:\TheToolsProject\TTP\libexec\bootstrap\cmd_bootstrap C:\ProgramData\ttp.d
```

And drop the two configuration files in the directory:

```sh
  C:\> type C:\ProgramData\ttp.d\TTP.conf
# Address the installed (standard) version of TheToolsProject
C:\ProgramData\TTP
  C:\>
  C:\> type C:\ProgramData\ttp.d\site.conf
# Address site configuration
C:\ProgramData\Site
```

---
P. Wieser
- Last updated on 2025, May 9th

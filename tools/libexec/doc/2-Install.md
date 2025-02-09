# TheToolsProject - a work paradigm for IT productions

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

__TheToolsProject__ tree has the following structure:

```
  [TTPROOT]/
   |
   +- bin/                 Hosts the commands
   |                       This must be adressed by the PATH variable
   |
   +- etc/                 Configuration files
   |  |
   |  +- nodes/            The nodes configuration files
   |  |
   |  +- private/          Passwords and other credentials
   |  |
   |  +- services/         The services configuration files
   |  |
   |  +- ttp/              Global TTP configuration
   |
   +- libexec/             Functions and subroutines
   |  |
   |  +- bootstrap/        The bootstrapping code
   |  |
   |  +- doc/              This documentation directory
   |  |
   |  +- sh/               Shell resources
   |  |                    This is automatically adressed by the FPATH variable in shell-based __TTP__ flavor
   |  |
   |  +- perl/             Perl resources
   |                       This is automatically adressed by the PERL5LIB variable in Perl-based __TTP__ flavor
   |
   +- <command1>/          The verbs for the <command1> command
   |
   +- <command2>/          The verbs for the <command2> command
```

The above structure explains the reason for why a command name cannot be in `bin`, `etc` or `libexec`: one could not create the corresponding verb directory.

Obviously, all users of __TheToolsProject__ must have read permissions on all of each TTP trees, plus execute permission on `bin/` subdirectories.

It would be a good idea too to define a group and an account which would be the owner of each __TTP__ trees, and to make sure all users of __TheToolsProject__ are members of this group.

## Bootstrapping

The bootstrapping process is run every time a user logs-in on the node, and setup the current running execution node.

It tries to minimize hard-coded difficult to maintain paths, while keeping dynamic and be as much auto-discoverable than possible.

The general principle is that:

- the site integrator installs a small bootstrap script at the OS level

- this script manages both shell-based and Perl-based flavors; it addresses a site-level drop-in directory where `.conf` files define the addressed __TTP__ trees.

Yes, this is an example of the usual chicken-and-egg problem: trying to auto-discover all available __TTP__ layers, we have to hard-code the path to a first __TTP__ tree!

### Shell-based OS (any unix-like)

Say that the site integrator has decided to install:

- the drop-in directory in `/etc/ttp.d`

- __TheToolsProject__ released scripts, commands and verbs in `/opt/TTP`

- the site configuration in `/opt/site/ttp`.

As root, create `/etc/profile.d/ttp.sh`, which will address the drop-in directories:

```sh
  $ cat /etc/profile.d/ttp.sh
# Address the installed (standard) version of The Tools Project
. /opt/TTP/libexec/bootstrap/sh_bootstrap
```

The provided `sh_bootstrap` script accepts in the command-line a list of drop-in directories to examine for __TTP__ paths. This list defaults to `${HOME}/.ttp.d /etc/ttp.d`.
I
nstall in `/etc/ttp.d` drop-in directory a configuration to address the __TheToolsProject__ scripts, commands and verbs, and another configuration to address site specifics:

```sh
    $ LANG=C ls -1 /etc/ttp.d/*.conf
/etc/ttp.d/TTP.conf
/etc/ttp.d/site.conf
    $
    $ cat /etc/ttp.d/TTP.conf
# Address the installed (standard) version of The Tools Project
/opt/TTP
    $
    $ cat /etc/ttp.d/site.conf
# Address site configuration
/opt/site/ttp
```

Each configuration file should address one __TTP__ tree though __TTP__ itself treats each non-comment-non-blank line as an individual path to a __TTP__ tree.

### cmd-based OS (any windows-like)

Say that the site integrator has decided to install:

- the drop-in in `C:\ProgramData\ttp.d`

- __TheToolsProject__ released scripts, commands and verbs in `C:\ProgramData\TTP`

- the site configuration in `C:\ProgramData\Site`.

As an administrator, edit the [Local Group Policy](gpedit.msc), and add a logon script to User Configuration, addressing the drop-in directory:

```sh
  C:\TheToolsProject\TTP\libexec\bootstrap\cmd_bootstrap C:\ProgramData\ttp.d
```

And drop the two configuration files in the directory:

```sh
  C:\> type C:\ProgramData\ttp.d\TTP.conf
# Address the installed (standard) version of The Tools Project
C:\ProgramData\TTP
  C:\>
  C:\> type C:\ProgramData\ttp.d\site.conf
# Address site configuration
C:\ProgramData\Site
```

Both shell-based and Perl-based bootstrap processes do:

- identify the current running execution node and set a TTP_NODE user environment variable

- update the `PATH` variable to add the found __TTP__ layers (in C order)

- in shell-based flavor, update the `FPATH` variable to address the Korn-shell functions

- in Perl-based flavor, update the `PERL5LIB` variable to address the Perl modules.

## Per-user configuration

As the site integrator must define the available __TTP__ layers, every user can define its own layer, for example to write and test a new verb.

The bootstrapping process reads first the user configuration, and then the site one, adding successively found tree path to the list of TTP_ROOT's. This way, the user configuration takes precedence over the site-wide configuration.

As an exception to this rule, the path is prepended to the built list when it is prefixed by a dash (`-`).

### Shell-based OS (any unix-like)

The bootstrap process reads any `.conf` file dropped in `HOME/.ttp.d/` directory.

### cmd-based OS (any windows-like)

The bootstrap process reads any `.conf` file dropped in `USERPROFILE/.ttp.d/` directory.

-----------------------------------------------------------------------
 Addressing The Tools Project
 ============================

   2. Mandatory: define TTP_SHDIR variable

      Because The Tools Project supports the 'logical machine' paradigm,
      there is some situations where it cannot rely on the FPATH
      variable.
      A TTP_SHDIR must be defined to address (one of) the main shell functions
      directory.

      Note 1:
         The 'TTP_SHDIR' variable must address only one directory.
         You probably want address the standard Tools Project tree here.

      Ex:
         export TTP_SHDIR=/opt/TTP/libexec/sh

   3. Mandatory: define the initial execution node

      This is done by calling the '. ttp.sh switch --default' command.

   As a convenience, The Tools Project provides in the
   'libexec/bootstrap/' subdirectory some scripts which may be called
   from a user profile to make this initialization easyer:

     TTP=<dir>; . ${TTP}/libexec/bootstrap/sh_profile
     TTP=<dir>; . ${TTP}/libexec/bootstrap/sh_node

   or:

     TTP=<dir>; source ${TTP}/libexec/bootstrap/csh_profile
     TTP=<dir>; source ${TTP}/libexec/bootstrap/csh_node

   Remote execution
   ----------------
   a) SSH key

     When a command targets a service which is available on another
     node, The Tools Project automatically ssh to the target node and
     re-executes itself.

     You have to install the required ssh public keys in all possible
     target accounts/hosts in order these ssh's may be password-less.

     We suggest defining a single ssh key, shared among all users/hosts,
     dedicated to this usage.

   b) Bootstrapping

     While The Tools Project relies on an initialized user's environment,
     ssh does not open a login shell when it executes a remote command
     (i.e. does not initialize the user's environment).

     The Tools Project provides a TTPROOT/libexec/bootstrap/sh_remote
     script, which has to be adapted to the user's shell, and installed
     in the user home directory with the '.ttp_remote' name.

# TheToolsProject - a work paradigm for IT productions

## Summary

[What is it ?](#what-is-it-)

[How does it work ?](#how-does-it-work-)

[Installing](#installing-thetoolsproject)

## What is it ?

__TheToolsProject__ is an organized set of commands and verbs whose aims are:

- provide to a user or an administrator an unified way of interact with varous tools and products, the same way in all environments

    For example, starting a Sybase server, or a MariaDB server, or a HTTP server is as simple as:

    `$ sybase.sh start -s <service>`

    or `$ mariadb.sh start -s <service>`

    or `C:\> dbms.pl start -s <service>`

    or `$ httpd.sh start -s <service>`

    or `C:\> daemon.pl start -s <service>`

- provide logs: who has done what and when ?

    Even if the stdout console output can be highly configured, all informations, results, warnings, errors and logged and kept. No information is neither lost (though can be archived).

- manage several services spanned on several nodes, for several environments.

    Configuration files are outside of the code and well separated.

    Libraries have all the code needed to compute and use the right precedence depending of the current command / verb / usage.

But, most of all, __TheToolsProject__ materializes a work paradigm where all environments managed by our IT team use the exact same version of scripts and configuration files.

No more install scripts where we must slightly update scripts or configuration files when moving from an environment to another and this implies a much better quality of these moves. Instead of this painful work, just one configuration file which contains all parameters required for all managed environments.

No more scripts which must be modified for targeting one SGBD or another depending of the current environment. Instead of that, just one configuration file which contains all parameters required for all managed environments.

As a plus, __TheToolsProject__ brings to the daily usage  some comfortable enhancements:

- usage of the system environment is minimized as this is (actually used to be) a limited resource; instead of having accounts whose system environments happen to be polluted by the environment variables set by each and every application component (file transfer, sgbd monitor, and so on), needed variables are internally set by the __TTP__ scripts themselves;

- commands and their verbs are well identified, and safe to be discovered; they are self-explanatory; this let the IT team safely play with and learn every command;

- executions are logged, temporary files are kept; I repeat: all execution of any __TTP__ command are logged, all temporary files are kept; this is at last the dream of the Security Officer!

- commands and verbs build a standardized API for the developers, thus easying the transfert to the production.

As an executive summary, we can claim __TTP__ tools as the next step to an ideal industrialization process of the IT production team.

Do you aim to be [ITIL](https://en.wikipedia.org/wiki/ITIL) compliant ? You need it.

Do you aim to to make your devops happpy ? You cannot miss it.

Note that __TheToolsProject__ is before all a console interface. All interactions are command-line based. There isn't any user interface more complex that some lines displayed on a console.

## How does it work ?

At the very beginning, the only command you have to remember is:

`$ ttp.pl` or `$ ttp.sh`

depending of the exact flavor you are running.

You should get an answer like:

```sh
$ ttp.sh
ttp.sh: The Tools Project (TTP) management
  filter: reorder, filter and reformat columns from stdin stream to stdout
  fn: call a function with arguments
  list: list various informations about The Tools Project
  option: test different sort of optional and positional arguments
  purge: purge files from a directory
  switch: setup the execution node environment
```

or

```sh
C:\>ttp.pl
ttp.pl: The Tools Project Management
  alert: send an alert
  copydirs: copy directories from a source to a target
  list: list various TTP objects
  movedirs: move directories from a source to a target
  pull: pull code and configurations from a reference machine
  purgedirs: purge directories from a path
  push: publish code and configurations from development environment to pull target
  sizedir: compute and publish the size of a directory content
  test: run the TTP test suite
  vars: display internal TTP variables
  writejson: write JSON data into a file
```

The `ttp.sh` (resp. `ttp.pl`) command, when run without any argument, answers by providing the list of its available verbs.

And so do all available commands.

Go on by examining the answers to a `ttp.sh list` (resp. `ttp.pl list`) command.

```sh
$ ttp.sh list
ttp.sh: The Tools Project (TTP) management
  list: list various informations about The Tools Project
      This verb lists:
      - the available commands,
      - the registered execution nodes, maybe for a specified environment
          --nodes [--environment=<identifier>]
      - the services available on a node, maybe with their label:
          --services [--node=<name>] [--label]
      - the services defined in an environment:
          --services -environment=<identifier> [--label]
      - the TTP defined variables,
    usage: ttp.sh list [options]
    where options are:
      --[no]help                   display this online help and gracefully exit [no]
      --[no]verbose                verbose execution [no]
      --[no]commands               display the list of available commands [no]
      --[no]nodes                  display the registered nodes [no]
      --environment=<identifier>   display nodes for this specific environment []
      --[no]services               display defined services [no]
      --[no]variables              display TTP defined variables [no]
      --[no]counter                whether to display a data rows counter [yes]
      --[no]csv                    display output in CSV format [no]
      --[no]separator              (CSV output) separator [;]
      --[no]headers                (CSV output) whether to display headers [yes]
```

or

```sh
C:\>ttp.pl list
ttp.pl: The Tools Project Management
  list: list various TTP objects
    Usage: ttp.pl list [options]
    where available options are:
      --[no]help              print this message, and exit [no]
      --[no]colored           color the output depending of the message level [no]
      --[no]dummy             dummy run (ignored here) [no]
      --[no]verbose           run verbosely [no]
      --[no]commands          list the available commands [no]
      --[no]nodes             list the available nodes [no]
```

One more time, the `ttp.sh list` (resp. `ttp.pl list`) command, when run without any argument, answers by providing its usage and available options.

And this is a general rule of __TheToolsProject__ (also known as __TTP__ by the fans): a command will never ever break or modify something without the corresponding and validated option argument. This is a security rule so that the users can freely explorate the available commands and verbs, without having to worry about potential damages.

So go on with the available commands.

```sh
$ ttp.sh list -commands
[ttp.sh list] displaying available commands...
 audio.sh: Audio management
 cft.sh: Cross File Transfer (CFT) management
 cmdb.sh: Configuration Management Database
 ldap.sh: LDAP management
 mysql.sh: MySQL management
 oracle.sh: Oracle DBMS management
 packaging.sh: Packaging and repositories management
 svn.sh: Subversion management
 ttp.sh: The Tools Project (TTP) management
[ttp.sh list] 9 displayed command(s)
```

or

```sh
C:\>ttp.pl list -commands
[ttp.pl list] displaying available commands...
 daemon.pl: Daemon Management
 dbms.pl: DBMS Management
 http.pl: HTTP Requests
 mqtt.pl: MQTT Bus Communications
 mswin.pl: Windows-specifics verbs
 ovh.pl: OVH API Access
 services.pl: Services Management
 smtp.pl: SMTP Comunications
 telemetry.pl: Telemetry Services
 ttp.pl: The Tools Project Management
[ttp.pl list] 10 found command(s)
```

NB 1. Yes, lot of tools use nowadays this same paradigm of a command, a verb and some options. They were not so common at the time of the first writing, and __TheToolsProject__ is more than just some scripts: it aims to be a working paradigm for IT productions!

NB 2. As you can see in above examples, __TheToolsProject__ is released in two flavors

## Installing TheToolsProject

__TheToolsProject__ is all contained into a single directory tree which contains not only all __TTP__ code, scripts, functions and so on, but is also released with simple configuration files.

Two layers are usually defined:

- the first one is just an empty copy of __TheToolsProject__, only containing site-specific configuration files

- the last addressed tree usually contains the script themselves.

As many layers as needed can be installed, each one containing only the subset needed by this layer. They are resolved in the usual way: the first found wins.

See all details in [Install](./src/libexec/doc/2-Install.md).

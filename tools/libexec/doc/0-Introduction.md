# The Tools Project - Tools System and Working Paradigm for IT Production

## Summary

[What is it](#what-is-it)

[Description](#description)

[Features](#features)

[Maintenability and versions concurrency](#maintenability-and-versions-concurrency)

## What is it

__TheToolsProject__ is a script library targeting applicative production. It may also be seen as a Production Scripting Interface (PSI).

__TheToolsProject__ targets IT teams:

- application developers,
- integrators,
- production operators.

__TheToolsProject__ provides to IT teams a common library which offers many benefits:
 
- first, offer to the IT teams an unified command-line interface to the managed tools and services
  
  - encapsulates all the gory details of managed products
  - keeps a common, homogeneous, consistent interface
  - provides full execution logs
  - provides a securized behavior, including an online help.

- second, offer to the applications an unified access to all production services, without regarding of the running environment

- third, ensure that scripts are exactly the same between the environments, by forcing all parameters to be isolated in well-known configuration files

- last, offer an integrated audit track of all executed commands.

__TheToolsProject__ targets both:

- developers who are now able to take advantage of these resources
- integrators who no more have to deal with products themselves more than once
- exploitation teams which take benefit of consistency, audit trace, online help, and more.

The investment required to design, develop and test these tools is largely convered by:

- a shorter integration delay of new guys in the IT team as the commands are unified and self-explanatory

- a better share of competencies inside of the team: because all the written code only used interpreted languages, anybody is able to look at it and understand how it works;

- the separation between configuration and code is a major step in system industrialization, thus bringing more efficiency, reliability and stability to the applications;

- the total removing of all incidents due to a script which must be modified when being moved from an environment to another.

The whole thing finally builds a production library where most of configuration and code is shared, reusable, well tested.

## Description

__TTP__ tools are a set of scripts and text configuration files who are to be considered as a complete production library. This library is to be used by business developers and engineers in order to safely and completely access to the production services.

- __rule 1__: all __TTP__ code can be viewed and edited by any __TTP__ user with a simple text editor. No compilation, no hidden code.

In a typical production site, you have many applications who all share some sgbd engines, maybe one or more schedulers and file transfer monitors. The infrastructure can implement some middleware, and the business interfaces can be implemented under Tomcat or another application server.

And thus, __TTP__ tools are able address each of these products, and can be easily extended to another new product.

- __rule 2__: each and every member of your IT team can create a verb or a command as long as he/she is able to write a simple script and willing to respect some well-known coding rules.

But business developer who writes a script for his application doesn't want to know anything about all the gory details of the infrastructure. Nothing about the detailed interface to the file transfer monitor, or to the used middleware. And more, he doesn't want to be impacted when it staff decides to migrate to another middleware product.

And so, __TTP__ tools are also an abstraction layer between the actual products and their commands, and the business application.

The production site is typically built with more than one machine, and often with many. All these machines execute different services, but its staff (usually) wants that the start/stop/use scripts of these services be maintained coherent and consistent beetween these machines.

And so, __TTP__ these tools are completely banalized. On each machine, you deploy the same set of scripts. This set includes the needed parameters for all machines, including of course the current one. And when a engineer creates a script, or fixes a bug in an existing one, the new script can and should be safely deployed in all the machines.

- __rule 3__: the same whole thing anywhere, not (and no more) scripts for the developments and scripts for the production.

Usually, the developers write and test their scripts in a test environment before deploying them in production environment. And they do not want modify any line of code for this deploiement. The tools define the same command for a given service in all knwown environments, making so easier to go to production, with much less errors due to the deploiement.

Last but not least, when the production site has many machines, its engineers use their times ssh-ing from one machine to another, to test or act on a given service.

These tools know about the exact localization of each service, in each known environment. They ssh themselves - transparently to the current user - to the needed machines for a given service... And, yes, these tools know ssh also when the used account need to be changed for a particular service...

And, as these scripts are primarly production tools, they all log what they do, and all the errors they detect, and eventually automatically work-around.

## Features

- Unified, self-explained, command-line interface
- Full execution logs
- Full audit track
- Identity among environments
- Command agnosticity between environments
- Common code vs. site properties separation
- Version concurrency

## Maintenability and versions concurrency

Starting with v2, several versions of The Tools Project can be made available simultaneously.

This has two main benefits:

- we are now able to store the site configuration files apart from the __TTP__ code; __TTP__ updates are simpler as a new version can just fully replace the previous one, being sure that nothing of the site configuration files will be modified

- we can have a production-state __TTP__ code, besides of a development tree on a coder home directory, without having to duplicate all the unchanged stuff.

Each time __TheToolsProject__ searches for a file, it searches it in the ordered list of TTPROOT's trees, the first being found winning. The order is determined when populating the FPATH variable, most often at bootstrap time.

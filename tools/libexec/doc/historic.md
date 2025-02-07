# TheToolsProject - a work paradigm for IT productions

## Summary

[The very first version](#the-very-first-version)

[Versions spread](#versions-spread)

[The second version](#the-second-version)

[Going to cmd-based](#going-to-cmd-based)

[Merge sh and Perl](#merge-sh-and-perl)

## The very first version

__TheToolsProject__ is first born in 90' when I were asked by a customer to create its central production site. Code was initially written by an imaginative applicative production team.

At the time, we were running financial applications with a first version of Sun Cluster. In this version, logical machines were defined as:

- a name
- an IPv4 address
- a mounpoint named as the logical machine at the root of the physical server
- an arbitrary list of filesystems mounted under the above root mountpoint.

And high availability was obtained by switching between physical servers:

- switch the IP address
- detach from the source and attach to the target the filesystems defined by the logical machine.

As you can imagine, this configuration was a bit difficult to manage. Some examples are:

- product editors were at the time reluctant to provide a single licence while we potentially want run on two servers

- products were not easily installable elsewhere than under /usr with configurations in /etc while we wanted that product be switched with the logical machines

- and so on.

What was important in this architecture is that we could (and had to) switch between logical machines even when staying in the same physical server because some services only worked when locally managed. And actually __TheToolsProject__ commands has taken care of hiding the technical aspects of these switch as soon as these original days.

For example, when working on a pre-production machine, and running a command like `cft.sh send -file ...`, then __TheToolsProject__ automagically ran a remote execution on the logical machine which hosted the CFT service for the pre-production environment, transmitting the local file to be sent, receiving back the send result.

The logical machine from which you run your command is not important. What is important is that you are running in such or such environment. __TheToolsProject__ warranties that it will not run a command in another environment than your running one at the time.

Eventually, the fact is that these tools have brought up such an increase of the global production quality that they have become a must-have in all production teams
of the corporation.

## Versions spread

As the initial team work for several customers, __TheToolsProject__ has lived and has been ported to different unixes (at least Aix and HP to my own knownledge).

And because different customers have differents needs, __TheToolsProject__ has most probably been largely modified to include new products or new verbs.

This is the spirit of __TheToolsProject__: any team can appropriate it, extend it or remove unused verbs.

Though rather largely spread, and heavily modified, updated, increased and improved, we consider that all these versions can be numbered as v1.x: they are shell-based, and only target unix OS'es.

## The second version

Years later, this shell-based version has been rewritten to make the multi-layering more easy, and still decrease the used environment size.

Though it has been published, this second version has been much less used.

This was the v2, published in 2020-2021.

## Going to cmd-based

Adressing a cmd-based (Windows-like) OS with this shell-based code, though possible, is rather a pain, and not worth against re-writing these same features in Perl.

Configuration files have become JSON-based, and this v3 has been published in 2023-2024.

## Merge sh and Perl

In 2025, I still believe this architecture is usefull and bring more quality to IT teams. It is so time to merge these two flavors in a fourth version.

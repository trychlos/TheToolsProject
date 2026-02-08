# TheToolsProject - Tools System and Working Paradigm for IT Production

## Summary

[Introduction](#introduction)

[The `services.pl live` verb](#the-services.pl-live-verb)

## Introduction

Like its name says, a service is something which provides an action or a result. This is most often one of the hearts of our production. Examples of services are DBMS, MQTT or SMTP gateway, Secured file transfer. A service can be almost anything which wa want be able to address or to request.

At its most simple expression, a service is running on one node per environment.

To be known by `TTP`, a service has to be defined in at least one node, maybe as an empty object:

```json
    "services": {
        "myService": {
        }
    }
```

This above definition says: "yes, the node knows about the service and is able to handle it". The node can define the whole configuration of the service, or this configuration can be delegated to a `<myService>.json`, in the `servicesDir` directory:

```json
    {
    }
```

## Configuration

It is rather frequent that a dedicated command is used to manage a particular type of service. This is typically the case for example for DBMS with `dbms.pl`, LDAP with `ldap.pl` and so on. Each command defines its own sub-schema in the JSON configurartion.

The [service JSON schema](../schemas/services_service.schema.json) describes both common service configuration and command-specific options.

## One service-node per environment paradigm

The environment is one of the main notions of `TTP`. When a service is defined on a node, it is available to all nodes which share the same environment that the node where the service is defined.

When the service is defined on a node NOT attached to any environment, then this service is considered as environment-agnostic, and all the nodes, whatever be the environment to which they are attached, can take advantage of this service.

## Multi-nodes services

As indicated above, the most simple configuration of a service if when it runs on one node per environment.

When a service is addressed by a verb, this verb must first determine which node has to be chosen for the service configuration in the running environment. Candidate nodes are, in this order:

- the target node, if the service is defined on it, and if its been specified as an argument of the verb

- the running node, if the service is defined on it

- if the running node is attached to an environment, all other nodes (of this same environment) which define this service, in ASCII alpha order

- if the running node is NOT attached to any environment, all other nodes not attached to any environment and which define this service, in ASCII alpha order

If several nodes are candidates, then a warning is emitted, and the first one is chosen.

Please note that this algorythm doesn't cross the environments boundary.

## Attributing properties to a service

Starting with v4.32, `TTP` let you freely define properties for a service. These propoerties can be defined at the service or at the node level. As usual, the properties defined at the node level override those defined at the service level, these later rather acting as default value.

A property is:
- a name
- a value.

`TTP` doesn't consider any particular semantic to these properties, but provide a verb which let you identify which node provides the property name and its value in the running environment.

```sh
    services.pl by-property -service <SERVICE> -property 'name=value'
```

The node returned cannot cross the environments boundary.

### Example 1: managing a 'live' instance and a 'backup' instance

In this example, we have a 'live' DBMS in production which provides the business data to a web site. For activity continuity, we also have an active 'backup' DBMS running on another node of the production.

We have chosen to define these two nodes in the same 'production' environment so that verbs can freely request and monitor the two DBMS without any issue.

We also have chosen to define a single service for the two DBMS in order to minimize the changes when web site production is switched from a DBMS to the other.

The service is defined in `<servicesDir>/myDBMS.json` as:

```json
    {
        "DBMS": {
            "package": "SqlServer"
        }
    }
```

The web site production (the 'live' instance) is defined in `<nodesDir>/<node1>.json` as:

```json
    "services": {
        "myDBMS": {
        }
    }
```


The running production backup is defined in `<nodesDir>/<node1>.json` as:

`<nodesDir>/<node2>.json`:

```json
    "services": {
        "myDBMS": {
        }
    }
```

Because backups are run with `dbms.pl backup` on the live production host, they actually save the live (local) DBMS.

The administrator has chosen to use the ``backup-monitor-daemon.pl` provided by `TTP` to transfer the filesets from the live production to the backup production, and so `dbms.pl restore` also restores the fileset on its own node.

This is a rather simple case where the running node determines the target DBMS instance, even if the service is defined in several nodes in this environment.

### Example 2: updating a 'live' instance from a 'backup' node

In this example, we manage a 'live' and a 'backup' DBMS in a same environment as above, but we wants this time be able to access the 'live' node from the 'backup'.

This is a typical use case of the properties as we want access a node which is not a natural candidate of the algorythm described above.

The service is defined in `<servicesDir>/myDBMS.json` as:

```json
    {
        "DBMS": {
            "package": "SqlServer"
        }
    }
```

The web site production (the 'live' instance) is defined in `<nodesDir>/<node1>.json` as:

```json
    "services": {
        "myDBMS": {
            "properties": {
                "live": {
                    "command": "<siteDir>/scripts/live_dbms.sh <SERVICE> <ENVIRONMENT>"
                }
            }
        }
    }
```

The running production backup is defined in `<nodesDir>/<node1>.json` as:

`<nodesDir>/<node2>.json`:

```json
    "services": {
        "myDBMS": {
            "properties": {
                "live": {
                    "command": "<siteDir>/scripts/live_dbms.sh <SERVICE> <ENVIRONMENT>"
                }
            }
        }
    }
```

The command `live_dbms.sh` has been written and provided by the site administrator and returns the string 'true' when the node is the 'live' one.

`dbms.pl backup` and `dbms.pl restore` work the same way than in the example 1.

But, here, as we want, say, `dbms.pl sql` on the node1 from the node2, we have to first identify the target node which runs the 'live' DBMS, and provide this information to `dbms.pl sql`:

```sh
    TARGET=`services.pl by-property -service myDBMS -property live=true`
    dbms.pl sql -service myDBMS -target TARGET
```

### Example 3: a single service common to all environments

This could be the case for example for a logging node, or a monitoring node, where we want gather all the data for all our environments.

The service is defined in `<nodesDir>/<node1>.json` in production as:

```json
    "services": {
        "myLogger": {
        }
    }
```

The same service is also defined in `<nodesDir>/<node2>.json` in a staging environment as:

```json
    "services": {
        "myLogger": {
        }
    }
```

In this configuration, we have a 'myLogger' instance in staging environment and another 'myLogger' instance in production.

Defining the host at a node level is enough to redirect all requests from an environment to the defined host:

I.e. in `<nodesDir>/<node2>.json` in the staging environment:

```json
    "services": {
        "myLogger": {
            "host": "node1"
        }
    }
```

Note that explicitely defining the host for a service in the node **can** cross the environments boundary.

And voilà !

---
P. Wieser
- Last updated on 2026, Feb. 3rd

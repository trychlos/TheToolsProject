# TheToolsProject - Tools System and Working Paradigm for IT Production

## Summary

1. [Todo](#todo)
2. [Done](#done)

---
## Todo

|   Id | Date       | Description and comment(s) |
| ---: | :---       | :---                       |
|    8 | 2024- 5- 2 | implements and honors text-based telemetry |
|   53 | 2025- 1-17 | have a timeout on movedirs and purgedirs at least, maybe on all verbs which needs a network access + alert when this timeout is reached |
|      | 2025- 1-20 | daemon.pl command done |
|      | 2025- 4-10 | should build an inventory of what should be done, and what can be done |
|   54 | 2025- 1-19 | verbs should have an internal telemetry for the memory they consume, the execution elapsed time |
|      | 2025- 4-29 | have to define the telemetry to get and how and where to publish it |
|   55 | 2025- 2-17 | daemon.pl status should have an option to publish to mqtt too |
|      | 2025- 4-29 | the daemon itself is already able to publish its status to MQTT - is it relevant to have this option |
|      | 2025- 4-29 | yes, the option is relevant, for consistency first, and to publish status to MQTT if the daemon has disabled it |
|   57 | 2025- 2-17 | daemon.pl status should have an option to publish to text too |
|   59 | 2025- 2-18 | Daemon.pm: metrics for the daemon are windows-specific: re-code for unix'es |
|      | 2025- 4-14 | mswin32 metrics are isolated |
|   61 | 2025- 4- 8 | ttp.pl writejson should should actually be ttp.pl filewrite as the json is provided as a string on input - so this is not dedicated to json |
|   78 | 2025- 4-12 | some daemons should be moveable to libexec/daemons |
|      | 2025- 4-14 | alerts-monitor-daemon.pl is moved to libexec/daemons |
|      | 2025- 4-14 | node-monitor-daemon.pl is moved to libexec/daemons |
|      | 2025- 4-17 | mqtt-monitor-daemon.pl is moved to libexec/daemons |
|      | 2025- 4-17 | at the moment, still exists backup-monitor-daemon in site tree - to be evaluated |
|  111 | 2025- 4-20 | site.schema for telemetry |
|      | 2025- 4-22 | done - has to be honored |
|      | 2025- 5-11 | Mqtt honors it |
|  123 | 2025- 4-29 | have a test for alerts-monitor-daemon |
|  124 | 2025- 4-29 | have a test for mqtt-monitor-daemon |
|  125 | 2025- 4-29 | have a test for node-monitor-daemon |
|  141 | 2025- 5-10 | MongoDB::backupDatabase() and restoreDatabase() command-lines should be configurable somewhere |
|  146 | 2025- 5-11 | maybe a site may/want/should define its own test suite, to be run after the TTP own test suite |
|  147 | 2025- 5-13 | DaemonConfig should be Daemon to be consistent with Site, Node, Service where the class actually addresses or is based on a configuration file |
|      |            | or: have a Daemon class which both gathers DaemonConfig and RunnerDaemon features |
|      | 2025- 5-14 | DaemonConfig -> Daemon would imply $runner = TTP::RunnerDaemon->bootstrap() and $daemon->config() -> $runner->daemon() |
|  163 | 2025- 5-23 | honor MQTTGateway and SMTPGateway wantsAccounts and wantsPassword |
|  164 | 2025- 5-27 | extend commandBYOS to accept both a node name and a ttp::node |
|  170 | 2025- 6-27 | meteor.pl create --application should be fully configurable as a TTP schema and/or with command-line options |
|  171 | 2026- 1- 8 | MQTTGateway and SMTPGateway should be managed as standard services |
|  172 |  |  |

---
## Done

|   Id | Date       | Description and comment(s) |
| ---: | :---       | :---                       |

---
P. Wieser
- Last updated on 2026, Jan. 5th

# The Tools Project - Tools System and Working Paradigm for IT Production

## ChangeLog

### 4.1.0-rc

    Release date: 

    - Change the semantic of 'alerts.xxx.enabled' introducing 'alerts.xxx.default'
    - Alerts now have a title and a message, each of them (but not both) being optional
    - Deprecate 'TTP::alertsDir()' in favor of 'TTP::alertsFileDropdir()'
    - Define ttp.pl alert --list-levels option
    - TTP::commandByOs() is renamed TTP::commandExec() as this is a command execution
    - TTP::commandByOs() is now the function which find a configured (maybe per-OS) command
    - Introduce TTP::nodeName() function
    - Define new 'alerts.xxx.prettyJson' property to display a pretty JSON data, defaulting to true
    - Define new 'alerts.withMqtt.topic' property
    - Change the default alert topic name to <node>/alerts/<stamp>
    - Change the alert stamp format to ISO 8601

### 4.0.1-rc.5

    Release date: 2025- 4- 7

    - Have a Github Action to publish tar.gz and zip packages

### 4.0.0

    Release date: 2025- 4- 4

    - Initial v4 release

---
P. Wieser
- Last updated on 2025, March 25th

# The Tools Project - Tools System and Working Paradigm for IT Production

## ChangeLog

### 4.2.0-rc.0

    Release date: 

    - Shell functions trap_int() and trap_exit() output to stderr
    - Deprecate 'Environment' property in favor of 'environment' (todo #65), thus bumping minor candidate version number
    - Deprecate 'environment.type' property in favor of 'environment.id' (todo #66)
    - Deprecate 'MQTTGateway.broker' property in favor of 'MQTTGateway.host' (todo #62)
    - ttp.pl copydirs: remove option --skip, add options --exclude-dir, --exclude-file and --options
    - copyDir(), copyFile() and removeTree() functions are moved to TTP::Path module
    - ttp.pl copydirs: deprecate (though still honors) --dirs option
    - ttp.pl push makes internally use of ttp.pl copydirs
    - ttp.pl pull makes internally use of ttp.pl copydirs
    - Deduplicate makeDirExist() function (used to be both in TTP and in TTP::Path)
    - ttp.pl copydirs has now an option --empty to empty the target tree before the copy
    - ttp.pl push has now options --exclude-dir and --exclude-files, defaulting to the site configuration

### 4.1.3

    Release date: 2025- 4- 9

    - Fix release content

### 4.1.2

    Release date: 2025- 4- 9

    - Add back msgOut() and msgVerbose() shell functions from Tools-v2-Sh

### 4.1.1

    Release date: 2025- 4- 9

    - Update execution permision (git update-index --chmod=+x tools/bin/*)
    - Setup missing $running variable in ttp/switch.do.ksh

### 4.1.0

    Release date: 2025- 4- 9

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
- Last updated on 2025, Apr. 9th

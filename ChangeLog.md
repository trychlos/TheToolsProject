# TheToolsProject - Tools System and Working Paradigm for IT Production

## ChangeLog

### 4.32.0-rc.0

    Release date: 

    - Display the starting version in all deprecation messages
    - DBMS.host is deprecated in favor of 'host'
    - dbms.pl telemetry -text: check the existance of the .prom file before reading it
    - TTP::DBMS::newDbms() no more tries to load ':all' as there is not exported method in our DBMS packages
    - Warns when trying to publish a telemetry to both 'http' and 'text' media
    - services.pl by-property new verb, thus bumping minor candidate version number
    - Deprecate 'ttp.pl writejson' in favor of 'ttp.pl writefile' (todo #61)

### 4.31.0

    Release date: 2026- 2- 7

    - Restore TTP::Credentials::findWithFile(), updating OVH::conect() accordingly
    - services.pl live is improved to no more depend of the command semantic, but just take the outputed result
    - dbms.pl restore finds and honors the live MonitorDB current node
    - Deprecate workloadSummary.perPeriod in favor of workloadSummary.sinceRun
    - Deprecate workloadSummary.perWorkload in favor of workloadSummary.workloadRun
    - services.pl workload-summary: fix errors management
    - TTP::execRemote() improve message readibility
    - services.pl commands: improve hash detection
    - telemetry.pl ping: have the same help string whatever be the device
    - dbms.pl restore fix access to ttpMonitor database after rename

### 4.30.0

    Release date: 2026- 2- 1

    - New TTP::Meteor::isDevel() function, thus bumping minor candidate version number
    - meteor.pl deploy honors '--dummy' option
    - meteor.pl list --applications has '--dirs' and '--diffs' new options to list the directory when it is doesn't correspond to the name of the application
    - Fix meteor.pl publish to have the right per-day termination
    - Define new TTP::IRunnable->runnableOptionsCount() method
    - meteor.pl deploy --first option displays an help to prepare the first deployment to a new target
    - meteor.pl list --packages displays publication informations as a JSON-like string
    - daemon.pl restore -monitor: only insert if previous delete has been successful
    - Node::findByService(): fix the inhibition detection

### 4.29.0

    Release date: 2026 -1-21

    - TTP::Meteor::getApplication() now also checks the ability to run a Meteor command, and returns the Meteor version to the caller
    - Define new meteor.pl deploy verb, thus bumping minor candidate version number
    - services.pl workload-summary fix

### 4.28.1

    Release date: 2026- 1-19

    - services.pl workload-summary fix

### 4.28.0

    Release date: 2026- 1-18

    - Fix Text metric publication when several differents labels are used
    - Fix JSON schemas
    - Define new bottomSummary and topSummary attributes, both defaulting to true, thus bumping minor candidate version number

### 4.27.1

    Release date: 2026- 1- 5

    - Fix the shell workload execution to only filter 'services.pl list' lines, aligning it on the cmd version

---
P. Wieser
- Last updated on 2026, Feb. 7th

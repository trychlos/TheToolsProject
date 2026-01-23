# TheToolsProject - Tools System and Working Paradigm for IT Production

## ChangeLog

### 4.30.0-rc.0

    Release date: 

    - New TTP::Meteor::isDevel() function, thus bumping minor candidate version number
    - meteor.pl deploy honors '--dummy' option
    - meteor.pl list --applications has '--dirs' and '--diffs' new options to list the directory when it is doesn't correspond to the name of the application
    - Fix meteor.pl publish to have the right per-day termination
    - Define new TTP::IRunnable->runnableOptionsCount() method
    - meteor.pl deploy --first option displays an help to prepare the first deployment to a new target

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
- Last updated on 2026, Jan. 21st

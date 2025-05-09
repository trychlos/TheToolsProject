# TheToolsProject - Tools System and Working Paradigm for IT Production

## ChangeLog

### 4.11.0-rc.0

    Release date: 

    - site.example/backup-monitor-daemon takes advantage of TTP::Node->hasService() method
    - Improve TTP::Node->hasService() method to take advantage of TTP::Service->list()
    - Define new TTP::Node->list() class method to get all available nodes, thus bumping minor candidate version number
    - Transform TTP::MongoDB and TTP::SqlServer into TTP::DBMS-derived classes

### 4.10.1

    Release date: 2025- 5- 9

    - Remove surrounding double quotes of commands and verbs counts
    - Fix node-monitor-daemon.pl array ref argument
    - Fix TTP::Service array ref computing

### 4.10.0

    Release date: 2025- 5- 8

    - Define service.schema.json (todo #112)
    - 'Services' configuration key is deprecated in favor of 'services', thus bumping minor candidate version number
    - JSON configurations are now searched only in etc/ subdirectories
    - 'servicesDirs' configuration is deprecated in favor of 'services.confDirs'
    - Remove TTP::Service->dirs() obsolete class method
    - Rename TTP::Service->enumerate() to TTP::Service->enum() to be consistent with TTP::Node
    - Define new TTP::Service->list(), updating node-monitor-daemon.pl and services.pl list accordingly
    - Obsolete 'services.pl list --type' in favor of 'services.pl --identifier' option to get consistent with 'environment.id' property
    - Credentials are now searched only in etc/ subdirectories
    - Obsolete 'archivesRoot' and 'archivesDir' properties in favor of 'archives.periodicDic' and 'archives.rootDir'

### 4.9.3

    Release date: 2025- 5- 7

    - TTP::Metric has missing 'use TTP::Telemetry;'
    - ttp.sh switch displays its help when run without argument (todo #135)
    - dbms.pl verbs emphasize that '--instance' is a Sql Server specific option (todo #138)
    - TTP::executionReport() honors 'enabled' configuration default value (todo #109)

### 4.9.2

    Release date: 2025- 5- 7

    - TTP::Metric enabled default value is true
    - TTP::Metric replace 'Telemetry' obsoleted value with 'telemetry'
    - Define new TTP::Telemetry::isHttpEnabled() isMqttEnabled() and isTextEnabled() functions
    - TTP::Metric has labelled error codes
    - Make project name and copyright notice consistent among all files (todo #133, #134)
    - Remove unused ttp.pl test verb (todo #131)
    - TTP::Metric enabled default value is true

### 4.9.1

    Release date: 2025- 5- 6

    - dbms.pl vars deprecated listBackupsdir() uses TTP::dbmsBackupsPeriodic() instead of recomputing the var
    - dbms.pl vars fix call to listBackupsPeriodic()
	- DBMS::computeDefaultBackupFilename() uses TTP::dbmsBackupsPeriodic() instead of recomputing the var
	- Path remove obsolete and no more used dbmsBackupsDir()

### 4.9.0

    Release date: 2025- 4-29

    - Homogeneize 'if exists(...)' into 'if defined(...)
    - Isolate sh-oriented test suite in its own directory tree
	- Creates cmd-oriented test suite
	- Define libexec/cmd/bootstrap.cmd, thus bumping minor candidate version number
	- Define t-cmd-bootstrap test
	- Define t-ttp-boostrap test
	- Define t-pl-commands test

### 4.8.1

    Release date: 2025- 4-23

    - Fix DaemonConfig->messagingEnabled() method calls
    - Improve RunnerDaemon debug messages
    - Remove dead code from TTP::Credentials
    - Improve DaemonConfig debug messages
	- Prevent any filesystem access during IJSONable evaluation

### 4.8.0

    Release date: 2025- 4-23

    - Define new verb daemon.pl hup (todo #99), thus bumping minor candidate version number
    - TTP::RunnerDaemon honors 'hup' command
    - DBMS no more uses TTP::SqlServer but only dynamically loads it
    - TTP::SqlServer only uses Win32::SqlServer on MSWin32 platforms
    - Check that each Perl module is loaded through its canonical name
    - Remove unused 'use' or 'require' sentences
    - Update ttp.sh code to support the test suite
    - Check sh and perl bootstrapping processes
    - Fix TTP::RunnerVerb->run() command when no verb is available
    - Have a test suite with an almost fixed architecture
    - Homogeneize and fix 'use if' sentences
    - Deprecate 'DBMS.backupsRoot' in favor of 'DBMS.backups.rootDir', 'DBMS.backupsDir' in favor of 'DBMS.backups.periodicDir' (todo #108)
    - Define new TTP::dbmsBackupsPeriodic() and TTP::dbmsBackupsRoot()
    - Deprecate TTP::Path::dbmsBackupsDir() in favor of TTP::Path::dbmsBackupsPeriodic()
    - Change the default default values of ttp.pl alerts from true to false, keeping default enabled to true
    - Define the default default values of telemetry.pl publish to false, having default enabled to true
    - dbms.pl backup and dbms.pl restore have and honor '--report' option
    - Introduce TTP::EP->bootstrapped()
    - Introduce msgDebug()

### 4.7.2

    Release date: 2025- 4-20

    - Fix regression in TTP::Message::printMsg() introduced when refactoring Message

### 4.7.1

    Release date: 2025- 4-20

    - Fix regression in TTP::IJSONable::var() introduced when coding #107

### 4.7.0

    Release date: 2025- 4-19

    - Change 'MQTTGateway' schema so that the port number is included in the host definition (todo #100), thus bumping minor candidate version number
    - Update 'MQTT' package according to new 'MQATTGateway' schema
    - Update mqtt-monitor-dameon.pl to only manage a single MQTT broker (todo #105)
    - TTP::IRunnable now uses qualifiers as an (illimited) array (todo #103)
    - Fix TTP::DaemonConfig configuration and schema - Do not modify the hardcoded constant
    - Remove TTP::nodesDirs() function
    - Remove TTP::Node->dirs() method in favor of updated TTP::Node->finder() (todo #106)
    - Obsolete TTP::host() in favor of already existing TTP::nodeName() (todo #102)
    - Obsolete 'credentialsDirs' variable in favor of 'credentials.dirs'
    - Deprecate 'nodes.dirs' variable in favor of 'nodes.confDirs'
    - Define 'copyFile' new macros SOURCEDIR, SOURCEFILE, TARGETDIR, TARGETFILE
    - Deprecate 'logsRoot' in favor of 'logs.rootDir'
    - Deprecate 'logsDaily' variable in favor of 'logs.periodicDir'
    - Deprecate 'logsCommands' variable in favor of 'logs.commandsDir'
    - Deprecate 'logsMain' variable in favor of 'logs.mainFile'
    - Deprecate 'Message' variable in favor of 'messages'
    - Deprecate, do not replace, nodeRoot() (todo #76)
    - Fix ttp.pl vars returning a value even when a key doesn't exist (todo #107)

### 4.6.0

    Release date: 2025- 4-18

    - Add 'stdinFromNull' option to TTP::commandExec(), defaulting to true
    - TTP::commandByOs() is renamed to commandByOS() for consistency reasons (todo #96)
    - TTP::RunnerCommand module is renamed RunnerVerb (todo #93)
    - Replace RunnerDaemon->startRun() with bootstrap() (todo #97), thus bumping minor candidate version number
    - ttp.pl push is now as verbose as ttp.pl pull (todo #91)
    - alerts-monitor-daemon.pl: rename 'scanInterval' property with 'workerInterval'
    - node-monitor-daemon.pl: rename 'runInterval' property with 'workerInterval'
    - TTP::commandExec() provided macros are globally substituted
    - Fix TTP::DaemonConfig messages when there is no listeningPort or listeningInterval
    - mqtt-monitor-daemon.pl is moved into libexec/daemons (todo #78)
    - Fix calls to TTP::Node->dirs()
    - Homogeneize TTP_DEBUG prints

### 4.5.1

    Release date: 2025- 4-17

    - TTP::commandExec() remove debug lines and temporary subroutines
    - node-monitor-daemon.pl: remove debug code, fixing TTP::commandExec() accordingly

### 4.5.0

    Release date: 2025- 4-17

    - TTP::commandExec() no more adds an EOL to stdout
	- ttp.pl alert: fix cmd vs. sh execution and quotings
    - logicals regular expression is no more an array as it can satisfies itself with a single string (todo #87)
    - Change TTP::commandExec() prototype to more standard '$command, $opts' (todo #86)
    - Deduplicate TTP::runnerDaemon::_mqtt_timeout() and TTP::runnerDaemon::messagingTimeout() (todo #83)
    - Bump minor candidate version number due to site.json change
    - RunnerDaemon better check listeningPort (todo #81) and listeningInterval (todo #82)
    - sufix is renamed suffix (todo #80)
    - TTP::commandByOs() now accepts 'withCommands' option
    - Define daemonsConfDirs site property (todo #89)
    - Define daemonsConfDirs site property and corresponding TTP::RunnerDaemon::execDirs() method (todo #90)
    - RunnerDaemon->new() changed options: 'path' becomes 'jsonPath', 'daemonize' becomes 'listener'
    - Introduce DaemonConfig in order to manage daemons configuration files
    - TTP::commandByOs() changes the default values of 'withCommand' and 'withCommands' to both false
    - Fix TTP::Path inclusion in DBMS.pm

### 4.4.1

    Release date: 2025- 4-14

    - TTP::EP: remove useless TTP::Command
    - TTP::RunnerDaemon: fix $ep usage
    - ttp.pl list no more uses TTP::RunnerCommand

### 4.4.0

    Release date: 2025- 4-14

    - TTP, TTP::EP: remove no more used debug variables
    - TTP::stackTrace() now ends the running program with exit code 1
    - Introduce TTP::Runner base class for all executables
    - Rename TTP::Command class to TTP::RunnerCommand making it a derived class of TTP::Runner
    - Rename TTP::Extern class to TTP::RunnerExtern making it a derived class of TTP::Runner
      Extern commands must now run my $command = TTP::runExtern();
    - Commands verbHelp() is renamed displayHelp()
    - External helpExtern() is renamed displayHelp()
    - Rename TTP::Daemon class to TTP::RunnerDaemon making it a derived class of TTP::Runner (todo #88)

### 4.3.0

    Release date: 2025- 4-14

    - TTP::Daemon define new httpingEnabled(), messagingEnabled() and textingEnabled() methods, thus bumping minor candidate version number
    - TTP::commandByOs() accepts now a 'jsonable' option to search data in
    - Define libexec/daemons/alerts-monitor-daemon.pl

### 4.2.6

    Release date: 2025- 4-13

    - Fix ttp.pl sizedir regression (todo #84)
    - Fix services.pl live regression (todo #85)

### 4.2.5

    Release date: 2025- 4-12

    - Merge the pending changes

### 4.2.4

    Release date: 2025- 4-12

    - Reorganize tools/etc vs. site.example/ files (todo #67)
    - Add a comment on how to get site variables (todo #77)
    - ttp.pl purgedirs now makes use of TTP::Path::removeTree(), this one increasing its verbosity
    - Get rid of (historical) $ep->{run} object, replacing it with $ep->runner() call

### 4.2.3

    Release date: 2025- 4-12

    - Fix TTP::Path::_copy_match_dir()

### 4.2.2

    Release date: 2025- 4-12

    - ttp.pl push no more quotes defined exclusions
    - TTP::Path::copyFile() accepts a command be specified as an option

### 4.2.1

    Release date: 2025- 4-12

    - Remove previous calls to localtime->strftime(), replacing them to Time::Moment->now->strftime() - See todo #60
    - ttp.pl copydirs and ttp.pl push use plural options i.e. --exclude-dirs and --exclude-files
    - ttp.pl pull doesn't try to exclude anything: it pulls all what has been pushed

### 4.2.0

    Release date: 2025- 4-12

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
    - Remove all instances of '$running' variable, using instead '$ep->runner()' (todo #63)
    - Remove Time::Piece dependency only using time::Moment which says it gives us a nanosecond precision, even if we are plainly satisfied with microseconds (todo #60)
      This notably means that all calls to 'localtime->strftime()' have to be replaced with 'Time::Moment->now->strftime()'
    - Homogenize strftime() formats when displaying date and time to the user - notably changes the log format to '2012-12-24 15:30:45.500 +01:00' adding the time zone
    - Remove TTP::Path::toopsConfigurationPath() obsolete function (todo #68)
    - Remove TTP::Path::serviceConfigurationPath() obsolete function (todo #71)
    - Remove TTP::Path::hostConfigurationPath() obsolete function (todo #73)
    - Remove TTP::Path::servicesConfigurationsDir() obsolete function (todo #70)
    - Remove TTP::Path::hostsConfigurationsDir() obsolete function (todo #72)
    - Remove TTP::Path::daemonsConfigurationsDir() obsolete function
    - Remove TTP::Path::siteConfigurationsDir() obsolete function (todo #69)
    - Deduplicate fromCommand() to TTP::Path (todo #75)
    - Rename 'makeExist' option to 'makeDirExist' for consistency (todo #74)
    - Remove TTP::Path::credentialsDir() obsolete function
    - Let an administrator define its own credentials subdirectories

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
- Last updated on 2025, May 9th

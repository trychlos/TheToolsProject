# The Tools Project - Tools System and Working Paradigm for IT Production

## Summary

1. [Todo](#todo)
2. [Done](#done)

---
## Todo

|   Id | Date       | Description and comment(s) |
| ---: | :---       | :---                       |
|    8 | 2024- 5- 2 | implements and honors text-based telemetry |
|   49 | 2024- 5-11 | all functions should check the type of their arguments and call TTP::stackTrace() on coding error |
|   52 | 2024- 5-17 | replace IP addresses by dns aliases to make easier the switch between live and backup productions (e.g. http gateway) |
|   53 | 2025- 1-17 | have a timeout on movedirs and purgedirs at least, maybe on all verbs which needs a network access + alert when this timeout is reached |
|      | 2025- 1-20 | daemon.pl command done |
|      | 2025- 4-10 | should build an inventory of what should be done, and what can be done |
|   54 | 2025- 1-19 | verbs should have an internal telemetry for the memory they consume, the execution elapsed time |
|   55 | 2025- 2-17 | daemon.pl status should have an option to publish to mqtt too |
|   57 | 2025- 2-17 | daemon.pl status should have an option to publish to text too |
|   59 | 2025- 2-18 | Daemon.pm: metrics for the daemon are windows-specific: re-code for unix'es |
|      | 2025- 4-14 | mswin32 metrics are isolated |
|   61 | 2025- 4- 8 | ttp.pl writejson should should actually be ttp.pl filewrite as the json is provided as a string on input - so this is not dedicated to json |
|   78 | 2024- 4-12 | some daemons should be moveable to libexec/daemons |
|      | 2024- 4-14 | alerts-monitor-daemon.pl is moved to libexec/daemons |
|      | 2024- 4-14 | node-monitor-daemon.pl is moved to libexec/daemons |
|      | 2024- 4-17 | mqtt-monitor-daemon.pl is moved to libexec/daemons |
|      | 2024- 4-17 | at the moment, still exists backup-monitor-daemon in site tree - to be evaluated |
|   99 | 2024- 4-17 | daemons should have a HUP command to fully reload their config |
|  108 |  |  |

---
## Done

|   Id | Date       | Description and comment(s) |
| ---: | :---       | :---                       |
|    1 | 2024- 5- 1 | get rid of tabular display in DBMS::execSQLCommand
|      | 2024- 5- 1 | done
|    2 | 2024- 5- 1 | SqlServer::execSql: why a first empty array in the result ?
|      | 2024- 5- 9 | unable to reproduce -> closed
|    3 | 2024- 5- 1 | DBMS::hashFromTabular() and displayTabular() should be moved to TTP
|      | 2024- 5- 1 | displayTabular() is done
|      | 2024- 5- 2 | hashFromTabular() is done
|    4 | 2024- 5- 1 | get rid of TTPVars
|      | 2024- 5- 2 | done
|    5 | 2024- 5- 1 | get rid of 'ttp'-prefixed TTP functions
|      | 2024- 5- 2 | done
|    6 | 2024- 5- 1 | IRunnable::filter() when called with direct command execution, only get the first line as in $running->filter( `$command` );
|	   | 	        | while having my $res = `$command`; $running->filter( $res ) is fine
|	   | 2024- 5- 2 | is move to TTP:;:filter() -> to be retested
|	   | 2024- 5- 3 | happened that the arguments format depends of the call mode -> fixed
|    7 | 2024- 5- 1 | Daemon.pm let the daemon advertise its status to http-based and text-based telemetry
|      |            | provides labels through json configuration
|	   | 2024- 5- 2 | labels can be added via the Daemon API - closing
|    9 | 2024- 5- 2 | [backup-monitor-daemon.pl tom59-backup-monitor-daemon] (WAR) TTP::Metric::_http_publish() Code: 400 MSG: text format parsing error in line 1: invalid metric name in comment
|      |            | line is "# HELP ttp_tom17-backup-monitor-daemon The last epoch time the daemon has been seen alive"
|      | 2024- 5- 2 | done (fix regexes)
|   10 | 2024- 5- 2 | backup-monitor-daemon.pl should advertise the remoteExecReportsDir but not as a msgVerbose as this later is too frequent
|      | 2024- 5- 2 | done (see #13)
|   11 | 2024- 5- 2 | check that httpMessaging and textMessaging can be disabled in daemon configuration (zero is it valid ?)
|      | 2024- 5- 2 | OK - needs interval be set to -1
|   12 | 2024- 5- 2 | daemon telemetry run since in sec, memory consumed
|      | 2024- 5- 2 | done for running since and for memory indicators
|   13 | 2024- 5- 2 | the daemon should be able to add its own mqtt topics
|      | 2024- 5- 2 | done
|   14 | 2024- 5- 2 | jsonRead should be only available through IJSONable (not in TTP)
|      | 2024- 5- 2 | actually jsonRead is moved from IJSONable to TTP (like jsonWrite and jsonAppend) -> done
|   15 | 2024- 1-29 | Toops::getOptions doesn't work as we do not know how to pass arguments to GetOptions() |
|      | 2024- 5- 2 | these are called 'named options' and are got in the function through a hash though I don't know at the moment how to dintinguish between a hash and a hash ref |
|	   | 2025- 1-17 | this is actually a list of values |
|      | 2025- 4-10 | this point was initially raised to make the verbs less verbose (or lighter whatever you prefer) - but this appears now of very few interest - just cancel |
|   16 | 2024- 5- 2 | on ws12dev1, startup doesn't send alerts
|      | 2024- 5- 5 | same even after scheduled tasks path update
|	   |            | "services.pl list -workload startup -commands -hidden" returns (wrong) "C:\Temp\Site\Commands\startup.cmd"
|	   | 		    | while "ttp.pl vars -key site,commandsDir" returns (right) "C:\INLINGUA\Site\Commands"
|	   | 2024- 5- 5 | fixed
|   17 | 2024- 5- 3 | ns332346 tasks didn't execute this morning 
|	   | 2024- 5- 3 | fixed with #24
|   18 | 2024- 5- 3 | ws22prod1
|      |            | Can't stat //ns3232346.ovh.net/C/INLINGUA/dailyLogs/240503/execReports: No such file or directory
|      |            |  at C:\INLINGUA\Site\Commands\backup-monitor-daemon.pl line 507.
|      |            | Can't stat //ns3232346.ovh.net/C/INLINGUA/dailyLogs/240503/execReports: No such file or directory
|      |            | at C:\INLINGUA\Site\Commands\backup-monitor-daemon.pl line 493.
|	   | 		    | One line is normal as long as there is not yet any execution report to create the directory
|	   | 		    | Why this second line ?
|	   | 2024- 5- 5 | seems that this doesn't reproduce - wait for two days...
|      | 2024- 5- 6 | stdout is clean as of 2024-05-06 09:43
|      | 2024- 5- 7 | stdout is clean as of 2024-05-06 09:41 -> closing
|   19 | 2024- 5- 3 | ws22prod1 tasks didn't execute to purge the logs directories
|	   | 2024- 5- 3 | fixed with #24
|   20 | 2024- 5- 3 | ttp.pl vars -logsCommands -nocolored
|      |            | ws12dev1 Can't call method "verbose" on an undefined value at C:\INLINGUA\dev\scripts\TheToolsProject\libexec\perl/TTP.pm line 774.
|	   | 		    | ns3232346 Can't call method "verbose" on an undefined value at C:\INLINGUA\TheToolsProject\libexec\perl/TTP.pm line 918.
|	   | 2024- 5- 3 | fixed
|   21 | 2024- 5- 3 | C:\INLINGUA\TheToolsProject\smtp\send.do.pl: Global symbol "$ttp" requires explicit package name (did you forget to declare "my $ttp"?) at C:\INLINGUA\TheToolsProject\libexec\perl/TTP/SMTP.pm line 48.
|	   | 2024- 5- 3 | fixed
|   22 | 2024- 5- 3 | Type of arg 1 to Try::Tiny::catch must be block or sub {} (not reference constructor) at C:\INLINGUA\TheToolsProject\libexec\perl/TTP/SMTP.pm line 99, near "};"
|	   | 2024- 5- 3 | fixed
|   23 | 2024- 5- 3 | [smtp.pl send] (ERR) Mail::send() expect smtp gateway, not found
|      | 2024- 5- 3 | fixed
|   24 | 2024- 5- 3 | ns3232346 C:\Users\inlingua-user>services.pl list -workload daily.morning -commands -hidden -nocolored
|      |            | [services.pl list] displaying workload commands defined in 'NS3232346\daily.morning'...
|      |            | [services.pl list] 0 found defined command(s)
|	   | 2024- 5- 3 | fixed with #6
|   25 | 2024- 5- 3 | ttp->var() and others should be able to return a composite data (not only a scalar) |
|      |            | and ttp.pl vars and others should be able to display them |
|	   | 2024- 5- 5 | they actually do return composite data - which just is not displayed by the verb |
|	   |            | see daemon.pl dbms.pl services.pl ttp.pl |
|	   | 2025- 4-10 | the guy who wants display these data must use Dumper() - cancel the point |
|   26 | 2024- 5- 3 | upgrade Canal33 backups from every.5h to every.2h (like the Tom's)
|      | 2024- 5-10 | done, installed on WS12...
|   27 | 2024- 5- 3 | archivesBackups should be set when purging dailyBackups so that we keep for example 5 days in daily Backups and move the 6th to the archives
|      | 2024- 5-10 | done
|   28 | 2024- 5- 3 | services.pl list -commands: tasks of any workload hide tasks of other workloads
|      | 2024- 5- 3 | fixed by requiring the exact wanted workload
|   29 | 2024- 5- 5 | ws22prod1 has no daemon for Tom17 -> why didn't it have started this morning
|      | 2024- 5- 5 | the scheduled tasks form yesterday was still running - thus not trigerred this morning
|   30 | 2024- 5- 5 | ns3232346 while Tom59 has four databases, the execution reports show only one -> should have one execution report per database
|      | 2024- 5- 6 | confirmed: all the databases are saved, but only three execution reports: tom17+tom21+tom59: the four execution reports are sent to the same file
|	   |            | happens that TTP::random() is evaluated at bootstrap time, so once for the three files
|      | 2024- 5- 6 | fixed by a) removing the TTP::random() evaluation from site.json b) replacing it with a temp file templating in ttp.pl writejson
|   31 | 2024- 5- 5 | ws22prod1 inlingua33_archive is restored at 6h, but not inlingua31_archive nor inlingua59_archive
|      | 2024- 5- 6 | confirmed - this may be because there was only one execution report json file, so should be fixed with #30
|      | 2024- 5- 9 | still there: to be fixed
|      | 2024- 5- 9 | fix execReports .json filenames and release...
|      | 2024- 5-10 | three databases on 4 are restored, the fourth is missing
|      | 2024- 5-10 | no more relies on sort order to detect new files
|      | 2024- 5-11 | that fixes the issue -> closing
|   32 | 2024- 5- 5 | services.pl list -> log the displayed results
|      | 2024- 5- 5 | done
|   33 | 2024- 5- 5 | happens that $self = undef in new() classes methods do not work -> have another way to report errors
|      | 2024- 5- 5 | that works that returned value must be tested!
|      | 2024- 5- 5 | done
|   34 | 2024- 5- 6 | (war) telemetry are not requested on tom17, tom21, tom59.live.morning
|      | 2024- 5- 6 | fixed
|   35 | 2024- 5- 6 | (VER) checkDatabaseExists() returning true should also have the database name
|      | 2024- 5- 6 | done
|   36 | 2024- 5- 6 | jsonWrite() returns $VAR1 = bless( [
|      |            | 'C:/INLINGUA/dailyLogs/240506/execReports/2024050606000238325-bcfd49ecb39b10149c0546b87b6865c8.json',
|      |            | 'C:\\INLINGUA\\dailyLogs\\240506\\execReports\\2024050606000238325-bcfd49ecb39b10149c0546b87b6865c8.json'
|      |            | ], 'Path::Tiny' ); -> two filenames ?
|	   | 2024- 5- 6 | this is just the standard return value of Path::Tiny->path() -> closed
|   37 | 2024- 5- 7 | ns3232346 no execution reports
|      | 2024- 5- 7 | fixed
|   38 | 2024- 5- 7 | backup daemons do not run
|      | 2024- 5- 7 | actually, they are running, but do not answer
|      | 2024- 5- 9 | they answer but this is very long
|	   | 2024- 5- 9 | fixed by the freeing of rl9pilot1 work space
|   39 | 2024- 5- 9 | daemons do not publish their status to mqtt
|      | 2024- 5- 9 | they actually do publish, but 1mn later an 'offline' is also published
|	   | 2024- 5- 9 | fixed by increasing the KEEPALIVE_INTERVAL for backup daemons
|   40 | 2024- 5- 9 | telemetry: should have environment and emitter(command+verb) - see the push gateway @ 10.122.1.15:9091
|      | 2024- 5- 9 | labels are added to dbms.pl status and dbms.pl telemetry, http.pl get, Daemon.pm, mswin.pl service, and ttp.pl sizedir
|	   |            | only telemetry.pl publish is left unchanged
|      | 2024- 5- 9 | done
|   41 | 2024- 5- 9 | daemons mqtt: publish all status informations
|      | 2024- 5- 9 | done
|   42 | 2024- 5- 9 | daemons mqtt: let the daemon have it own lastwill + rename messagingSub to statusSub ?
|      | 2024- 5- 9 | actually a disconnect will as only a topic,payload hash can be attached to a MQTT connection -> done
|   43 | 2024- 5- 9 | daemons http: Can\'t connect to 10.122.1.15:9091 (A connection attempt failed because the connected party did not properly respond after a period of time
|      | 2024- 5- 9 | the firewalld daemon was reactivated in rl9pilot1! => fixed
|   44 | 2024- 5-10 | backup daemon publishes http telemetry with very few labels (actually seems that some are missing)
|      | 2024- 5-10 | fixed
|   45 | 2024- 5-10 | review labelled mqtt publications: maybe could only use values when labelling as name=value
|      | 2024- 5-10 | done
|   46 | 2024- 5-10 | $ttp should be renamed $ep (for EP instance)
|      | 2024- 5-10 | done
|   47 | 2024- 5-11 | dbms mqtt telemetry for tables misses new environment,command,verb labels
|      | 2024- 5-11 | fixed
|   48 | 2024- 5-11 | remove ns230134_c network shortcut
|      | 2024- 5-12 | done
|   50 | 2024- 5-13 | dbms.pl vars doesn't replace the <HOST> macro
|      | 2024- 5-13 | fixed
|   51 | 2024- 5-13 | replace <HOST> macros by <NODE>
|      | 2024- 5-13 | done
|   56 | 2025- 2-17 | daemon.pl status should publish the same telemetries that Daemon.pm status advertising
|      | 2025- 2-17 | done
|   58 | 2025- 2-17 | all verbs: on arguments verbose, use 'got' instead of 'found'
|      | 2025- 2-18 | done
|   60 | 2025- 4- 6 | replace Time::Piece with Time::Moment |
|      | 2024- 4-11 | also homogeneize the date and time displays to the user to '2012-12-24 15:30:45.500 +01:00' - done |
|   62 | 2024- 4- 9 | 'MQTTGateway.broker' should be deprecated in favor of 'MQTTGateway.host' for consistency reason |
|      | 2025- 2-18 | done
|   63 | 2024- 4- 9 | replace all $running with $ep->runner() (a specific variable seems useless) |
|      | 2024- 4-10 | done |
|   64 | 2024- 4- 9 | when there is no execution node, trap_exit doesn't trigger sh/msgVerbose() on slim14 while triggering it in node93 - why ? |
|      | 2024- 4-10 | msgOut/msgVerbose have been added back to the libexec/sh path - so cancelled |
|   65 | 2024- 4- 9 | 'Environment' node property should be renamed 'environment |
|      | 2024- 4-10 | done |
|   66 | 2024- 4- 9 | 'environment.type' property should be renamed 'environment.id' |
|      | 2024- 4-10 | done |
|   67 | 2024- 4-10 | TheToolsProject/tools already includes an etc/ tree with samples - does we have also to have a site.samples/ tree ? |
|      | 2024- 4-12 | decision: tools/etc only includes README filesn, while site.example includes samples |
|      | 2024- 4-12 | done |
|   68 | 2024- 4-10 | remove TTP::Path::toopsConfigurationPath() |
|      | 2024- 4-11 | done |
|   69 | 2024- 4-10 | remove TTP::Path::siteConfigurationsDir() |
|      | 2024- 4-11 | done |
|   70 | 2024- 4-10 | remove TTP::Path::servicesConfigurationsDir() |
|      | 2024- 4-11 | done |
|   71 | 2024- 4-10 | remove TTP::Path::serviceConfigurationPath() |
|      | 2024- 4-11 | done |
|   72 | 2024- 4-10 | remove TTP::Path::hostsConfigurationsDir() |
|      | 2024- 4-11 | done |
|   73 | 2024- 4-10 | remove TTP::Path::hostConfigurationPath() |
|      | 2024- 4-11 | done |
|   74 | 2024- 4-10 | TTP::Path::fromCommand() option should be 'makeDirExist' for consistency |
|      | 2024- 4-11 | done |
|   75 | 2024- 4-11 | fromCommand() appears both in TTP and in TTP::Path |
|      | 2024- 4-11 | deduplicated to TTP::Path |
|   76 | 2024- 4-10 | nodeRoot() should be siteRoot(), shouldn'it ? and so be removed from TTP |
|      | 2024- 4-19 | whether a logical machine actually has or not a node 'root', aka the root mounted filesystem, it is never used in TTP code itself |
|      |            | this is only used as a variable when computing directories |
|      |            | as described in the 'site.schema.json', we allow to put any variable inside of the 'site' property object |
|      |            | there is so no nodeRoot neither siteRoot (from TTP point of view) but just a site variable which can be get with 'ttp.pl var -key' command |
|      |            | so just remove nodeRoot() |
|   77 | 2024- 4-10 | add a comment on how to get site variables |
|      | 2024- 4-12 | done |
|   79 | 2024- 4-12 | let a node override a site variable |
|      | 2024- 4-19 | this is already done and works well when the node json file is rightly addressed |
|   80 | 2024- 4-13 | sufix should be renamed suffix |
|      | 2024- 4-14 | done |
|   81 | 2024- 4-13 | TTP::Daemon should check that listeningPort is OK |
|      | 2024- 4-14 | done |
|   82 | 2024- 4-13 | TTP::Daemon should check that listeningInterval is OK |
|      | 2024- 4-14 | done |
|   83 | 2024- 4-13 | TTP::Daemon mqtt_timeout() and messagingTimeout() are same function |
|      | 2024- 4-14 | fixed |
|   84 | 2024- 4-13 | [ttp.pl sizedir] (ERR) do C:\INLINGUA\TheToolsProject\tools\ttp\sizedir.do.pl: |
|      |            |  ... syntax error at C:\INLINGUA\TheToolsProject\tools\ttp\sizedir.do.pl line 197, near "TTP::Path::( " |
|      | 2024- 4-13 | fixed |
|   85 | 2024- 4-13 | [services.pl live] (ERR) do /mnt/ws12dev1/INLINGUA/dev/scripts/TheToolsProject/tools/services/live.do.pl: |
|      |            | ... Can't call method "runner" on an undefined value at /mnt/ws12dev1/INLINGUA/dev/scripts/TheToolsProject/tools/services/live.do.pl line 129. |
|      | 2024- 4-13 | fixed |
|   86 | 2024- 4-13 | TTP::commandExec should have ( $command, { macros => {}} ) definition |
|      | 2024- 4-14 | done |
|   87 | 2024- 4-13 | logicals regular expression should be a single string as this is simpler and can still embed several re's |
|      | 2024- 4-14 | done |
|   88 | 2024- 4-14 | review classes hierarchy which should be something like Base -> Command -> Extern -> Daemon |
|      | 2024- 4-14 | done |
|   89 | 2024- 4-14 | daemonsDirs should be renamed to daemonsConfigDir and configurable in site.json |
|      | 2024- 4-14 | renamed as daemonsConfDirs and described in site.schema.json |
|   90 | 2024- 4-14 | also have daemonsExecDir and configurable in site.json |
|      | 2024- 4-14 | defined as daemonsExecDirs() |
|   91 | 2024- 4-15 | ttp.pl push and pull should have same level of verbosity |
|      | 2024- 4-17 | done |
|   92 | 2024- 4-15 | RunnerDaemon::dirs() and finder() should be qualified as in confDirs() and confFinder() |
|      | 2024- 4-17 | obsolete |
|   93 | 2024- 4-15 | RunnerCommand should be renamed RunnerVerb |
|      | 2024- 4-17 | done |
|   94 | 2024- 4-15 | TTP::run() should become TTP::runVerb() |
|      | 2024- 4-17 | TTP::runCommand() as some sense when run from, e.g. daemon.pl, which is a command - cancelled  |
|   95 | 2024- 4-15 | all getter on Dirs() should be in Path:: |
|      | 2024- 4-19 | we are keeping in TTP the functions the user is used to call from its json configurations files |
|      |            | there are two reasons: first it is shorter, and second we are not willing to expose the details of our internal modules |
|      |            | but we are moving the actual code to the relevant internal module |
|      |            | e.g. the user still can [eval:TTP::logsRoot()], which is redirected to TTP::Path::logsRoot(), which itself does the actual work |
|   96 | 2024- 4-16 | rename nullByOS with nullByOs (like commandByOs) |
|      | 2024- 4-17 | actually rather keep the byOS case |
|      | 2024- 4-17 | commandByOs() is now named commandByOS() - done |
|   97 | 2024- 4-16 | replace RunnerDaemon->startRun() with bootstrap() |
|      | 2024- 4-17 | done in node-monitor-daemon.pl and alerts-monitor-daemon.pl |
|   98 | 2024- 4-17 | remove TTP::Ports |
|      | 2024- 4-17 | done |
|  100 | 2024- 4-17 | review MQTT gateway schema so that the port number is part of the host address |
|      | 2024- 4-18 | done |
|  101 | 2024- 4-17 | review SMTP gateway schema so that the port number is part of the host address |
|      | 2024- 4-18 | cancelled as our SMTP module tries to guess the port number - so better to keep it explicit if needed |
|  102 | 2024- 4-17 | compare Node::hostname() vs TTP::host() |
|      | 2024- 4-18 | Node->_hostname() is a private method which returns the operating system host name, which acts as the default for the node name |
|      | 2024- 4-18 | Node->name() - which default to Node->_hostname() - is the canonical way of getting the node name |
|      | 2024- 4-18 | TTP::nodeName() exists and should be kept, is redirected to $ep->node()->name(). Fine. |
|      | 2024- 4-18 | TTP::host() is a duplicate of TTP::nodeName() - to be obsoleted |
|      | 2024- 4-18 | done |
|  103 | 2024- 4-17 | IRunnable qualifier should be an array of qualifiers |
|      | 2024- 4-18 | done |
|  104 | 2024- 4-17 | RunnerExtern should have the same type of bootstrap than RunnerDaemon |
|      | 2024- 4-18 | cancelled: using TTP::runExtern() let the 'ep' global be correctly allocated |
|  105 | 2024- 4-17 | each mqtt daemon connects to a single host: several hosts imply several daemons |
|      | 2024- 4-18 | done |
|  106 | 2024- 4-18 | Node->dirs() doesn't appear to be more relevant than DaemonConfig->confDirs() or execDirs() |
|      | 2024- 4-18 | TTP::nodesDirs() is obsoleted (not used) - TTP::Node->dirs() is obsoleted too in favor of (updated) TTP::Node->finder() |
|      | 2024- 4-18 | done |
|  107 | 2024- 4-19 | ttp.pl vars -key knownA,knownB,unknown returns knownA,knownB but should return undef |
|      | 2024- 4-19 | fixed |

---
P. Wieser
- Last updated on 2025, Apr. 17th

Toops, a perl-port of Tools

Toops for Windows:
- install Strawberry Perl 5.36 in C:\Strawberry
	5.36 is the last version managed by Win32::SqlServer provided binaries - so stay stuck to this version unless you are willing to install from sources
- install additionnal modules
	> Win32::SqlServer https://www.sommarskog.se/MSSQL/index.html
- install and configure Toops for your site:
	> set the PERL5LIB global environment variable to address the Toops directory
	> set a TTP_ROOTS global environment variable to address the directory which contains your site configuration
	> update the PATH to address all your Toops/bin directories
	> install CPAN packages
	  Data::UUID
	  Devel::StackTrace
	  Net::MQTT::Simple
	  Proc::Background
	  Proc::ProcessTable
	  vars::global

# when writing and using new commands or verbs
# --------------------------------------------
For debugging purposes workload.cmd may take additional arguments, say for example -dummy, -verbose, -nocolored
As these additional arguments will be passed to each and every executed TTP command/verb, all these must at least *support* (if not honor) these standard arguments.

Topics tree

  published
	<emitter_host> / executionReport / <command.pl> / <verb>														-> the json execution report (command/verb dependant)
	<emitter_host> / telemetry / dbms / <instance> / database / <database> / dbsize / <size_item>					-> size_item_value
	<emitter_host> / telemetry / dbms / <instance> / database / <database> / table / <table_name> / rows_count		-> size_item_value

  retained
	<emitter_host> / daemon / <daemon_name> / status				where daemon_name is the base name of the json file, without the extension

Data
====
DBMS
	instance
		The instance identifies the DBMS instance (by the fact) into which we will find databases and other objects.
		The instance can be specified, either explicitly in the command-line, or via the service name.
		When explicit, the instance name is not checked, but see package below.
		When a service is instead specified, then the instance comes from in the order of precedence:
		- the host configuration through a 'Service.<service>.DBMS.instance' key in the service section
		- the host configuration through a 'DBMS.instance' key (acts as a default for all services in this host)
		- the service configuration as a 'DBMS.instance' key (acts as a default for all hosts which define this service)
		- the site configuration as a 'DBMS.instance' key (acts as a default for all services and hosts)
		First (non empty) found wins, which doesn't imply that the found instance exists and is valid.
	database
		One of the main objects in a DBMS, most often the place where all application datas are stored.
		The database can be specified, either explicitly in the command-line, or via the service name.
		When explicit, the database name is not checked unless the command wants to make it exists in the addressed instance.
		When a service is instead specified, then the involved databases come from in the order of precedence:
		- the host configuration through a 'Service.<service>.DBMS.databases' key in the service section
		- the host configuration through a 'DBMS.databases' key (acts as a default for all services in this host)
		- the service configuration as a 'DBMS.databases' key (acts as a default for all hosts which define this service)
		- the site configuration as a 'DBMS.databases' key (acts as a default for all services and hosts)
		First (non empty) found wins, which doesn't imply that the found databases exist and are valid.
	package
		In Toops, each DBMS is accessed via a specialized, dynamically loaded, Perl package. The package is addressed through the instance name.
		Package is identified in order of precedence by:
		- the host configuration through a 'Service.<service>.DBMS.byInstance.<instance>.package' key in the service section
		- the host configuration through a 'DBMS.byInstance.<instance>.package' key (acts as a default for all services in this host)
		- the service configuration as a 'DBMS.byInstance.<instance>.package' key (acts as a default for all hosts which define this service)
		- the site configuration as a 'DBMS.byInstance.<instance>.package' key (acts as a default for all services and hosts)
		First (non empty) found wins, which doesn't imply that the found package exists and is valid.

Journal
=======
 2024- 5- 2 livraison v3.0

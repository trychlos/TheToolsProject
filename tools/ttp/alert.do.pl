# @(#) send an alert
#
# @(-) --[no]help              print this message, and exit [${help}]
# @(-) --[no]colored           color the output depending of the message level [${colored}]
# @(-) --[no]dummy             dummy run (ignored here) [${dummy}]
# @(-) --[no]verbose           run verbosely [${verbose}]
# @(-) --emitter=<name>        the emitter's name [${emitter}]
# @(-) --level=<level>         the alert level [${level}]
# @(-) --title=<name>          the alert title [${title}]
# @(-) --message=<name>        the alert message [${message}]
# @(-) --[no]file              create a JSON file alert, monitorable e.g. by the alert daemon [${file}]
# @(-) --[no]mqtt              send the alert on the MQTT bus [${mqtt}]
# @(-) --[no]smtp              send the alert by SMTP [${smtp}]
# @(-) --[no]sms               send the alert by SMS [${sms}]
# @(-) --list-levels           display the known alert levels [${listLevels}]
# @(-) --options=<options>     additional options to be passed to the command [${options}]
#
# The Tools Project - Tools System and Working Paradigm for IT Production
# Copyright (©) 1998-2023 Pierre Wieser (see AUTHORS)
# Copyright (©) 2023-2025 PWI Consulting
#
# TheToolsProject is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License as
# published by the Free Software Foundation; either version 2 of the
# License, or (at your option) any later version.
#
# TheToolsProject is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
# General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with TheToolsProject; see the file COPYING. If not,
# see <http://www.gnu.org/licenses/>.

use strict;
use utf8;
use warnings;

use File::Spec;
use JSON;
use Path::Tiny;
use Time::Moment;

use TTP::Path;
use TTP::SMTP;

my $defaults = {
	help => 'no',
	colored => 'no',
	dummy => 'no',
	verbose => 'no',
	emitter => $ep->node()->name(),
	level => 'INFO',
	title => '',
	message => '',
	listLevels => 'no',
	options => ''
};

my $opt_emitter = $defaults->{emitter};
my $opt_level = INFO;
my $opt_title = $defaults->{title};
my $opt_message = $defaults->{message};
my $opt_listLevels = false;
my $opt_options = $defaults->{options};

my $opt_file = TTP::var([ 'alerts', 'withFile', 'default' ]);
$opt_file = true if !defined $opt_file;
$defaults->{file} = $opt_file ? 'yes' : 'no';
my $opt_file_set = false;

my $opt_mqtt = TTP::var([ 'alerts', 'withMqtt', 'default' ]);
$opt_mqtt = true if !defined $opt_mqtt;
$defaults->{mqtt} = $opt_mqtt ? 'yes' : 'no';
my $opt_mqtt_set = false;

my $opt_smtp = TTP::var([ 'alerts', 'withSmtp', 'default' ]);
$opt_smtp = true if !defined $opt_smtp;
$defaults->{smtp} = $opt_smtp ? 'yes' : 'no';
my $opt_smtp_set = false;

my $opt_sms = TTP::var([ 'alerts', 'withSms', 'default' ]);
$opt_sms = true if !defined $opt_sms;
$defaults->{sms} = $opt_sms ? 'yes' : 'no';
my $opt_sms_set = false;

# -------------------------------------------------------------------------------------------------
# build the alert data object

sub buildAlertData {
	my $data = {
		emitter => $opt_emitter,
		level => $opt_level,
		# ISO 8601 format
		stamp => Time::Moment->now->strftime( '%Y-%m-%d %H:%M:%S.%6N %:z' )
	};
	$data->{title} = $opt_title if $opt_title;
	$data->{message} = $opt_message if $opt_message;
	return $data;
}

# -------------------------------------------------------------------------------------------------
# display the known alert levels

sub doDisplayLevels {
	msgOut( "displaying known alert levels..." );
	my $levels = TTP::Message::knownLevels();
	my $count = 0;
	foreach my $level( @{$levels} ){
		if( ref( $level ) eq 'ARRAY' ){
			my $first = shift @{$level};
			print " $first (".join( ', ', @{$level} ).")".EOL;
		} else {
			print " $level".EOL;
		}
		$count += 1;
	}
	msgOut( "found $count known alert levels" );
}

# -------------------------------------------------------------------------------------------------
# send the alert by file
# as far as we are concerned here, this is just executing the configured command
# managed macros:
# - JSON: the alert data as a JSON stringified object

sub doFileAlert {
	msgOut( "creating a new '$opt_level' JSON file alert..." );
	my $command = TTP::commandByOs([ 'alerts', 'withFile' ]);
	my $dir = TTP::alertsFileDropdir();
	if( !$command ){
		my $file = File::Spec->catfile( $dir, 'alert-'.Time::Moment->now->strftime( '%Y%m%d%H%M%S%6N' ).'.json' );
		my $verbose = $ep->runner()->verbose() ? "-verbose" : "-noverbose";
		$command = "ttp.pl writejson -nocolored $verbose -file $file -data '<JSON>' <OPTIONS>";
	}
	TTP::Path::makeDirExist( $dir );
	my $prettyJson = $ep->var([ 'alerts', 'withFile', 'prettyJson' ]);
	$prettyJson = true if !defined $prettyJson;
	my $data = buildAlertData();
	my $json = $prettyJson ? JSON->new->pretty->encode( $data ) : JSON->new->encode( $data );
	my $macros = {
		EMITTER => $opt_emitter,
		LEVEL => $opt_level,
		TITLE => $opt_title,
		MESSAGE => $opt_message,
		JSON => $json,
		STAMP => $data->{stamp},
		OPTIONS => $opt_options
	};
	execute( $command, $macros, "success", "alert by File NOT OK" );
}

# -------------------------------------------------------------------------------------------------
# send the alert by mqtt
# as far as we are concerned here, this is just executing the configured command

sub doMqttAlert {
	msgOut( "publishing a '$opt_level' alert on MQTT bus..." );
	my $data = buildAlertData();
	my $topic = $ep->var([ 'alerts', 'withMqtt', 'topic' ]) || $ep->node()->name()."/alerts/".Time::Moment->from_string( $data->{stamp} )->epoch();
	my $command = TTP::commandByOs([ 'alerts', 'withMqtt' ]);
	if( !$command ){
		my $verbose = $ep->runner()->verbose() ? "-verbose" : "-noverbose";
		$command = "mqtt.pl publish -nocolored $verbose -topic $topic -payload '<JSON>' <OPTIONS>";
	}
	my $json = JSON->new->encode( $data );
	my $macros = {
		EMITTER => $opt_emitter,
		LEVEL => $opt_level,
		TITLE => $opt_title,
		MESSAGE => $opt_message,
		JSON => $json,
		STAMP => $data->{stamp},
		OPTIONS => $opt_options
	};
	execute( $command, $macros, "success", "alert by MQTT NOT OK" );
}

# -------------------------------------------------------------------------------------------------
# send the alert by SMS
# Expects have some sort of configuration in TTP json
# No default command as of v4.1

sub doSmsAlert {
	msgOut( "sending a '$opt_level' alert by SMS..." );
	my $command = TTP::commandByOs([ 'alerts', 'withSms' ]);
	if( !$command ){
		my $verbose = $ep->runner()->verbose() ? "-verbose" : "-noverbose";
		#$command = "smtp.pl send -nocolored $verbose -to <RECIPIENTS> -subject <TITLE> -text <MESSAGE> <OPTIONS>";
	}
	my $recipients = $ep->var([ 'alerts', 'withSms', 'recipients' ]) || [];
	if( $command && scalar( @{$recipients} )){
		my $prettyJson = $ep->var([ 'alerts', 'withSms', 'prettyJson' ]);
		$prettyJson = true if !defined $prettyJson;
		my $data = buildAlertData();
		my $json = $prettyJson ? JSON->new->pretty->encode( $data ) : JSON->new->encode( $data );
		my $macros = {
			EMITTER => $opt_emitter,
			LEVEL => $opt_level,
			TITLE => $opt_title,
			MESSAGE => $opt_message,
			JSON => $json,
			STAMP => $data->{stamp},
			OPTIONS => $opt_options,
			RECIPIENTS => join( ',', @{$recipients} )
		};
		execute( $command, $macros, "success", "alert by SMS NOT OK" );
	}
}

# -------------------------------------------------------------------------------------------------
# send the alert by SMTP
# send the mail by executing the configured command

sub doSmtpAlert {
	msgOut( "publishing a '$opt_level' alert by SMTP..." );
	my $command = TTP::commandByOs([ 'alerts', 'withSmtp' ]);
	if( !$command ){
		my $verbose = $ep->runner()->verbose() ? "-verbose" : "-noverbose";
		$command = "smtp.pl send -nocolored $verbose -to <RECIPIENTS> -subject <TITLE> -text '<MESSAGE>' <OPTIONS>";
	}
	my $recipients = $ep->var([ 'alerts', 'withSmtp', 'recipients' ]) || [ 'root@localhost' ];
	my $prefixTitle = $ep->var([ 'alerts', 'withSmtp', 'prefixTitle' ]);
	$prefixTitle = true if !defined $prefixTitle;
	my $title;
	if( $prefixTitle ){
		$title = "[$opt_level] Alert";
		$title .= " - $opt_title" if $opt_title;
	} else {
		$title = $opt_title || "[$opt_level] Alert";
	}
	my $prettyJson = $ep->var([ 'alerts', 'withSmtp', 'prettyJson' ]);
	$prettyJson = true if !defined $prettyJson;
	my $data = buildAlertData();
	my $json = $prettyJson ? JSON->new->pretty->encode( $data ) : JSON->new->encode( $data );
	my $macros = {
		EMITTER => $opt_emitter,
		LEVEL => $opt_level,
		TITLE => $title,
		MESSAGE => $opt_message,
		JSON => $json,
		STAMP => $data->{stamp},
		OPTIONS => $opt_options,
		RECIPIENTS => join( ',', @{$recipients} )
	};
	execute( $command, $macros, "success", "alert by SMTP NOT OK" );
}

# -------------------------------------------------------------------------------------------------
# execute the prepared command
# (I):
# - the command
# - the macros to be substituted
# - the message to be displayed in case of success
# - the message to be displayed in case of an error

sub execute {
	my ( $command, $macros, $msgok, $msgerr ) = @_;
	my $result = TTP::commandExec({
		command => $command,
		macros => $macros
	});
	if( $result->{success} ){
		msgOut( $msgok );
	} else {
		msgErr( $msgerr );
	}
}

# =================================================================================================
# MAIN
# =================================================================================================

if( !GetOptions(
	"help!"				=> sub { $ep->runner()->help( @_ ); },
	"colored!"			=> sub { $ep->runner()->colored( @_ ); },
	"dummy!"			=> sub { $ep->runner()->dummy( @_ ); },
	"verbose!"			=> sub { $ep->runner()->verbose( @_ ); },
	"emitter=s"			=> \$opt_emitter,
	"level=s"			=> \$opt_level,
	"title=s"			=> \$opt_title,
	"message=s"			=> \$opt_message,
	"file!"				=> sub {
		my( $name, $value ) = @_;
		$opt_file = $value;
		$opt_file_set = true;
	},
	"mqtt!"				=> sub {
		my( $name, $value ) = @_;
		$opt_mqtt = $value;
		$opt_mqtt_set = true;
	},
	"smtp!"				=> sub {
		my( $name, $value ) = @_;
		$opt_smtp = $value;
		$opt_smtp_set = true;
	},
	"sms!"				=> sub {
		my( $name, $value ) = @_;
		$opt_sms = $value;
		$opt_sms_set = true;
	},
	"list-levels!"		=> \$opt_listLevels,
	"options=s"			=> \$opt_options )){
		msgOut( "try '".$ep->runner()->command()." ".$ep->runner()->verb()." --help' to get full usage syntax" );
		TTP::exit( 1 );
}

if( $ep->runner()->help()){
	$ep->runner()->displayHelp( $defaults );
	TTP::exit();
}

msgVerbose( "got colored='".( $ep->runner()->colored() ? 'true':'false' )."'" );
msgVerbose( "got dummy='".( $ep->runner()->dummy() ? 'true':'false' )."'" );
msgVerbose( "got verbose='".( $ep->runner()->verbose() ? 'true':'false' )."'" );
msgVerbose( "got emitter='$opt_emitter'" );
msgVerbose( "got level='$opt_level'" );
msgVerbose( "got title='$opt_title'" );
msgVerbose( "got message='$opt_message'" );
msgVerbose( "got file='".( $opt_file ? 'true':'false' )."'" );
msgVerbose( "got mqtt='".( $opt_mqtt ? 'true':'false' )."'" );
msgVerbose( "got smtp='".( $opt_smtp ? 'true':'false' )."'" );
msgVerbose( "got sms='".( $opt_sms ? 'true':'false' )."'" );
msgVerbose( "got list-levels='".( $opt_listLevels ? 'true':'false' )."'" );
msgVerbose( "got options='$opt_options'" );

if( $opt_listLevels ){
	# nothing to check here
} else {
	# all data are mandatory (and we provide a default value for all but the title and the message)
	msgErr( "emitter is empty, but shouldn't" ) if !$opt_emitter;
	msgErr( "level is empty, but shouldn't" ) if !$opt_level;
	my $content = $opt_title.$opt_message;
	msgErr( "both title and message are empty, but at least one of them should be set" ) if !$content;
	# level must be known
	msgErr( "level='$opt_level' is unknown" ) if $opt_level && !TTP::Message::isKnownLevel( $opt_level );

	# disabled media are just ignored (or refused if option was explicit)
	if( $opt_file ){
		my $enabled = $ep->var([ 'alerts', 'withFile', 'enabled' ]);
		$enabled = true if !defined $enabled;
		if( !$enabled ){
			if( $opt_file_set ){
				msgErr( "File medium is disabled, --file option is not valid" );
			} else {
				msgWarn( "File medium is disabled and thus ignored" );
				$opt_file = false;
			}
		}
	}
	if( $opt_mqtt ){
		my $enabled = $ep->var([ 'alerts', 'withMqtt', 'enabled' ]);
		$enabled = true if !defined $enabled;
		if( !$enabled ){
			if( $opt_mqtt_set ){
				msgErr( "MQTT medium is disabled, --mqtt option is not valid" );
			} else {
				msgWarn( "MQTT medium is disabled and thus ignored" );
				$opt_mqtt = false;
			}
		}
	}
	if( $opt_smtp ){
		my $enabled = $ep->var([ 'alerts', 'withSmtp', 'enabled' ]);
		$enabled = true if !defined $enabled;
		if( !$enabled ){
			if( $opt_smtp_set ){
				msgErr( "SMTP medium is disabled, --smtp option is not valid" );
			} else {
				msgWarn( "SMTP medium is disabled and thus ignored" );
				$opt_smtp = false;
			}
		}
	}
	if( $opt_sms ){
		my $enabled = $ep->var([ 'alerts', 'withSms', 'enabled' ]);
		$enabled = true if !defined $enabled;
		if( !$enabled ){
			if( $opt_sms_set ){
				msgErr( "SMS medium is disabled, --sms option is not valid" );
			} else {
				msgWarn( "SMS medium is disabled and thus ignored" );
				$opt_sms = false;
			}
		}
	}

	# at least one medium must be specified
	if( !$opt_file && !$opt_mqtt && !$opt_smtp && !$opt_sms ){
		msgErr( "at least one of '--file', '--mqtt', '--smtp' or '--sms' options must be specified" );
	}
}

if( !TTP::errs()){
	if( $opt_listLevels ){
		doDisplayLevels();
	} else {
		$opt_level = uc $opt_level;
		doFileAlert() if $opt_file;
		doMqttAlert() if $opt_mqtt;
		doSmtpAlert() if $opt_smtp;
		doSmsAlert() if $opt_sms;
	}
}

TTP::exit();

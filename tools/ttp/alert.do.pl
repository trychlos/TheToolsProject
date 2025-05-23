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
# @(-) --[no]sms               send the alert by SMS [${sms}]
# @(-) --[no]smtp              send the alert by SMTP [${smtp}]
# @(-) --[no]tts               send the alert with text-to-speech [${tts}]
# @(-) --list-levels           display the known alert levels [${listLevels}]
# @(-) --options=<options>     additional options to be passed to the command [${options}]
#
# TheToolsProject - Tools System and Working Paradigm for IT Production
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
$opt_file = false if !defined $opt_file;
my $file_enabled = $ep->var([ 'alerts', 'withFile', 'enabled' ]);
$file_enabled = true if !defined $file_enabled;
msgErr( "alerts.withFile.default=true while alerts.withFile.enabled=false which is not consistent" ) if $opt_file && !$file_enabled;
$defaults->{file} = $opt_file && $file_enabled ? 'yes' : 'no';
my $opt_file_set = false;

my $opt_mqtt = TTP::var([ 'alerts', 'withMqtt', 'default' ]);
$opt_mqtt = false if !defined $opt_mqtt;
my $mqtt_enabled = $ep->var([ 'alerts', 'withMqtt', 'enabled' ]);
$mqtt_enabled = true if !defined $mqtt_enabled;
msgErr( "alerts.withMqtt.default=true while alerts.withMqtt.enabled=false which is not consistent" ) if $opt_mqtt && !$mqtt_enabled;
$defaults->{mqtt} = $opt_mqtt && $mqtt_enabled ? 'yes' : 'no';
my $opt_mqtt_set = false;

my $opt_sms = TTP::var([ 'alerts', 'withSms', 'default' ]);
$opt_sms = false if !defined $opt_sms;
my $sms_enabled = $ep->var([ 'alerts', 'withSms', 'enabled' ]);
$sms_enabled = true if !defined $sms_enabled;
msgErr( "alerts.withSms.default=true while alerts.withSms.enabled=false which is not consistent" ) if $opt_sms && !$sms_enabled;
$defaults->{sms} = $opt_sms && $sms_enabled ? 'yes' : 'no';
my $opt_sms_set = false;

my $opt_smtp = TTP::var([ 'alerts', 'withSmtp', 'default' ]);
$opt_smtp = false if !defined $opt_smtp;
my $smtp_enabled = $ep->var([ 'alerts', 'withSmtp', 'enabled' ]);
$smtp_enabled = true if !defined $smtp_enabled;
msgErr( "alerts.withSmtp.default=true while alerts.withSmtp.enabled=false which is not consistent" ) if $opt_smtp && !$smtp_enabled;
$defaults->{smtp} = $opt_smtp && $smtp_enabled ? 'yes' : 'no';
my $opt_smtp_set = false;

my $opt_tts = TTP::var([ 'alerts', 'withTextToSpeech', 'default' ]);
$opt_tts = false if !defined $opt_tts;
my $tts_enabled = $ep->var([ 'alerts', 'withTextToSpeech', 'enabled' ]);
$tts_enabled = true if !defined $tts_enabled;
msgErr( "alerts.withTextToSpeech.default=true while alerts.withTextToSpeech.enabled=false which is not consistent" ) if $opt_tts && !$tts_enabled;
$defaults->{tts} = $opt_tts && $tts_enabled ? 'yes' : 'no';
my $opt_tts_set = false;

my $alertStamp = Time::Moment->now;

# -------------------------------------------------------------------------------------------------
# build the alert data object

sub buildAlertData {
	my $data = {
		emitter => $opt_emitter,
		level => $opt_level,
		# ISO 8601 format
		stamp => $alertStamp->strftime( '%Y-%m-%d %H:%M:%S.%6N %:z' )
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
	my $commands = TTP::commandByOS([ 'alerts', 'withFile' ]);
	my $dir = TTP::alertsFileDropdir();
	if( !$commands || !scalar( @{$commands} )){
		my $file = File::Spec->catfile( $dir, 'alert-'.$alertStamp->strftime( '%Y%m%d%H%M%S%6N' ).'.json' );
		my $verbose = $ep->runner()->verbose() ? "-verbose" : "-noverbose";
		$commands = [ "ttp.pl writejson -nocolored $verbose -file $file -data \"<JSON>\" <OPTIONS>" ];
	}
	TTP::Path::makeDirExist( $dir );
	my $prettyJson = $ep->var([ 'alerts', 'withFile', 'prettyJson' ]);
	$prettyJson = true if !defined $prettyJson;
	$prettyJson = false;
	my $data = buildAlertData();
	my $json = $prettyJson ? JSON->new->pretty->encode( $data ) : JSON->new->encode( $data );
	# protect the double quotes against the CMD.EXE command-line
	$json =~ s/"/\\"/g;
	my $macros = {
		EMITTER => $opt_emitter,
		LEVEL => $opt_level,
		TITLE => $opt_title,
		MESSAGE => $opt_message,
		JSON => $json,
		STAMP => $data->{stamp},
		OPTIONS => $opt_options
	};
	execute( $commands, $macros, "success", "alert by File NOT OK" );
}

# -------------------------------------------------------------------------------------------------
# send the alert by mqtt
# as far as we are concerned here, this is just executing the configured command

sub doMqttAlert {
	msgOut( "publishing a '$opt_level' alert on MQTT bus..." );
	my $data = buildAlertData();
	my $topic = $ep->var([ 'alerts', 'withMqtt', 'topic' ]) || $ep->node()->name()."/alerts/".$alertStamp->strftime( '%Y%m%d%H%M%S%6N' );
	my $commands = TTP::commandByOS([ 'alerts', 'withMqtt' ]);
	if( !$commands || !scalar( @{$commands} )){
		my $verbose = $ep->runner()->verbose() ? "-verbose" : "-noverbose";
		$commands = [ "mqtt.pl publish -nocolored $verbose -topic $topic -payload \"<JSON>\" <OPTIONS>" ];
	}
	my $json = JSON->new->encode( $data );
	# protect the double quotes against the CMD.EXE command-line
	$json =~ s/"/\\"/g;
	my $macros = {
		EMITTER => $opt_emitter,
		LEVEL => $opt_level,
		TITLE => $opt_title,
		MESSAGE => $opt_message,
		JSON => $json,
		STAMP => $data->{stamp},
		OPTIONS => $opt_options
	};
	execute( $commands, $macros, "success", "alert by MQTT NOT OK" );
}

# -------------------------------------------------------------------------------------------------
# send the alert by SMS
# Expects have some sort of configuration in TTP json
# No default command as of v4.1

sub doSmsAlert {
	msgOut( "sending a '$opt_level' alert by SMS..." );
	my $commands = TTP::commandByOS([ 'alerts', 'withSms' ]);
	if( $commands && scalar( @{$commands} )){
		my $recipients = $ep->var([ 'alerts', 'withSms', 'recipients' ]) || [];
		if( scalar( @{$recipients} )){
			my $prettyJson = $ep->var([ 'alerts', 'withSms', 'prettyJson' ]);
			$prettyJson = true if !defined $prettyJson;
			my $data = buildAlertData();
			my $json = $prettyJson ? JSON->new->pretty->encode( $data ) : JSON->new->encode( $data );
			my $textfname = TTP::getTempFileName();
			my $fh = path( $textfname );
			$fh->spew( $json );
			my $macros = {
				EMITTER => $opt_emitter,
				LEVEL => $opt_level,
				TITLE => $opt_title,
				MESSAGE => $opt_message,
				JSON => $json,
				STAMP => $data->{stamp},
				OPTIONS => $opt_options,
				RECIPIENTS => join( ',', @{$recipients} ),
				CONTENTFNAME => $textfname
			};
			execute( $commands, $macros, "success", "alert by SMS NOT OK" );
		} else {
			msgWarn( "no recipients is provided by the site: it is not possible to send SMS" );
		}
	} else {
		msgWarn( "no command is provided by the site: it is not possible to send SMS" );
	}
}

# -------------------------------------------------------------------------------------------------
# send the alert by SMTP
# send the mail by executing the configured command

sub doSmtpAlert {
	msgOut( "publishing a '$opt_level' alert by SMTP..." );
	my $commands = TTP::commandByOS([ 'alerts', 'withSmtp' ]);
	if( !$commands || !scalar( @{$commands} )){
		my $verbose = $ep->runner()->verbose() ? "-verbose" : "-noverbose";
		$commands = [ "smtp.pl send -nocolored $verbose -to <RECIPIENTS> -subject \"<TITLE>\" -textfname <CONTENTFNAME> <OPTIONS>" ];
	}
	my $recipients = $ep->var([ 'alerts', 'withSmtp', 'recipients' ]) || [ 'root@localhost' ];
	my $prefixTitle = $ep->var([ 'alerts', 'withSmtp', 'prefixTitle' ]);
	$prefixTitle = true if !defined $prefixTitle;
	my $title;
	if( $prefixTitle ){
		$title = "[$opt_level] Alert";
		if( $opt_title ){
			$title .= " - $opt_title";
		} else {
			$title .= " from $opt_emitter";
		}
	} else {
		$title = $opt_title || "[$opt_level] Alert from $opt_emitter";
	}
	my $prettyJson = $ep->var([ 'alerts', 'withSmtp', 'prettyJson' ]);
	$prettyJson = true if !defined $prettyJson;
	my $data = buildAlertData();
	my $json = $prettyJson ? JSON->new->pretty->encode( $data ) : JSON->new->encode( $data );
	# put the mail into a temp file
	my $mailfrom = $ep->var([ 'SMTPGateway', 'mailfrom' ]);
	my $text = "Hi,\n
An alert has been raised:
$json
Best regards.
$mailfrom
";
	my $textfname = TTP::getTempFileName();
	my $fh = path( $textfname );
	$fh->spew( $text );
	my $macros = {
		EMITTER => $opt_emitter,
		LEVEL => $opt_level,
		TITLE => $title,
		MESSAGE => $opt_message,
		JSON => $json,
		STAMP => $data->{stamp},
		OPTIONS => $opt_options,
		RECIPIENTS => join( ',', @{$recipients} ),
		CONTENTFNAME => $textfname
	};
	execute( $commands, $macros, "success", "alert by SMTP NOT OK" );
}

# -------------------------------------------------------------------------------------------------
# send the alert by Text-To-Speech

sub doTextToSpeechAlert {
	msgOut( "publishing a '$opt_level' alert with Text-To-Speech..." );
	my $commands = TTP::commandByOS([ 'alerts', 'withTextToSpeech' ]);
	if( $commands && scalar( @{$commands} )){
		my $text = TTP::var([ 'alerts', 'withTextToSpeech', 'text' ]);
		$text = "Alert from <EMITTER> <TITLE> <MESSAGE>" if !$text;
		my $data = buildAlertData();
		my $macros = {
			EMITTER => $opt_emitter,
			LEVEL => $opt_level,
			TITLE => $opt_title,
			MESSAGE => $opt_message,
			JSON => encode_json( $data ),
			STAMP => $data->{stamp},
			OPTIONS => $opt_options,
			TEXT => $text
		};
		execute( $commands, $macros, "success", "alert by TTS NOT OK" );
	}
}

# -------------------------------------------------------------------------------------------------
# execute the prepared command
# (I):
# - the commands array ref
# - the macros to be substituted
# - the message to be displayed in case of success
# - the message to be displayed in case of an error

sub execute {
	my ( $commands, $macros, $msgok, $msgerr ) = @_;
	my $result = TTP::commandExec( $commands, {
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
	"sms!"				=> sub {
		my( $name, $value ) = @_;
		$opt_sms = $value;
		$opt_sms_set = true;
	},
	"smtp!"				=> sub {
		my( $name, $value ) = @_;
		$opt_smtp = $value;
		$opt_smtp_set = true;
	},
	"tts!"				=> sub {
		my( $name, $value ) = @_;
		$opt_tts = $value;
		$opt_tts_set = true;
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
msgVerbose( "got sms='".( $opt_sms ? 'true':'false' )."'" );
msgVerbose( "got smtp='".( $opt_smtp ? 'true':'false' )."'" );
msgVerbose( "got tts='".( $opt_tts ? 'true':'false' )."'" );
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
		if( !$file_enabled ){
			if( $opt_file_set ){
				msgErr( "File medium is disabled, --file option is not valid" );
			} else {
				msgWarn( "File medium is disabled and thus ignored" );
				$opt_file = false;
			}
		}
	}
	if( $opt_mqtt ){
		if( !$mqtt_enabled ){
			if( $opt_mqtt_set ){
				msgErr( "MQTT medium is disabled, --mqtt option is not valid" );
			} else {
				msgWarn( "MQTT medium is disabled and thus ignored" );
				$opt_mqtt = false;
			}
		}
	}
	if( $opt_sms ){
		if( !$sms_enabled ){
			if( $opt_sms_set ){
				msgErr( "SMS medium is disabled, --sms option is not valid" );
			} else {
				msgWarn( "SMS medium is disabled and thus ignored" );
				$opt_sms = false;
			}
		}
	}
	if( $opt_smtp ){
		if( !$smtp_enabled ){
			if( $opt_smtp_set ){
				msgErr( "SMTP medium is disabled, --smtp option is not valid" );
			} else {
				msgWarn( "SMTP medium is disabled and thus ignored" );
				$opt_smtp = false;
			}
		}
	}
	if( $opt_tts ){
		if( !$tts_enabled ){
			if( $opt_tts_set ){
				msgErr( "Text-To-Speech medium is disabled, --tts option is not valid" );
			} else {
				msgWarn( "Text-To-Speech medium is disabled and thus ignored" );
				$opt_tts = false;
			}
		}
	}

	# at least one medium must be specified
	if( !$opt_file && !$opt_mqtt && !$opt_smtp && !$opt_sms && !$opt_tts ){
		msgWarn( "at least one of '--file', '--mqtt', '--smtp', '--sms' or '--tts' options should be specified" );
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
		doTextToSpeechAlert() if $opt_tts;
	}
}

TTP::exit();

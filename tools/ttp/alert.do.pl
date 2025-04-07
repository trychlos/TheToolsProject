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
# @(-) --[no]json              set a JSON file alert to be monitored by the alert daemon [${json}]
# @(-) --[no]mqtt              send the alert on the MQTT bus [${mqtt}]
# @(-) --[no]smtp              send the alert by SMTP [${smtp}]
# @(-) --[no]sms               send the alert by SMS [${sms}]
# @(-) --list-levels           display the known alert levels [${listLevels}]
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

use JSON;
use Path::Tiny;
use Time::Piece;

use TTP::Message;
use TTP::SMTP;
my $running = $ep->runner();

my $defaults = {
	help => 'no',
	colored => 'no',
	dummy => 'no',
	verbose => 'no',
	emitter => $ep->node()->name(),
	level => 'INFO',
	title => '',
	message => '',
	listLevels => 'no'
};

my $opt_emitter = $defaults->{emitter};
my $opt_level = INFO;
my $opt_title = $defaults->{title};
my $opt_message = $defaults->{message};
my $opt_listLevels = false;

my $opt_json = TTP::var([ 'alerts', 'withJson', 'default' ]);
$opt_json = true if !defined $opt_json;
$defaults->{json} = $opt_json ? 'yes' : 'no';
my $opt_json_set = false;

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
# - DATA: the JSON content

sub doJsonAlert {
	msgOut( "creating a new '$opt_level' json alert..." );
	my $command = $ep->var([ 'alerts', 'withFile', 'command' ]);
	if( $command ){
		my $dir = $ep->var([ 'alerts', 'withFile', 'dropDir' ]);
		if( $dir ){
			TTP::makeDirExist( $dir );
			my $data = {
				emitter => $opt_emitter,
				level => $opt_level,
				message => $opt_message,
				host => $ep->node()->name(),
				stamp => localtime->strftime( "%Y-%m-%d %H:%M:%S" )
			};
			my $json = JSON->new;
			my $str = $json->encode( $data );
			# protect the double quotes against the CMD.EXE command-line
			$str =~ s/"/\\"/g;
			$command =~ s/<DATA>/$str/;
			my $dummy = $running->dummy() ? "-dummy" : "-nodummy";
			my $verbose = $running->verbose() ? "-verbose" : "-noverbose";
			print `$command -nocolored $dummy $verbose`;
			#$? = 256
			my $res = $? == 0;
			if( $res ){
				msgOut( "success" );
			} else {
				msgErr( $! );
			}
		} else {
			msgWarn( "unable to get a dropDir for 'withFile' alerts" );
			msgErr( "alert by file NOT OK" );
		}
	} else {
		msgWarn( "unable to get a command for alerts by file" );
		msgErr( "alert by file NOT OK" );
	}
}

# -------------------------------------------------------------------------------------------------
# send the alert by mqtt
# as far as we are concerned here, this is just executing the configured command
# managed macros:
# - TOPIC
# - PAYLOAD
# - OPTIONS

sub doMqttAlert {
	msgOut( "publishing a '$opt_level' alert on MQTT bus..." );
	my $command = $ep->var([ 'alerts', 'withMqtt', 'command' ]);
	my $res = false;
	if( $command ){
		my $topic = $ep->node()->name()."/alert";
		my $data = {
			emitter => $opt_emitter,
			level => $opt_level,
			message => $opt_message,
			host => $ep->node()->name(),
			stamp => localtime->strftime( "%Y-%m-%d %H:%M:%S" )
		};
		my $json = JSON->new;
		my $str = $json->encode( $data );
		# protect the double quotes against the CMD.EXE command-line
		$str =~ s/"/\\"/g;
		$command =~ s/<DATA>/$str/;
		$command =~ s/<SUBJECT>/$topic/;
		my $options = "";
		$command =~ s/<OPTIONS>/$options/;
		my $dummy = $running->dummy() ? "-dummy" : "-nodummy";
		my $verbose = $running->verbose() ? "-verbose" : "-noverbose";
		print `$command -nocolored $dummy $verbose`;
		$res = ( $? == 0 );
	} else {
		msgWarn( "unable to get a command for alerts by MQTT" );
	}
	if( $res ){
		msgOut( "success" );
	} else {
		msgErr( "alert by MQTT NOT OK" );
	}
}

# -------------------------------------------------------------------------------------------------
# send the alert by SMS
# Expects have some sort of configuration in TTP json

sub doSmsAlert {
	msgOut( "sending a '$opt_level' alert by SMS..." );
	my $res = false;
	my $command = $ep->var([ 'alerts', 'withSms', 'command' ]);
	if( $command ){
		my $text = "Hi,
An alert has been raised:
- level is $opt_level
- timestamp is ".localtime->strftime( "%Y-%m-%d %H:%M:%S" )."
- emitter is $opt_emitter
- message is '$opt_message'
Best regards.
";
		my $textfname = TTP::getTempFileName();
		my $fh = path( $textfname );
		$fh->spew( $text );
		$command =~ s/<OPTIONS>/-textfname $textfname/;
		my $dummy = $running->dummy() ? "-dummy" : "-nodummy";
		my $verbose = $running->verbose() ? "-verbose" : "-noverbose";
		print `$command -nocolored $dummy $verbose`;
		$res = ( $? == 0 );
	} else {
		msgWarn( "unable to get a command for alerts by SMS" );
	}
	if( $res ){
		msgOut( "success" );
	} else {
		msgErr( "alert by SMS NOT OK" );
	}
}

# -------------------------------------------------------------------------------------------------
# send the alert by SMTP
# send the mail by executing the configured command
# managed macros:
# - SUBJECT
# - OPTIONS

sub doSmtpAlert {
	msgOut( "publishing a '$opt_level' alert by SMTP..." );
	my $res = false;
	my $command = $ep->var([ 'alerts', 'withSmtp', 'command' ]);
	if( $command ){
		my $subject = "[$opt_level] Alert";
		my $text = "Hi,
An alert has been raised:
- level is $opt_level
- timestamp is ".localtime->strftime( "%Y-%m-%d %H:%M:%S" )."
- emitter is $opt_emitter
- message is '$opt_message'
Best regards.
";
		my $textfname = TTP::getTempFileName();
		my $fh = path( $textfname );
		$fh->spew( $text );
		$command =~ s/<SUBJECT>/$subject/;
		$command =~ s/<OPTIONS>/-textfname $textfname/;
		my $dummy = $running->dummy() ? "-dummy" : "-nodummy";
		my $verbose = $running->verbose() ? "-verbose" : "-noverbose";
		print `$command -nocolored $dummy $verbose`;
		$res = ( $? == 0 );
	} else {
		msgWarn( "unable to get a command for alerts by SMTP" );
	}
	if( $res ){
		msgOut( "success" );
	} else {
		msgErr( "alert by SMTP NOT OK" );
	}
}

# =================================================================================================
# MAIN
# =================================================================================================

if( !GetOptions(
	"help!"				=> \$ep->{run}{help},
	"colored!"			=> \$ep->{run}{colored},
	"dummy!"			=> \$ep->{run}{dummy},
	"verbose!"			=> \$ep->{run}{verbose},
	"emitter=s"			=> \$opt_emitter,
	"level=s"			=> \$opt_level,
	"title=s"			=> \$opt_title,
	"message=s"			=> \$opt_message,
	"json!"				=> sub {
		my( $name, $value ) = @_;
		$opt_json = $value;
		$opt_json_set = true;
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
	"list-levels!"		=> \$opt_listLevels )){
		msgOut( "try '".$running->command()." ".$running->verb()." --help' to get full usage syntax" );
		TTP::exit( 1 );
}

if( $running->help()){
	$running->verbHelp( $defaults );
	TTP::exit();
}

msgVerbose( "got colored='".( $running->colored() ? 'true':'false' )."'" );
msgVerbose( "got dummy='".( $running->dummy() ? 'true':'false' )."'" );
msgVerbose( "got verbose='".( $running->verbose() ? 'true':'false' )."'" );
msgVerbose( "got emitter='$opt_emitter'" );
msgVerbose( "got level='$opt_level'" );
msgVerbose( "got title='$opt_title'" );
msgVerbose( "got message='$opt_message'" );
msgVerbose( "got json='".( $opt_json ? 'true':'false' )."'" );
msgVerbose( "got mqtt='".( $opt_mqtt ? 'true':'false' )."'" );
msgVerbose( "got smtp='".( $opt_smtp ? 'true':'false' )."'" );
msgVerbose( "got sms='".( $opt_sms ? 'true':'false' )."'" );
msgVerbose( "got list-levels='".( $opt_listLevels ? 'true':'false' )."'" );

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
	if( $opt_json ){
		my $enabled = $ep->var([ 'alerts', 'withJson', 'enabled' ]);
		$enabled = true if !defined $enabled;
		if( !$enabled ){
			if( $opt_json_set ){
				msgErr( "JSON medium is disabled, --json option is not valid" );
			} else {
				msgWarn( "JSON medium is disabled and thus ignored" );
				$opt_json = false;
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
	if( !$opt_json && !$opt_mqtt && !$opt_smtp && !$opt_sms ){
		msgErr( "at least one of '--json', '--mqtt', '--smtp' or '--sms' options must be specified" ) if !$opt_emitter;
	}
}

if( !TTP::errs()){
	if( $opt_listLevels ){
		doDisplayLevels();
	} else {
		$opt_level = uc $opt_level;
		doJsonAlert() if $opt_json;
		doMqttAlert() if $opt_mqtt;
		doSmtpAlert() if $opt_smtp;
		doSmsAlert() if $opt_sms;
	}
}

TTP::exit();

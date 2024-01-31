# @(#) send an alert
#
# @(-) --[no]help              print this message, and exit [${help}]
# @(-) --[no]colored           color the output depending of the message level [${colored}]
# @(-) --[no]dummy             dummy run (ignored here) [${dummy}]
# @(-) --[no]verbose           run verbosely [${verbose}]
# @(-) --emitter=<name>        the emitter's name [${emitter}]
# @(-) --level=<level>         the alert level [${level}]
# @(-) --message=<name>        the alert message [${message}]
# @(-) --[no]json              set a JSON file alert to be monitored by the alert daemon [${json}]
# @(-) --[no]mqtt              send the alert on the MQTT bus [${mqtt}]
# @(-) --[no]smtp              send the alert by SMTP [${smtp}]
# @(-) --[no]sms               send the alert by SMS [${sms}]
#
# The Tools Project: a Tools System and Paradigm for IT Production
# Copyright (©) 1998-2023 Pierre Wieser (see AUTHORS)
# Copyright (©) 2023-2024 PWI Consulting
#
# The Tools Project is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License as
# published by the Free Software Foundation; either version 2 of the
# License, or (at your option) any later version.
#
# The Tools Project is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
# General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with The Tools Project; see the file COPYING. If not,
# see <http://www.gnu.org/licenses/>.

use JSON;
use Path::Tiny;
use Time::Moment;

use TTP::SMTP;

my $defaults = {
	help => 'no',
	colored => 'no',
	dummy => 'no',
	verbose => 'no',
	emitter => $ttp->node()->name(),
	level => 'INFO',
	message => ''
};

my $opt_emitter = $defaults->{emitter};
my $opt_level = INFO;
my $opt_message = $defaults->{message};
my $opt_json = TTP::var([ 'alerts', 'withFile', 'enabled' ]);
my $opt_mqtt = TTP::var([ 'alerts', 'withMqtt', 'enabled' ]);
my $opt_smtp = TTP::var([ 'alerts', 'withSmtp', 'enabled' ]);
my $opt_sms = TTP::var([ 'alerts', 'withSms', 'enabled' ]);

$defaults->{json} = $opt_json ? 'yes' : 'no';
$defaults->{mqtt} = $opt_mqtt ? 'yes' : 'no';
$defaults->{smtp} = $opt_smtp ? 'yes' : 'no';
$defaults->{sms} = $opt_sms ? 'yes' : 'no';

# -------------------------------------------------------------------------------------------------
# send the alert by file
# as far as we are concerned here, this is just executing the configured command
# managed macros:
# - DATA: the JSON content

sub doJsonAlert {
	msgOut( "creating a new '$opt_level' json alert..." );
	my $command = $ttp->var([ 'alerts', 'withFile', 'command' ]);
	if( $command ){
		my $dir = $ttp->var([ 'alerts', 'withFile', 'dropDir' ]);
		if( $dir ){
			TTP::makeDirExist( $dir );
			my $data = {
				emitter => $opt_emitter,
				level => $opt_level,
				message => $opt_message,
				host => $ttp->node()->name(),
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
			$res = $? == 0;
			msgOut( "success" );
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
	my $command = $ttp->var([ 'alerts', 'withMqtt', 'command' ]);
	my $res = false;
	if( $command ){
		my $topic = $ttp->node()->name()."/alert";
		my $data = {
			emitter => $opt_emitter,
			level => $opt_level,
			message => $opt_message,
			host => $ttp->node()->name(),
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
		my $dummy = $opt_dummy ? "-dummy" : "-nodummy";
		my $verbose = $opt_verbose ? "-verbose" : "-noverbose";
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
# Expects have some sort of configuration in Toops json

sub doSmsAlert {
	msgOut( "sending a '$opt_level' alert by SMS..." );
	my $res = false;
	my $command = $ttp->var([ 'alerts', 'withSms', 'command' ]);
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
		my $dummy = $opt_dummy ? "-dummy" : "-nodummy";
		my $verbose = $opt_verbose ? "-verbose" : "-noverbose";
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
	my $command = $ttp->var([ 'alerts', 'withSmtp', 'command' ]);
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
		my $dummy = $opt_dummy ? "-dummy" : "-nodummy";
		my $verbose = $opt_verbose ? "-verbose" : "-noverbose";
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
	"help!"				=> \$ttp->{run}{help},
	"colored!"			=> \$ttp->{run}{colored},
	"dummy!"			=> \$ttp->{run}{dummy},
	"verbose!"			=> \$ttp->{run}{verbose},
	"emitter=s"			=> \$opt_emitter,
	"level=s"			=> \$opt_level,
	"message=s"			=> \$opt_message,
	"json!"				=> \$opt_json,
	"mqtt!"				=> \$opt_mqtt,
	"smtp!"				=> \$opt_smtp,
	"sms!"				=> \$opt_sms )){

		msgOut( "try '".$running->command()." ".$running->verb()." --help' to get full usage syntax" );
		TTP::exit( 1 );
}

if( $running->help()){
	$running->verbHelp( $defaults );
	TTP::exit();
}

msgVerbose( "found colored='".( $running->colored() ? 'true':'false' )."'" );
msgVerbose( "found dummy='".( $running->dummy() ? 'true':'false' )."'" );
msgVerbose( "found verbose='".( $running->verbose() ? 'true':'false' )."'" );
msgVerbose( "found emitter='$opt_emitter'" );
msgVerbose( "found level='$opt_level'" );
msgVerbose( "found message='$opt_message'" );
msgVerbose( "found json='".( $opt_json ? 'true':'false' )."'" );
msgVerbose( "found mqtt='".( $opt_mqtt ? 'true':'false' )."'" );
msgVerbose( "found smtp='".( $opt_smtp ? 'true':'false' )."'" );
msgVerbose( "found sms='".( $opt_sms ? 'true':'false' )."'" );

# all data are mandatory (and we provide a default value for all but the message)
msgErr( "emitter is empty, but shouldn't" ) if !$opt_emitter;
msgErr( "message is empty, but shouldn't" ) if !$opt_message;
msgErr( "level is empty, but shouldn't" ) if !$opt_level;
#level must be known
msgErr( "level='$opt_level' is unknown" ) if $opt_level && !TTP::Message::isKnownLevel( $opt_level );

# at least one of json or mqtt media must be specified
if( !$opt_json && !$opt_mqtt && !$opt_smtp && !$opt_sms ){
	msgErr( "at least one of '--json', '--mqtt', '--smtp' or '--sms' options must be specified" ) if !$opt_emitter;
}

if( !TTP::errs()){
	$opt_level = uc $opt_level;
	doJsonAlert() if $opt_json;
	doMqttAlert() if $opt_mqtt;
	doSmtpAlert() if $opt_smtp;
	doSmsAlert() if $opt_sms;
}

TTP::exit();

# Copyright (@) 2023-2024 PWI Consulting
#
# SMTP gateway management.
#
# We expect find in configuration:
# - an email host server to connect to, with an account and a password
# - a default sender
#
# We expect be provided
# - subject, mailto, content

package TTP::SMTP;

use strict;
use warnings;

use Data::Dumper;
use Email::Stuffer;
use Email::Sender::Transport::SMTP;
use Try::Tiny;
use vars::global qw( $ep );

use TTP;
use TTP::Constants qw( :all );
use TTP::Credentials;
use TTP::Message qw( :all );

# ------------------------------------------------------------------------------------------------
# send a mail through the addressed SMTP gateway
# (I):
# - a hashref with following keys:
#   > subject
#   > text for text body, may be empty
#   > html for HTML body, may be empty
#   > to as a string or an array ref of target addresses
#   > cc as a string or an array ref of CarbonCopy addresses
#   > bcc as a string or an array ref of BlindCopy addresses
#   > join as a string or an array ref of filenames to attach to the mail
#   > from, defaulting to the smtp gateway 'mailfrom' default sender, which itself defaults to 'me@localhost'
#   > debug: defaulting to the smtp gateway 'debug' property, which itself defaults to false
# (O):
# - returns true|false
sub send {
	my ( $msg ) = @_;
	#print Dumper( $msg );
	my $res = false;
	msgErr( "Mail::send() expect parms as a hashref, not found" ) if !$msg || ref( $msg ) ne 'HASH';
	msgErr( "Mail::send() expect subject, not found" ) if $msg && ref( $msg ) eq 'HASH' && !$msg->{subject};
	msgErr( "Mail::send() expect a content, not found" ) if $msg && ref( $msg ) eq 'HASH' && !$msg->{text} && !$msg->{html};
	msgErr( "Mail::send() expect at least one target email address, not found" ) if $msg && ref( $msg ) eq 'HASH' && !$msg->{to};
	if( !TTP::errs()){
		my $sender = $ep->var([ 'SMTPGateway', 'mailfrom' ]);
		$sender = 'me@localhost' if !$sender;
		$sender = $msg->{from} if exists $msg->{from};

		my $email = Email::Stuffer->new({
			from => $sender,
			to => $msg->{to},
			cc => $msg->{cc},
			bcc => $msg->{bcc},
			subject => $msg->{subject}
		});
		if( scalar( @{$msg->{join}} )){
			foreach my $join ( @{$msg->{join}} ){
				$email->attach_file( $join );
			}
		}
		$email->text_body( $msg->{text} ) if $msg->{text};
		$email->html_body( $msg->{html} ) if $msg->{html};

		my $debug = $ep->var([ 'SMTPGateway', 'debug' ]);
		$debug = false if !defined $debug;
		$debug = $msg->{debug} if exists $msg->{debug};

		# Email::Sender::Transport::SMTP is able to choose a default port if we set the 'ssl' option to 'ssl' or true
		# but is not able to set a default ssl option starting from the port - fix that here
		my $opts = {};
		$opts->{host} = $ep->var([ 'SMTPGateway', 'host' ]) || 'localhost';
		$opts->{port} = $ep->var([ 'SMTPGateway', 'port' ]);
		#$opts->{sasl_authenticator} = $sasl;
		
		# use Credentials package to manage username and password (if any)
		my $username = TTP::Credentials::get([ 'SMTPGateway', 'username' ]);
		my $password = TTP::Credentials::get([ 'SMTPGateway', 'password' ]);
		$opts->{sasl_username} = $username if $username;
		$opts->{sasl_password} = $password if $username;

		$opts->{helo} = $ep->var([ 'SMTPGateway', 'helo' ]) || $ep->node()->name();
		$opts->{ssl} = $ep->var([ 'SMTPGateway', 'security' ]);
		if( $opts->{port} && !$opts->{ssl} ){
			$opts->{ssl} = 'ssl' if $opts->{port} == 465;
			$opts->{ssl} = 'starttls' if $opts->{port} == 587;
		}
		$opts->{timeout} = $ep->var([ 'SMTPGateway', 'timeout' ]) || 60;
		$opts->{debug} = $debug;
		$opts->{ssl_options} = { SSL_verify_mode => IO::Socket::SSL::SSL_VERIFY_NONE };
		my $transport = Email::Sender::Transport::SMTP->new( $opts );
		$email->transport( $transport );

		try {
			$res = $email->send();
		} catch {
			msgWarn( "Mail::send() $!" );
			print Dumper( $res );
		};
	}
	return $res;
}

1;

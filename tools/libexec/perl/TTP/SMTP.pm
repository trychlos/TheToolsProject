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
die __PACKAGE__ . " must be loaded as TTP::SMTP\n" unless __PACKAGE__ eq 'TTP::SMTP';

use strict;
use utf8;
use warnings;

use Data::Dumper;
use Email::Stuffer;
use Email::Sender::Transport::SMTP;
use Try::Tiny;

use TTP;
use vars::global qw( $ep );

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
#   > to as an array ref of target addresses
#   > cc as an array ref of CarbonCopy addresses
#   > bcc as an array ref of BlindCopy addresses
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
	if( TTP::errs()){
		TTP::stackTrace();
	} else {
		my $sender = $msg->{from} || $ep->var([ 'SMTPGateway', 'mailfrom' ]) || "No Reply <no-reply\@localhost>";

		my $email = Email::Stuffer->new({
			from => $sender,
			subject => $msg->{subject}
		});
		if( scalar( @{$msg->{to}} )){
			$email->to( @{$msg->{to}} );
		}
		if( scalar( @{$msg->{cc}} )){
			$email->cc( @{$msg->{cc}} );
		}
		if( scalar( @{$msg->{bcc}} )){
			$email->bcc( @{$msg->{bcc}} );
		}
		if( scalar( @{$msg->{join}} )){
			foreach my $join ( @{$msg->{join}} ){
				$email->attach_file( $join );
			}
		}
		$email->text_body( $msg->{text} ) if $msg->{text};
		$email->html_body( $msg->{html} ) if $msg->{html};

		my $opts = {};
		$opts->{host} = $ep->var([ 'SMTPGateway', 'host' ]);

		# if no MTA is configured, then default to local MTA (hoping it exists) and just send
		if( !$opts->{host} ){
			msgVerbose( "no configured MTA: just sending" );
			$res = $email->send;
			# returns "bless( {}, 'Email::Sender::Success' )"
			$res = ( ref( $res ) eq "Email::Sender::Success" );

		# a MTA is configured, use it
		} else {
			msgVerbose( "configured MTA is '$opts->{host}': try to use it" );
			# Email::Sender::Transport::SMTP is able to choose a default port if we set the 'ssl' option to 'ssl' or true
			# but is not able to set a default ssl option starting from the port - fix that here
			$opts->{port} = $ep->var([ 'SMTPGateway', 'port' ]);
			#$opts->{sasl_authenticator} = $sasl;

			my $debug = $ep->var([ 'SMTPGateway', 'debug' ]);
			$debug = false if !defined $debug;
			$debug = $msg->{debug} if defined $msg->{debug};

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
			msgVerbose( "sending with opts=".Dumper( $opts ));

			try {
				# see https://github.com/rjbs/Email-Stuffer/issues/17
				$res = $email->send({ to => [ @{$msg->{to}}, @{$msg->{bcc}} ] });
			} catch {
				msgWarn( "Mail::send() $!" );
				print Dumper( $res );
			};
		}
	}
	return $res;
}

1;

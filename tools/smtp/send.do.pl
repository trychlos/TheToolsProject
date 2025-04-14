# @(#) send an email using the configured SMTP gateway
#
# @(-) --[no]help              print this message, and exit [${help}]
# @(-) --[no]colored           color the output depending of the message level [${colored}]
# @(-) --[no]dummy             dummy run (ignored here) [${dummy}]
# @(-) --[no]verbose           run verbosely [${verbose}]
# @(-) --subject=<subject>     the email subject [${subject}]
# @(-) --text=<text>           the text body [${text}]
# @(-) --textfname=<filename>  the filename which contains the text body [${textfname}]
# @(-) --html=<html>           the HTML body [${html}]
# @(-) --htmlfname=<filename>  the filename which contains the HTML body [${htmlfname}]
# @(-) --to=<to>               a comma-separated list of target email addresses [${to}]
# @(-) --cc=<cc>               a comma-separated list of target email addresses to copy to [${cc}]
# @(-) --bcc=<bcc>             a comma-separated list of target email addresses to bind copy to [${bcc}]
# @(-) --join=<filename>       a comma-separated list of filenames to attach to email [${join}]
# @(-) --[no]debug             debug the SMTP transport phase [${debug}]
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

use Path::Tiny;

use TTP::SMTP;

my $defaults = {
	help => 'no',
	colored => 'no',
	dummy => 'no',
	verbose => 'no',
	subject => '',
	text => '',
	textfname => '',
	html => '',
	htmlfname => '',
	to => '',
	cc => '',
	bcc => '',
	join => '',
	debug => 'no'
};

my $opt_subject = $defaults->{subject};
my $opt_text = $defaults->{text};
my $opt_textfname = $defaults->{textfname};
my $opt_html = $defaults->{html};
my $opt_htmlfname = $defaults->{htmlfname};
my $opt_to = $defaults->{to};
my $opt_cc = $defaults->{cc};
my $opt_bcc = $defaults->{bcc};
my $opt_join = $defaults->{join};
my $opt_debug = undef;

# -------------------------------------------------------------------------------------------------
# send the email

sub doSend {
	msgOut( "sending an email to $opt_to..." );
	my @to = split( /,/, $opt_to );
	my @cc = split( /,/, $opt_cc );
	my @bcc = split( /,/, $opt_bcc );
	my @join = split( /,/, $opt_join );
	my $text = undef;
	$text = $opt_text if $opt_text;
	if( $opt_textfname ){
		my $fh = path( $opt_textfname );
		$text = $fh->slurp_utf8;
	}
	my $html = undef;
	$html = $opt_html if $opt_html;
	if( $opt_htmlfname ){
		$html = path( $opt_htmlfname )->slurp_utf8;
	}
	my $res = TTP::SMTP::send({
		subject => $opt_subject,
		text => $text,
		html => $html,
		to => \@to,
		cc => \@cc,
		bcc => \@bcc,
		join => \@join,
		debug => $opt_debug
	});
	if( $res ){
		msgOut( "success" );
	} else {
		msgErr( "NOT OK" );
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
	"subject=s"			=> \$opt_subject,
	"text=s"			=> \$opt_text,
	"textfname=s"		=> \$opt_textfname,
	"html=s"			=> \$opt_html,
	"htmlfname=s"		=> \$opt_htmlfname,
	"to=s"				=> \$opt_to,
	"cc=s"				=> \$opt_cc,
	"bcc=s"				=> \$opt_bcc,
	"join=s"			=> \$opt_join,
	"debug!"			=> \$opt_debug )){

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
msgVerbose( "got subject='$opt_subject'" );
msgVerbose( "got text='$opt_text'" );
msgVerbose( "got textfname='$opt_textfname'" );
msgVerbose( "got html='$opt_html'" );
msgVerbose( "got htmlfname='$opt_htmlfname'" );
msgVerbose( "got to='$opt_to'" );
msgVerbose( "got cc='$opt_cc'" );
msgVerbose( "got bcc='$opt_bcc'" );
msgVerbose( "got join='$opt_join'" );
msgVerbose( "got debug='".( defined $opt_debug ? ( $opt_debug ? 'true':'false' ) : '(undef)' )."'" );

# all data are mandatory, and we must provide some content, either text or html
msgErr( "subject is empty, but shouldn't" ) if !$opt_subject;
msgErr( "content is empty, but shouldn't" ) if !$opt_text && !$opt_textfname && !$opt_html && !$opt_htmlfname;
msgErr( "addresses target is empty, but shouldn't" ) if !$opt_to && !$opt_cc && !$opt_bcc;

# text and textfname are mutually exclusive, so are html and htmlfname
msgErr( "text body can only be provided one way, but both '--text' and '--textfname' are specified" ) if $opt_text && $opt_textfname;
msgErr( "HTML body can only be provided one way, but both '--html' and '--htmlfname' are specified" ) if $opt_html && $opt_htmlfname;

if( !TTP::errs()){
	doSend();
}

TTP::exit();

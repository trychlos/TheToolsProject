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
# @(-) --[no]debug             debug the SMTP transport phase [${debug}]
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
	debug => 'no'
};

my $opt_subject = $defaults->{subject};
my $opt_text = $defaults->{text};
my $opt_textfname = $defaults->{textfname};
my $opt_html = $defaults->{html};
my $opt_htmlfname = $defaults->{htmlfname};
my $opt_to = $defaults->{to};
my $opt_debug = undef;

# -------------------------------------------------------------------------------------------------
# send the email

sub doSend {
	msgOut( "sending an email to $opt_to..." );
	my @to = split( /,/, $opt_to );
	my $text = undef;
	$text = $opt_text if $opt_text;
	if( $opt_textfname ){
		my $fh = path( $opt_textfname );
		$text = $fh->slurp_utf8;
	}
	my $html = undef;
	$html = $opt_html if $opt_html;
	if( $opt_htmlfname ){
		my $fh = path( $opt_htmlfname );
		$html = $fh->slurp_utf8;
	}
	my $res = TTP::SMTP::send({
		subject => $opt_subject,
		text => $text,
		html => $shtml,
		to => \@to,
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
	"help!"				=> \$ep->{run}{help},
	"colored!"			=> \$ep->{run}{colored},
	"dummy!"			=> \$ep->{run}{dummy},
	"verbose!"			=> \$ep->{run}{verbose},
	"subject=s"			=> \$opt_subject,
	"text=s"			=> \$opt_text,
	"textfname=s"		=> \$opt_textfname,
	"html=s"			=> \$opt_html,
	"htmlfname=s"		=> \$opt_htmlfname,
	"to=s"				=> \$opt_to,
	"debug!"			=> \$opt_debug )){

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
msgVerbose( "found subject='$opt_subject'" );
msgVerbose( "found text='$opt_text'" );
msgVerbose( "found textfname='$opt_textfname'" );
msgVerbose( "found html='$opt_html'" );
msgVerbose( "found htmlfname='$opt_htmlfname'" );
msgVerbose( "found to='$opt_to'" );
msgVerbose( "found debug='".( defined $opt_debug ? ( $opt_debug ? 'true':'false' ) : '(undef)' )."'" );

# all data are mandatory, and we must provide some content, either text or html
msgErr( "subject is empty, but shouldn't" ) if !$opt_subject;
msgErr( "content is empty, but shouldn't" ) if !$opt_text && !$opt_textfname && !$opt_html && !$opt_htmlfname;
msgErr( "target is empty, but shouldn't" ) if !$opt_to;

# text and textfname are mutually exclusive, so are html and htmlfname
msgErr( "text body can only provided one way, but both '--text' and '--textfname' are specified" ) if $opt_text && $opt_textfname;
msgErr( "HTML body can only provided one way, but both '--html' and '--htmlfname' are specified" ) if $opt_html && $opt_htmlfname;

if( !TTP::errs()){
	doSend();
}

TTP::exit();

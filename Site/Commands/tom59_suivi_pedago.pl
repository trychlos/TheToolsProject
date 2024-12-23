# @(#) Build and (mail) send the suivi pedago for Tom59
#
# @(#) This verb display a summary of the executed commands found in 'command' environment variable,
# @(#) along with their exit code in 'rc' environment variable.
#
# @(-) --[no]help              print this message, and exit [${help}]
# @(-) --[no]colored           color the output depending of the message level [${colored}]
# @(-) --[no]dummy             dummy run (ignored here) [${dummy}]
# @(-) --[no]verbose           run verbosely [${verbose}]
# @(-) --service=<service>     the DBMS service name [${service}]
# @(-) --script=<script>       the path to the SQL script to be executed [${script}]
#
# @(@) This script is mostly written like a TTP verb but is not.
# @(@) This is an example of how to take advantage of TTP to write your own (rather pretty and efficient) scripts.
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

use Data::Dumper;
use Excel::Writer::XLSX;
use File::Basename;
use File::Spec;
use Getopt::Long;
use Path::Tiny;
use POSIX;

use utf8;

use TTP;
use TTP::Constants qw( :all );
use TTP::Extern;
use TTP::Message qw( :all );
use vars::global qw( $ep );

# TTP initialization
my $extern = TTP::Extern->new();

my $defaults = {
	help => 'no',
	colored => 'no',
	dummy => 'no',
	verbose => 'no',
	service => '',
	script => ''
};

my $opt_service = $defaults->{service};
my $opt_script = $defaults->{script};

#my $mail_to = 'cbonnier@inlingua-pro.com,fwanlin@inlingua-pro.com';
#my $mail_bcc = 'inlingua-adm@trychlos.org';
my $mail_to = 'inlingua-adm@trychlos.org,p.wieser@trychlos.org';
my $mail_bcc = 'pierre@wieser.fr';

my $columns = {
	Intras => [
		'Source',
		'ModuleID',
		'ModuleLabel',
		'FormuleID',
		'FormuleLabel',
		'ModuleDateFrom',
		'ModuleDateTo',
		'ModuleNbStagiaires',
		'ModuleDureeMinutes',
		'ModuleDureeHeures',
		'ModuleSoldeToPlann',
		'CentreID',
		'CentreLabel',
		'RefPedagoID',
		'RefPedagoLabel',
		'LangueID',
		'LangueLabel',
		'ConventionLabel',
		'CompanyID',
		'CompanyName',
		'ConventionDateFromMin',
		'ConventionDateToMax',
		'SeancesPremierCours',
		'SeancesDernierCours',
		'NotesPedagoDue',
		'NotesPedagoFound',
		'NotesPedagoManquantes',
		'SeancesPassees',
		'SeancesSignFormateurManquantes',
		'EvaluationPlanifiee',
		'EvaluationRenseignee',
		'ModuleStagiaireID',
		'ModuleStagiaireLabel',
		'PersonID',
		'PersonLabel',
		'PersonCivility',
		'PersonEmail',
		'StagiaireSignManquantes',
		'StagiaireAbsencesMinutes',
		'StagiaireAbsencesPercentMinutes',
		'StagiaireAbsencesCount',
		'StagiaireAbsencesPercentCount',
		'QuestionnaireDebut',
		'QuestionnaireFin',
		'ReprendreFormation'
	],
	Inters => [
		'Source',
		'CoursID',
		'CoursLabel',
		'FormuleID',
		'FormuleLabel',
		'CoursDateFrom',
		'CoursDateTo',
		'CoursNbStagiaires',
		'CoursDureeMinutes',
		'CoursDureeHeures',
		'CoursSoldeToPlann',
		'CentreID',
		'CentreLabel',
		'RefPedagoID',
		'RefPedagoLabel',
		'LangueID',
		'LangueLabel',		
		'ConventionLabel',
		'CompanyID',
		'CompanyName',
		'ConventionDateFromMin',
		'ConventionDateToMax',
		'SeancesPremierCours',
		'SeancesDernierCours',
		'NotesPedagoDue',
		'NotesPedagoFound',
		'NotesPedagoManquantes',
		'SeancesPassees',
		'SeanceSignFormateurManquantes',
		'EvaluationPlanifiee',
		'EvaluationRenseignee',
		'CoursStagiaireID',
		'CoursStagiaireLabel',
		'PersonID',
		'PersonLabel',
		'PersonCivility',
		'PersonEmail',
		'StagiaireSignManquantes',
		'StagiaireAbsencesMinutes',
		'StagiaireAbsencesPercentMinutes',
		'StagiaireAbsencesCount',
		'StagiaireAbsencesPercentCount',
		'QuestionnaireDebut',
		'QuestionnaireFin',
		'ReprendreFormation'
	]
};

my $sheets = {
	intras_solo => {
		name => 'Intras SOLO',
		header => 'Intras'
	},
	intras_others => {
		name => 'Intras Others',
		header => 'Intras'
	},
	inters => {
		name => 'Inters',
		header => 'Inters'
	}
};

# -------------------------------------------------------------------------------------------------
# Execute the provided script
# Split the 'Intras' result set (if found)
# Create a workbook with up to three sheets
# and sends it

sub doWork {
	# execute the sql script
	# which provides two datasets - but as they are executed as SINGLESET, we get them merged
	my $json = TTP::getTempFileName();
	my $columns = TTP::getTempFileName();
	my $command = "dbms.pl sql -service $opt_service -script $opt_script -nocolored -json $json -columns $columns";
	my $out = `$command`;
	my $rc = $?;
	print "$out";
	msgVerbose( "rc=$rc" );
	if( $rc == 0 ){
		# compute the output filename
		my $fbase = basename( $opt_script );
		$fbase =~ s/\.[^.]+$//;
		my $stamp = strftime( '%Y%m%d', localtime time );
		my $xlsx = File::Spec->catfile( TTP::logsCommands(), $fbase."_$stamp.xlsx" );
		msgVerbose( "creating $xlsx workbook" );
		my $workbook = Excel::Writer::XLSX->new( $xlsx );
		# split the data into the tree output part
		# simultaneously writing in the workbook
		my $input = TTP::jsonRead( $json );
		foreach my $row ( @{$input} ){
			if( $row->{Source} eq 'Intras' && $row->{FormuleID} == 1 ){
				writeInSheet( $workbook, 'intras_solo', $row );
			} elsif( $row->{Source} eq 'Intras' && $row->{FormuleID} != 1 ){
				writeInSheet( $workbook, 'intras_others', $row );
			} elsif( $row->{Source} eq 'Inters' ){
				writeInSheet( $workbook, 'inters', $row );
			} else {
				msgWarn( "unknwon source: '$row->{Source}'" );
			}
		}
		foreach my $sheet ( keys %{$sheets} ){
			msgVerbose(( $sheets->{$sheet}{name} ).": ".( $sheets->{$sheet}{count}-1 ));
		}
		#print Dumper( $sheets );
		$workbook->close();
		# send the workbook by email
		my $subject = $fbase;
		$subject =~ s/_/ /g;
		$stamp = strftime( '%d/%m/%Y', localtime time );
		$subject .= ' - '.$stamp;
		my $html = <<EOT;
<p>Bonjour,</p>
<p>Vous trouverez ci-joint le rapport de suivi pédagogique en date du $stamp.</p>
<p>Je vous en souhaite bonne réception.</p>
<p>Cordialement,</p>
<p><a href='mailto:inlingua-adm@trychos.org'>Tom59</a></p>
EOT
		my $htmlfname = TTP::getTempFileName();
		path( $htmlfname )->spew_utf8( $html );
		$command = "smtp.pl send -subject '$subject' -htmlfname $htmlfname -to $mail_to -bcc $mail_bcc -join $xlsx";
		msgVerbose( $command );
		my $out = `$command`;
		my $rc = $?;
		print "$out";
		msgVerbose( "rc=$rc" );
	}
}

sub writeInSheet {
	my ( $book, $name, $row ) = @_;
	if( !$sheets->{$name}{sheet} ){
		$sheets->{$name}{sheet} = $book->add_worksheet( $sheets->{$name}{name} );
		$sheets->{$name}{sheet}->write_row( 0, 0, $columns->{$sheets->{$name}{header}} );
		$sheets->{$name}{count} = 1;
	}
	my $array_ref = [];
	foreach my $col ( @{$columns->{$sheets->{$name}{header}}} ){
		push( @{$array_ref}, $row->{$col} || '' );
	}
	$sheets->{$name}{sheet}->write_row( $sheets->{$name}{count}++, 0, $array_ref );
}

# =================================================================================================
# MAIN
# =================================================================================================

if( !GetOptions(
	"help!"				=> \$ep->{run}{help},
	"colored!"			=> \$ep->{run}{colored},
	"dummy!"			=> \$ep->{run}{dummy},
	"verbose!"			=> \$ep->{run}{verbose},
	"service=s"			=> \$opt_service,
	"script=s"			=> \$opt_script	)){

		msgOut( "try '".$extern->command()." --help' to get full usage syntax" );
		TTP::exit( 1 );
}

#print Dumper( $ep->{run} );
if( $extern->help()){
	$extern->helpExtern( $defaults );
	TTP::exit();
}

msgVerbose( "found colored='".( $extern->colored() ? 'true':'false' )."'" );
msgVerbose( "found dummy='".( $extern->dummy() ? 'true':'false' )."'" );
msgVerbose( "found verbose='".( $extern->verbose() ? 'true':'false' )."'" );
msgVerbose( "found service='$opt_service'" );
msgVerbose( "found script='$opt_script'" );

if( !TTP::errs()){
	doWork();
}

TTP::exit();

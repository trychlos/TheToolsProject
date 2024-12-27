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
# @(-) --fnews=<fnews>         an optional filename which contains HTML news [${fnews}]
# @(-) --to=<to>               a comma-separated list of mail dests [${to}]
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
	script => '',
	fnews => '',
	to => ''
};

my $opt_service = $defaults->{service};
my $opt_script = $defaults->{script};
my $opt_fnews = $defaults->{fnews};
my $opt_to = $defaults->{to};

my $mail_bcc = 'inlingua-adm@trychlos.org';

my $columns = {
	Intras => [
		{
			name => 'Source',
			width => 9
		},
		{
			name => 'ModuleID',
			width => 10
		},
		{
			name => 'ModuleLabel',
			width => 66
		},
		{
			name => 'FormuleID',
			width => 11
		},
		{
			name => 'FormuleLabel',
			width => 14
		},
		{
			name => 'ModuleDateFrom',
			width => 16
		},
		{
			name => 'ModuleDateTo',
			width => 16
		},
		{
			name => 'ModuleNbStagiaires',
			width => 19
		},
		{
			name => 'ModuleDureeMinutes',
			width => 19
		},
		{
			name => 'ModuleDureeHeures',
			width => 19,
			format => {
				align => 'right',
				num_format => 'H:MM'
			}
		},
		{
			name => 'ModuleSoldeToPlann',
			width => 19
		},
		{
			name => 'CentreID',
			width => 10
		},
		{
			name => 'CentreLabel',
			width => 25
		},
		{
			name => 'RefPedagoID',
			width => 12
		},
		{
			name => 'RefPedagoLabel',
			width => 32
		},
		{
			name => 'LangueID',
			width => 10
		},
		{
			name => 'LangueLabel',
			width => 14
		},
		{
			name => 'ConventionLabel',
			width => 80
		},
		{
			name => 'CompanyID',
			width => 12
		},
		{
			name => 'CompanyName',
			width => 66
		},
		{
			name => 'ConventionDateFromMin',
			width => 19
		},
		{
			name => 'ConventionDateToMax',
			width => 19
		},
		{
			name => 'SeancesPremierCours',
			width => 19
		},
		{
			name => 'SeancesDernierCours',
			width => 19
		},
		{
			name => 'SeancesMiParcoursDate',
			width => 19
		},
		{
			name => 'SeancesMiParcoursPasse',
			width => 19
		},
		{
			name => 'NotesPedagoDue',
			width => 21
		},
		{
			name => 'NotesPedagoFound',
			width => 21
		},
		{
			name => 'NotesPedagoManquantes',
			width => 21
		},
		{
			name => 'SeancesPassees',
			width => 21
		},
		{
			name => 'SeancesSignFormateurManquantes',
			width => 28
		},
		{
			name => 'ModuleStagiaireID',
			width => 16
		},
		{
			name => 'ModuleStagiaireLabel',
			width => 80
		},
		{
			name => 'PersonID',
			width => 11
		},
		{
			name => 'PersonLabel',
			width => 40
		},
		{
			name => 'PersonCivility',
			width => 13
		},
		{
			name => 'PersonEmail',
			width => 40
		},
		{
			name => 'StagiaireSignManquantes',
			width => 25
		},
		{
			name => 'StagiaireAbsencesMinutes',
			width => 25
		},
		{
			name => 'StagiaireAbsencesPercentMinutes',
			width => 25
		},
		{
			name => 'StagiaireAbsencesCount',
			width => 25
		},
		{
			name => 'StagiaireAbsencesPercentCount',
			width => 25
		},
		{
			name => 'EvaluationPlanifiee',
			width => 19
		},
		{
			name => 'EvaluationRenseignee',
			width => 19
		},
		{
			name => 'RapportProgresValide',
			width => 19
		},
		{
			name => 'QuestionnaireDebut',
			width => 17
		},
		{
			name => 'QuestionnaireFin',
			width => 17
		},
		{
			name => 'ReprendreFormation',
			width => 17
		}
	],
	Inters => [
		{
			name => 'Source',
			width => 9
		},
		{
			name => 'CoursID',
			width => 10
		},
		{
			name => 'CoursLabel',
			width => 66
		},
		{
			name => 'FormuleID',
			width => 11
		},
		{
			name => 'FormuleLabel',
			width => 14
		},
		{
			name => 'CoursDateFrom',
			width => 16
		},
		{
			name => 'CoursDateTo',
			width => 16
		},
		{
			name => 'CoursNbStagiaires',
			width => 19
		},
		{
			name => 'CoursDureeMinutes',
			width => 19
		},
		{
			name => 'CoursDureeHeures',
			width => 19,
			format => {
				align => 'right',
				num_format => 'H:MM'
			}
		},
		{
			name => 'CoursSoldeToPlann',
			width => 19
		},
		{
			name => 'CentreID',
			width => 10
		},
		{
			name => 'CentreLabel',
			width => 25
		},
		{
			name => 'RefPedagoID',
			width => 12
		},
		{
			name => 'RefPedagoLabel',
			width => 32
		},
		{
			name => 'LangueID',
			width => 10
		},
		{
			name => 'LangueLabel',
			width => 14
		},
		{
			name => 'ConventionLabel',
			width => 80
		},
		{
			name => 'CompanyID',
			width => 12
		},
		{
			name => 'CompanyName',
			width => 66
		},
		{
			name => 'ConventionDateFromMin',
			width => 19
		},
		{
			name => 'ConventionDateToMax',
			width => 19
		},
		{
			name => 'SeancesPremierCours',
			width => 19
		},
		{
			name => 'SeancesDernierCours',
			width => 19
		},
		{
			name => 'SeancesMiParcoursDate',
			width => 19
		},
		{
			name => 'SeancesMiParcoursPasse',
			width => 19
		},
		{
			name => 'NotesPedagoDue',
			width => 21
		},
		{
			name => 'NotesPedagoFound',
			width => 21
		},
		{
			name => 'NotesPedagoManquantes',
			width => 21
		},
		{
			name => 'SeancesPassees',
			width => 21
		},
		{
			name => 'SeanceSignFormateurManquantes',
			width => 28
		},
		{
			name => 'CoursStagiaireID',
			width => 16
		},
		{
			name => 'CoursStagiaireLabel',
			width => 80
		},
		{
			name => 'PersonID',
			width => 11
		},
		{
			name => 'PersonLabel',
			width => 40
		},
		{
			name => 'PersonCivility',
			width => 13
		},
		{
			name => 'PersonEmail',
			width => 40
		},
		{
			name => 'StagiaireSignManquantes',
			width => 25
		},
		{
			name => 'StagiaireAbsencesMinutes',
			width => 25
		},
		{
			name => 'StagiaireAbsencesPercentMinutes',
			width => 25
		},
		{
			name => 'StagiaireAbsencesCount',
			width => 25
		},
		{
			name => 'StagiaireAbsencesPercentCount',
			width => 25
		},
		{
			name => 'EvaluationPlanifiee',
			width => 19
		},
		{
			name => 'EvaluationRenseignee',
			width => 19
		},
		{
			name => 'RapportProgresValide',
			width => 19
		},
		{
			name => 'QuestionnaireDebut',
			width => 17
		},
		{
			name => 'QuestionnaireFin',
			width => 17
		},
		{
			name => 'ReprendreFormation',
			width => 17
		}
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

my $formats = {};

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
		# define the formats
		$formats->{headers} = $workbook->add_format(
			size => 9.5,
			bold => true,
			bg_color => '#2a6099',
			color => 'white',
			valign => 'vcenter'
		);
		$formats->{rows} = $workbook->add_format(
			valign => 'vcenter'
		);
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
		# define and apply formats
		setupAtEnd( $workbook );
		$workbook->close();
		# send the workbook by email
		my $subject = $fbase;
		$subject =~ s/_/ /g;
		$subject .= " - ".strftime( '%d/%m/%Y', localtime time );
		my $html = <<EOT;
<p>Bonjour,</p>
<p>Vous trouverez ci-joint le rapport de suivi pédagogique en date du $stamp.</p>
EOT
		if( $opt_fnews ){
			my $news = path( $opt_fnews )->slurp_utf8;
			if( $news ){
				$html .= $news;
			}
		}
		$html .= <<EOT;
<p>Je vous en souhaite bonne réception, et une bonne journée.</p>
<p>Cordialement,</p>
<p><a href='mailto:inlingua-adm@trychos.org'>Tom59</a></p>
EOT
		my $htmlfname = TTP::getTempFileName();
		path( $htmlfname )->spew_utf8( $html );
		$command = "smtp.pl send -subject \"$subject\" -htmlfname $htmlfname -to \"$opt_to\" -bcc \"$mail_bcc\" -join $xlsx";
		msgVerbose( $command );
		my $out = `$command`;
		my $rc = $?;
		print "$out";
		msgVerbose( "rc=$rc" );
	}
}

sub writeInSheet {
	my ( $book, $name, $row ) = @_;
	# create the sheet and write the first line if not already done
	# set the columns width
	if( !$sheets->{$name}{sheet} ){
		msgVerbose( "defining '$name' sheet with ".scalar( @{$columns->{$sheets->{$name}{header}}} )." columns" );
		$sheets->{$name}{sheet} = $book->add_worksheet( $sheets->{$name}{name} );
		# set columns names and width on first row
		for( my $i=0 ; $i<scalar( @{$columns->{$sheets->{$name}{header}}} ) ; ++$i ){
			my $col = $columns->{$sheets->{$name}{header}}->[$i];
			$sheets->{$name}{sheet}->write_string( 0, $i, $col->{name}, $formats->{headers} );
			$sheets->{$name}{sheet}->set_column( $i, $i, $col->{width} );
			# defines a special format for this column
			if( $col->{format} ){
				$col->{colfmt} = $book->add_format( %{$col->{format}} );
			}
		}
		$sheets->{$name}{sheet}->set_row( 0, 22 );
		$sheets->{$name}{sheet}->freeze_panes( 1, 0 );
		$sheets->{$name}{count} = 1;
		# define a write handler to handle hours
		$sheets->{$name}{sheet}->add_write_handler( qr/^\d+(:\d+){1,2}$/, \&write_my_format );	# match hours as hhh:mm
	}
	# convert the row hash to an array ref in the right order
	my $array_ref = [];
	for( my $i=0 ; $i<scalar( @{$columns->{$sheets->{$name}{header}}} ) ; ++$i ){
		my $col = @{$columns->{$sheets->{$name}{header}}}[$i];
		push( @{$array_ref}, $row->{$col->{name}} || '' );
	}
	$sheets->{$name}{sheet}->write_row( $sheets->{$name}{count}, 0, $array_ref, $formats->{rows} );
	$sheets->{$name}{sheet}->set_row( $sheets->{$name}{count}, 18 );	# row height
	$sheets->{$name}{count} += 1;
	# check (once per sheet) that all fields of the row hash have a corresponding column name
	if( !$sheets->{$name}{checked} ){
		foreach my $field ( keys %{$row} ){
			my $found = false;
			for( my $i=0 ; $i<scalar( @{$columns->{$sheets->{$name}{header}}} ) ; ++$i ){
				my $col = $columns->{$sheets->{$name}{header}}->[$i];
				if( $col->{name} eq $field ){
					$found = true;
					last;
				}
			}
			if( !$found ){
				msgWarn( "$name: $field not found in columns" );
			}
		}
		$sheets->{$name}{checked} = true;
	}
}

# push a specific format for some cells of some sheets
sub write_my_format {
	my $worksheet = shift;
	my $name = $worksheet->get_name();
	foreach my $k ( keys %{$sheets} ){
		if( $sheets->{$k}{name} eq $name ){
			my $col = $columns->{$sheets->{$k}{header}}[$_[1]];
			my @args = @_;
			if( $col->{colfmt} ){
				$args[3] = $col->{colfmt};
				#print "write_my_format: match".EOL;
				return $worksheet->write_string( @args );
			} else {
				msgVerbose( "write_my_format: expreg is matched without specific format" );
			}
		}
	}
	return undef;
}

sub setupAtEnd {
	my ( $book ) = @_;
	foreach my $it ( keys %{$sheets} ){
		my $sheet = $sheets->{$it};
		# set autofilter
		my $rows_count = $sheet->{count};
		my $cols_count = scalar( @{$columns->{$sheet->{header}}} );
		$sheet->{sheet}->autofilter( 0, 0, $rows_count, $cols_count-1 );
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
	"service=s"			=> \$opt_service,
	"script=s"			=> \$opt_script,
	"fnews=s"			=> \$opt_fnews,
	"to=s"				=> \$opt_to	)){

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
msgVerbose( "found fnews='$opt_fnews'" );
msgVerbose( "found to='$opt_to'" );

if( !TTP::errs()){
	doWork();
}

TTP::exit();

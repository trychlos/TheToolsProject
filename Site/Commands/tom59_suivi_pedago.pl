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
# @(-) --finprev=<finprev>     an optional filename from where to get the previous result sets [${finprev}]
# @(-) --foutprev=<foutprev>   an optional filename which will record this execution result sets [${foutprev}]
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

use utf8;
use strict;
use warnings;

use Data::Dumper;
use Excel::Writer::XLSX;
use File::Basename;
use File::Spec;
use Getopt::Long;
use Path::Tiny;
use POSIX;

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
	to => '',
	finprev => 'C:\\INLINGUA\\DBs\\SuiviPedagoLast.json',
	foutprev => 'C:\\INLINGUA\\DBs\\SuiviPedagoLast.json'
};

my $opt_service = $defaults->{service};
my $opt_script = $defaults->{script};
my $opt_fnews = $defaults->{fnews};
my $opt_to = $defaults->{to};
my $opt_finprev = $defaults->{finprev};
my $opt_foutprev = $defaults->{foutprev};

my $mail_bcc = 'it-tom@inlingua-pro.com';

my $columns = {
	Intras => [
		{
			name => 'Source',
			hidden => true
		},
		{
			name => 'ModuleID',
			hidden => true
		},
		{
			name => 'ModuleLabel',
			width => 66
		},
		{
			name => 'FormuleID',
			hidden => true
		},
		{
			name => 'FormuleLabel',
			hidden => true
		},
		{
			name => 'ModuleDateFrom',
			computed => \&computeModuleDateFrom,
			width => 16
		},
		{
			name => 'ModuleDateTo',
			computed => \&computeModuleDateTo,
			width => 16
		},
		{
			name => 'ModuleNbStagiaires',
			hidden => true
		},
		{
			name => 'ModuleDureeMinutes',
			hidden => true
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
			hidden => true
		},
		{
			name => 'LangueID',
			hidden => true
		},
		{
			name => 'LangueLabel',
			hidden => true
		},
		{
			name => 'ConventionDateFromMin',
			hidden => true
		},
		{
			name => 'ConventionDateToMax',
			hidden => true
		},
		{
			name => 'NotesPedagoDue',
			hidden => true
		},
		{
			name => 'NotesPedagoFound',
			hidden => true
		},
		{
			name => 'NotesPedagoManquantes',
			width => 20
		},
		{
			name => 'SeancesSignFormateurManquantes',
			width => 25
		},
		{
			name => 'StagiaireSignManquantes',
			width => 25
		},
		{
			name => 'StagiaireAbsencesCount',
			width => 25
		},
		{
			name => 'StagiaireAbsencesPercentCount',
			hidden => true
		},
		{
			name => 'StagiaireAbsencesCountSincePrev',
			computed => \&computeStagiaireAbsencesCountSincePrev,
			width => 25
		},
		{
			name => 'SeancesPremierCours',
			computed => \&computeSeancesPremierCours,
			width => 20
		},
		{
			name => 'SeancesPremierCoursModifie',
			computed => \&computeSeancesPremierCoursModifie,
			width => 20
		},
		{
			name => 'SeancesDernierCours',
			computed => \&computeSeancesDernierCours,
			width => 20
		},
		{
			name => 'SeancesDernierCoursModifie',
			computed => \&computeSeancesDernierCoursModifie,
			width => 20
		},
		{
			name => 'SeancesMiParcoursDate',
			computed => \&computeSeancesMiParcoursDate,
			width => 20
		},
		{
			name => 'SeancesMiParcoursPassée',
			width => 20
		},
		{
			name => 'SeancesPassees',
			hidden => true
		},
		{
			name => 'EvaluationPlanifiee',
			computed => \&computeEvaluationPlanifiee,
			width => 20
		},
		{
			name => 'EvaluationRenseignee',
			computed => \&computeEvaluationRenseignee,
			width => 20
		},
		{
			name => 'RapportProgresValide',
			computed => \&computeRapportProgresValide,
			width => 20
		},
		{
			name => 'QuestionnaireDebut',
			computed => \&computeQuestionnaireDebut,
			width => 20
		},
		{
			name => 'QuestionnaireFin',
			computed => \&computeQuestionnaireFin,
			width => 20
		},
		{
			name => 'ReprendreFormation',
			width => 20
		},
		{
			name => 'LastNoteLabel',
			width => 20
		},
		{
			name => 'LastNoteContent',
			width => 40
		},
		{
			name => 'LastNoteDate',
			width => 20
		},
		{
			name => 'CentreID',
			hidden => true
		},
		{
			name => 'CentreLabel',
			width => 25
		},
		{
			name => 'RefPedagoID',
			hidden => true
		},
		{
			name => 'RefPedagoLabel',
			width => 30
		},
		{
			name => 'ConventionLabel',
			width => 80
		},
		{
			name => 'CompanyID',
			hidden => true
		},
		{
			name => 'CompanyName',
			width => 60
		},
		{
			name => 'ModuleStagiaireID',
			hidden => true
		},
		{
			name => 'ModuleStagiaireLabel',
			hidden => true
		},
		{
			name => 'PersonID',
			hidden => true
		},
		{
			name => 'PersonLabel',
			hidden => true
		},
		{
			name => 'PersonCivility',
			hidden => true
		},
		{
			name => 'PersonEmail',
			hidden => true
		}
	],
	Inters => [
		{
			name => 'Source',
			hidden => true
		},
		{
			name => 'CoursID',
			hidden => true
		},
		{
			name => 'CoursLabel',
			width => 66
		},
		{
			name => 'FormuleID',
			hidden => true
		},
		{
			name => 'FormuleLabel',
			hidden => true
		},
		{
			name => 'CoursDateFrom',
			computed => \&computeCoursDateFrom,
			width => 16
		},
		{
			name => 'CoursDateTo',
			computed => \&computeCoursDateTo,
			width => 16
		},
		{
			name => 'CoursNbStagiaires',
			hidden => true
		},
		{
			name => 'CoursDureeMinutes',
			hidden => true
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
			hidden => true
		},
		{
			name => 'LangueID',
			hidden => true
		},
		{
			name => 'LangueLabel',
			hidden => true
		},
		{
			name => 'ConventionDateFromMin',
			hidden => true
		},
		{
			name => 'ConventionDateToMax',
			hidden => true
		},
		{
			name => 'NotesPedagoDue',
			hidden => true
		},
		{
			name => 'NotesPedagoFound',
			hidden => true
		},
		{
			name => 'NotesPedagoManquantes',
			width => 20
		},
		{
			name => 'SeanceSignFormateurManquantes',
			width => 30
		},
		{
			name => 'StagiaireSignManquantes',
			width => 25
		},
		{
			name => 'StagiaireAbsencesCount',
			width => 25
		},
		{
			name => 'StagiaireAbsencesPercentCount',
			hidden => true
		},
		{
			name => 'StagiaireAbsencesCountSincePrev',
			computed => \&computeStagiaireAbsencesCountSincePrev,
			width => 25
		},
		{
			name => 'SeancesPremierCours',
			computed => \&computeSeancesPremierCours,
			width => 20
		},
		{
			name => 'SeancesPremierCoursModifie',
			computed => \&computeSeancesPremierCoursModifie,
			width => 20
		},
		{
			name => 'SeancesDernierCours',
			computed => \&computeSeancesDernierCours,
			width => 20
		},
		{
			name => 'SeancesDernierCoursModifie',
			computed => \&computeSeancesDernierCoursModifie,
			width => 20
		},
		{
			name => 'SeancesMiParcoursDate',
			computed => \&computeSeancesMiParcoursDate,
			width => 20
		},
		{
			name => 'SeancesMiParcoursPassée',
			width => 20
		},
		{
			name => 'EvaluationPlanifiee',
			computed => \&computeEvaluationPlanifiee,
			width => 20
		},
		{
			name => 'EvaluationRenseignee',
			computed => \&computeEvaluationRenseignee,
			width => 20
		},
		{
			name => 'RapportProgresValide',
			computed => \&computeRapportProgresValide,
			width => 20
		},
		{
			name => 'QuestionnaireDebut',
			computed => \&computeQuestionnaireDebut,
			width => 20
		},
		{
			name => 'QuestionnaireFin',
			computed => \&computeQuestionnaireFin,
			width => 20
		},
		{
			name => 'ReprendreFormation',
			width => 20
		},
		{
			name => 'LastNoteLabel',
			width => 20
		},
		{
			name => 'LastNoteContent',
			width => 40
		},
		{
			name => 'LastNoteDate',
			width => 20
		},
		{
			name => 'CentreID',
			hidden => true
		},
		{
			name => 'CentreLabel',
			width => 20
		},
		{
			name => 'RefPedagoID',
			hidden => true
		},
		{
			name => 'RefPedagoLabel',
			width => 30
		},
		{
			name => 'ConventionLabel',
			width => 80
		},
		{
			name => 'CompanyID',
			hidden => true
		},
		{
			name => 'CompanyName',
			width => 66
		},
		{
			name => 'SeancesPassees',
			hidden => true
		},
		{
			name => 'CoursStagiaireID',
			hidden => true
		},
		{
			name => 'CoursStagiaireLabel',
			hidden => true
		},
		{
			name => 'PersonID',
			hidden => true
		},
		{
			name => 'PersonLabel',
			hidden => true
		},
		{
			name => 'PersonCivility',
			hidden => true
		},
		{
			name => 'PersonEmail',
			hidden => true
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
# the computed columns
# each function receives the current row and the previous one
# and must return the value to be displayed

sub computeDateOnly {
	my ( $str ) = @_;
	return $str ? substr( $str, 0, 10 ) : '';
}

sub computeCoursDateFrom {
	my ( $row, $prev ) = @_;
	return computeDateOnly( $row->{CoursDateFrom} );
}

sub computeCoursDateTo {
	my ( $row, $prev ) = @_;
	return computeDateOnly( $row->{CoursDateTo} );
}

sub computeEvaluationPlanifiee {
	my ( $row, $prev ) = @_;
	return computeDateOnly( $row->{EvaluationPlanifiee} );
}

sub computeEvaluationRenseignee {
	my ( $row, $prev ) = @_;
	return computeDateOnly( $row->{EvaluationRenseignee} );
}

sub computeModuleDateFrom {
	my ( $row, $prev ) = @_;
	return computeDateOnly( $row->{ModuleDateFrom} );
}

sub computeModuleDateTo {
	my ( $row, $prev ) = @_;
	return computeDateOnly( $row->{ModuleDateTo} );
}

sub computeQuestionnaireDebut {
	my ( $row, $prev ) = @_;
	return computeDateOnly( $row->{QuestionnaireDebut} );
}

sub computeQuestionnaireFin {
	my ( $row, $prev ) = @_;
	return computeDateOnly( $row->{QuestionnaireFin} );
}

sub computeRapportProgresValide {
	my ( $row, $prev ) = @_;
	return computeDateOnly( $row->{RapportProgresValide} );
}

sub computeSeancesDernierCours {
	my ( $row, $prev ) = @_;
	return computeDateOnly( $row->{SeancesDernierCours} );
}

sub computeSeancesDernierCoursModifie {
	my ( $row, $prev ) = @_;
	my $res = ( $row and $row->{SeancesDernierCours} and $prev and $prev->{SeancesDernierCours} ) ? ( $row->{SeancesDernierCours} eq $prev->{SeancesDernierCours} ? '' : 'Modifie' ) : '';
	return $res;
}

sub computeSeancesMiParcoursDate {
	my ( $row, $prev ) = @_;
	return computeDateOnly( $row->{SeancesMiParcoursDate} );
}

sub computeSeancesPremierCours {
	my ( $row, $prev ) = @_;
	return computeDateOnly( $row->{SeancesPremierCours} );
}

sub computeSeancesPremierCoursModifie {
	my ( $row, $prev ) = @_;
	my $res = ( $row and $row->{SeancesPremierCours} and $prev and $prev->{SeancesPremierCours} ) ? ( $row->{SeancesPremierCours} eq $prev->{SeancesPremierCours} ? '' : 'Modifie' ) : '';
	return $res;
}

sub computeStagiaireAbsencesCountSincePrev {
	my ( $row, $prev ) = @_;
	my $res = ( $row and $row->{StagiaireAbsencesCount} and $prev and $prev->{StagiaireAbsencesCount} ) ? ( $row->{StagiaireAbsencesCount} == $prev->{StagiaireAbsencesCount} ? '' : $row->{StagiaireAbsencesCount} - $prev->{StagiaireAbsencesCount} ) : '';
}

# -------------------------------------------------------------------------------------------------
# Execute the provided SQL query script
# Split the 'Intras' result set (if found)
# Create a workbook with up to three sheets
# and sends it

sub doWork {
	# execute the sql script
	# which provides two datasets - but as they are executed as SINGLESET, we get them merged in a single array
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
		# split the data into the three output parts
		# simultaneously writing in the workbook
		my $input = TTP::jsonRead( $json );
		my @sorted = sort sortFn @{$input};
		# read the previous result set which has been written already sorted
		my $previous = previousResultSet();
		foreach my $row ( @sorted ){
			my $key = rowKey( $row );
			if( $row->{Source} eq 'Intras' && $row->{FormuleID} == 1 ){
				writeInSheet( $workbook, 'intras_solo', $row, $previous->{$key} );
			} elsif( $row->{Source} eq 'Intras' && $row->{FormuleID} != 1 ){
				writeInSheet( $workbook, 'intras_others', $row, $previous->{$key} );
			} elsif( $row->{Source} eq 'Inters' ){
				writeInSheet( $workbook, 'inters', $row, $previous->{$key} );
			} else {
				msgWarn( "unknwon source: '$row->{Source}'" );
			}
		}
		foreach my $sheet ( keys %{$sheets} ){
			msgVerbose(( $sheets->{$sheet}{name} ).": ".( $sheets->{$sheet}{count}-1 ));
		}
		# write the current result sets to be used in next execution comparisons
		prepareNext( \@sorted );
		#print Dumper( $sheets );
		# define and apply formats
		setupAtEnd( $workbook );
		$workbook->close();
		# send the workbook by email
		$stamp = strftime( '%d/%m/%Y', localtime time );
		my $subject = $fbase;
		$subject =~ s/_/ /g;
		$subject .= " - ".$stamp;
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
<p><a href='mailto:Tom &lt;it-tom\@inlingua-pro.com&gt;'>Tom</a></p>
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

# -------------------------------------------------------------------------------------------------
# write the current result sets into prev file to prepare the next execution

sub prepareNext {
	my ( $results ) = @_;
	truncate( $opt_foutprev, 0 );
	TTP::jsonOutput( $results, $opt_foutprev );
	msgVerbose( "current result sets successfully written in $opt_foutprev" );
}

# -------------------------------------------------------------------------------------------------
# read the previous result set
# returning a hash

sub previousResultSet {
	my $read = TTP::jsonRead( $opt_finprev, { ignoreIfNotExist => true });
	my $prev = {};
	my $count = 0;
	foreach my $it ( @{$read} ){
		my $k = rowKey( $it );
		$prev->{$k} = $it;
		$count += 1;
	}
	msgVerbose( "$opt_finprev successfully read, $count records were found" );
	return $prev;
}

# -------------------------------------------------------------------------------------------------
# compute a unique key for a row

sub rowKey {
	my ( $row ) = @_;
	my $k;
	if( $row->{Source} eq 'Intras' ){
		$k = sprintf( '%010s%010s', $row->{ModuleID}, $row->{ModuleStagiaireID} );
	} else {
		$k = sprintf( '%010s%010s', $row->{CoursID}, $row->{CoursStagiaireID} );
	}
	return $k;
}

# -------------------------------------------------------------------------------------------------
# sort the result set
# Modules Intras: ModuleDateFrom / ModuleID / ModuleStagiaireID
# Cours Inters: CoursDateFrom / CoursID / CoursStagiaireID

sub sortFn {
	if( $a->{Source} ne $b->{Source} ){
		return $a->{Source} cmp $b->{Source};
	}
	if( $a->{Source} eq 'Intras' ){
		my $key_a = sprintf( '%s%s', $a->{ModuleDateFrom} =~ s/[^0-9]//gr, rowKey( $a ));
		my $key_b = sprintf( '%s%s', $b->{ModuleDateFrom} =~ s/[^0-9]//gr, rowKey( $b ));
		return $key_a cmp $key_b;
	}
	my $key_a = sprintf( '%s%s', $a->{CoursDateFrom} =~ s/[^0-9]//gr, rowKey( $a ));
	my $key_b = sprintf( '%s%s', $b->{CoursDateFrom} =~s/[^0-9]//gr, rowKey( $b ));
	return $key_a cmp $key_b;
}

# -------------------------------------------------------------------------------------------------

sub writeInSheet {
	my ( $book, $name, $row, $prev ) = @_;
	# create the sheet and write the first line if not already done
	# set the columns width
	if( !$sheets->{$name}{sheet} ){
		msgVerbose( "defining '$name' sheet with ".scalar( @{$columns->{$sheets->{$name}{header}}} )." columns" );
		$sheets->{$name}{sheet} = $book->add_worksheet( $sheets->{$name}{name} );
		# set columns names and width on first row
		for( my $i=0 ; $i<scalar( @{$columns->{$sheets->{$name}{header}}} ) ; ++$i ){
			my $col = $columns->{$sheets->{$name}{header}}->[$i];
			$sheets->{$name}{sheet}->write_string( 0, $i, $col->{name}, $formats->{headers} );
			my $hidden = false;
			$hidden = $col->{hidden} if exists $col->{hidden};
			my $width = undef;
			$width = $col->{width} if exists $col->{width};
			$sheets->{$name}{sheet}->set_column( $i, $i, $width, undef, $hidden );
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
		if( $col->{computed} ){
			push( @{$array_ref}, $col->{computed}( $row, $prev ));
		} else {
			push( @{$array_ref}, $row->{$col->{name}} || '' );
		}
	}
	$sheets->{$name}{sheet}->write_row( $sheets->{$name}{count}, 0, $array_ref, $formats->{rows} );
	$sheets->{$name}{sheet}->set_row( $sheets->{$name}{count}, 18 );	# row height
	$sheets->{$name}{count} += 1;
	# check (once per sheet) that all fields of the row hash have a corresponding column name
	if( !$sheets->{$name}{fields_checked} ){
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
				msgWarn( "$name: query $field not found in displayed columns" );
			}
		}
		$sheets->{$name}{fields_checked} = true;
	}
	# check (once per sheet) that all columns (but the computed ones) have a source field
	if( !$sheets->{$name}{columns_checked} ){
		for( my $i=0 ; $i<scalar( @{$columns->{$sheets->{$name}{header}}} ) ; ++$i ){
			my $col = $columns->{$sheets->{$name}{header}}->[$i];
			if( $col->{computed} ){
				msgVerbose( "$name: $col->{name} is computed, so not checked for query field origin" );
			} else {
				if( !exists $row->{$col->{name}} ){
					print Dumper( $row );
					print Dumper( $col );
					msgWarn( "$name: column $col->{name} is not computed, but do not have any related query field" );
				}
			}
		}
		$sheets->{$name}{columns_checked} = true;
	}
}

# -------------------------------------------------------------------------------------------------
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

# -------------------------------------------------------------------------------------------------

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
	"to=s"				=> \$opt_to,
	"finprev=s"			=> \$opt_finprev,
	"foutprev=s"		=> \$opt_foutprev )){

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
msgVerbose( "found finprev='$opt_finprev'" );
msgVerbose( "found foutprev='$opt_foutprev'" );

if( !TTP::errs()){
	doWork();
}

TTP::exit();

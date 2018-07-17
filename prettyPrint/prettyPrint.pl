#!/usr/bin/perl

# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
#

use strict;
use lib '.';
use PrettyPrint;
use Date::Parse;
use DBI;
use File::Path;
use File::Basename;
use Getopt::Long;
use HTML::Template;
use Pod::Usage;

my $cregitVersion = "1.0-RC2";
my $man = 0;
my $help = 0;
my $verbose = 0;
my $templateFile = undef;
my $webRoot = "";
my $outputFile = undef;
my $dryrun = 0;
my $filter = "";
my $filter_lang = 0;

sub print_one {
	my $sourceFile = shift @ARGV;
	my $blameFile = shift @ARGV;
	my $lineFile =  shift @ARGV;
	my $sourceDB = shift @ARGV;
	my $authorsDB = shift @ARGV;
	
	Usage("Source file does not exist [$sourceFile]", 0) unless -f $sourceFile;
	Usage("Tokenized blame file does not exist [$blameFile]", 0) unless -f $blameFile;
	Usage("Tokenized line file does not exist [$lineFile]", 0) unless -f $lineFile;
	Usage("Database of tokenized repository does not exists [$sourceDB]", 0) unless -f $sourceDB;
	Usage("Database of authors does not exists [$authorsDB]", 0) unless -f $authorsDB;
	
	PrettyPrint::setup_dbi($sourceDB, $authorsDB);
	print_with_options($sourceFile, $blameFile, $lineFile);
	
	return 0;
}

sub print_many {
	my $repoDir = shift @ARGV;
	my $blameDir = shift @ARGV;
	my $lineDir = shift @ARGV;
	my $sourceDB = shift @ARGV;
	my $authorsDB = shift @ARGV;
	my $outputDir = shift @ARGV;
	my $filter = $filter;
	if ($filter_lang eq "c") {
		$filter = "\\.(h|c)\$";
	} elsif ($filter_lang eq "cpp") {
		$filter = "\\.(h(pp)?|cpp)\$";
	}
	
	Usage("Source directory does not exist [$repoDir]", 0) unless -d $repoDir;
	Usage("Tokenized blame file directory does not exist [$blameDir]", 0) unless -d $blameDir;
	Usage("Tokenized line file directory does not exist [$lineDir]", 0) unless -d $lineDir;
	Usage("Database of tokenized repository does not exists [$sourceDB]", 0) unless -f $sourceDB;
	Usage("Database of authors does not exists [$authorsDB]", 0) unless -f $authorsDB;
	Usage("Output root directory does not exists [$outputDir]", 0) unless -d $outputDir;
	
	PrettyPrint::setup_dbi($sourceDB, $authorsDB);
	
	open(my $FILES, "git -C '$repoDir' ls-files |") or die "unable to traverse git repo [$repoDir] $!";
	
	my $index = 0;
	my $count = 0;
	my $errorCount = 0;
	while (my $filePath = <$FILES>) {
		chomp $filePath;
		next if ($filter ne "" and $filePath !~ /$filter/);
		print(++$index . ": $filePath\n") if $verbose;
		
		my $originalFile = File::Spec->catfile($repoDir, $filePath);
		my $blameFile = File::Spec->catfile($blameDir, $filePath . ".blame");
		my $lineFile = File::Spec->catfile($lineDir, $filePath . ".token");
		my $outputFile = File::Spec->catfile($outputDir, $filePath . ".html");
		my ($fileName, $fileDir) = fileparse($outputFile);
		my $relative = File::Spec->abs2rel($outputDir, $fileDir);
		my $options = { "outputFile" => $outputFile };
		
		goto NOSOURCE if (! -f $originalFile);
		goto NOBLAME if (! -f $blameFile);
		goto NOLINE if (! -f $lineFile);
		
		print("$filePath\n") if !$verbose;
		if (!$dryrun) {
			File::Path::make_path($fileDir);
			my $errorCode = print_with_options($originalFile, $blameFile, $lineFile, $options);
			
			if ($errorCode != 0) {
				print "Error: $filePath\n";
				$errorCount++;
			}
		}
		$count++;
		
		next;
		NOSOURCE:	print("file does not exist in local repo [$originalFile]. Skipping\n") if $verbose; next;
		NOBLAME:	print("blame file [$blameFile] does not exist. Skipping\n") if $verbose; next;
		NOLINE:		print("line file [$lineFile] does not exist. skipping\n") if $verbose; next;
	}
	
	print "Processed: [$count]\n";
	print "Errors: [$errorCount]\n";
	return 0;
}

sub print_with_options {
	my $sourceFile = shift @_;
	my $blameFile = shift @_;
	my $lineFile =  shift @_;
	my $options = shift @_ // {};
	$options->{cregitVersion} //= $cregitVersion;
	$options->{templateFile} //= $templateFile;
	$options->{outputFile} //= $outputFile;
	$options->{webRoot} //= $webRoot;
	
	return PrettyPrint::print_file($sourceFile, $blameFile, $lineFile, $options);
}

sub Usage {
    my ($message, $verbose) = @_;
    print STDERR $message, "\n";
    pod2usage(-verbose=>$verbose) if $verbose > 0;
    exit(1);
}

GetOptions(
	"help" => \$help,
	"man" => \$man,
	"verbose" => \$verbose,
	"template=s" => \$templateFile,
	"webroot=s" => \$webRoot,
	"output=s" => \$outputFile,
	"dryrun" => \$dryrun,
	"filter=s" => \$filter,
	"filter-lang=s" => \$filter_lang,
) or die("Error in command line arguments\n");

exit pod2usage(-verbose=>1) if ($help);
exit pod2usage(-verbose=>2) if ($man);
exit pod2usage(-verbose=>1, -exit=>1) if (@ARGV[0] == undef);
exit pod2usage(-verbose=>1, -exit=>1) if (-f @ARGV[0] and scalar(@ARGV) != 5);
exit pod2usage(-verbose=>1, -exit=>1) if (-d @ARGV[0] and scalar(@ARGV) != 6);
exit print_one() if -f @ARGV[0];
exit print_many() if -d @ARGV[0];

__END__

=head1 NAME

prettyPrint-main.pl: create the "pretty" output of files in a git repository

=head1 SYNOPSIS

  prettyPrint.pl [options] <sourceFile> <blameFile> <tokenFile> <cregitRepoDB> <authorsDB>

  prettyPrint.pl [options] <repoDir> <blameDir> <tokenDir> <cregitRepoDB> <authorsDB> <outputDir>

     Options:
        --help             Brief help message
        --man              Full documentation
        --verbose          Enable verbose output
        --template         The template file to use.
                           Defaults to templates/page.tmpl
        --webroot          The web_root template parameter value.
                           Defaults to empty
    
     Options: (single)
        --output           The output file. Defaults to STDOUT.
    
     Options: (multi)
        --dryrun           print file names only.
        --filter           A regex file filter for processed files.
        --filter-lang      Filters input files by language
                               c      *.c|*.h
                               cpp    *.cpp|*.h|*.hpp

=cut

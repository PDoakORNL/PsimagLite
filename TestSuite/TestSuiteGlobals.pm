#! /usr/bin/perl

=pod
// BEGIN LICENSE BLOCK
/*
Copyright (c) 2008-2011, UT-Battelle, LLC
All rights reserved

[DMRG++, Version 2.0.0]
[by G.A., Oak Ridge National Laboratory]
[TestSuite by E.P., Puerto Rico and ORNL]

UT Battelle Open Source Software License 11242008
see file LICENSE for more details
*********************************************************
DISCLAIMER

THE SOFTWARE IS SUPPLIED BY THE COPYRIGHT HOLDERS AND
CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED
WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A
PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE
COPYRIGHT OWNER, CONTRIBUTORS, UNITED STATES GOVERNMENT,
OR THE UNITED STATES DEPARTMENT OF ENERGY BE LIABLE FOR
ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE
OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH
DAMAGE.

NEITHER THE UNITED STATES GOVERNMENT, NOR THE UNITED
STATES DEPARTMENT OF ENERGY, NOR THE COPYRIGHT OWNER, NOR
ANY OF THEIR EMPLOYEES, REPRESENTS THAT THE USE OF ANY
INFORMATION, DATA, APPARATUS, PRODUCT, OR PROCESS
DISCLOSED WOULD NOT INFRINGE PRIVATELY OWNED RIGHTS.

*********************************************************

// END LICENSE BLOCK

"Program testing can be a very effective way to show the presence of bugs, 
but it is hopelessly inadequate for showing their absence." -- Edsger Dijkstra
=cut

use strict;
# use Cwd 'abs_path';
package TestSuiteGlobals;
use Getopt::Long;
use Digest::MD5 qw(md5 md5_hex md5_base64);

my ($testDir, $srcDir,$inputsDir,$oraclesDir,$resultsDir,$specFile);

sub init
{
	$TestSuiteGlobals::testDir=`pwd`;
	chomp($TestSuiteGlobals::testDir);
	$TestSuiteGlobals::testDir.="/";
	$TestSuiteGlobals::srcDir=$TestSuiteGlobals::testDir."../src/";
	$TestSuiteGlobals::srcDir=$TestSuiteGlobals::testDir."../" unless (-r $TestSuiteGlobals::testDir."../src/");
	$TestSuiteGlobals::inputsDir = $TestSuiteGlobals::testDir."inputs/";
	$TestSuiteGlobals::oraclesDir = $TestSuiteGlobals::testDir."oracles/";	
	$TestSuiteGlobals::resultsDir = $TestSuiteGlobals::testDir."results/";
	system("mkdir \"$TestSuiteGlobals::resultsDir\"") unless (-d "$TestSuiteGlobals::resultsDir");
}

sub doMain
{

#	Get command line options
	my $all = 0;
	my $lastTest;
	die $! if(!GetOptions("n=i" => \$TestSuiteGlobals::testNum, "l=i" => \$lastTest, "all" => \$all));
	
	if (!$all && !defined($TestSuiteGlobals::testNum)) {
		$TestSuiteGlobals::testNum = selectTest();
	}

	$TestSuiteGlobals::testNum = 0 if (!defined($TestSuiteGlobals::testNum));

	if($TestSuiteGlobals::testNum < 0) {
		$TestSuiteGlobals::testNum = -$TestSuiteGlobals::testNum;
	}

	$lastTest = $TestSuiteGlobals::testNum if (!$all && !defined($lastTest));

	runAllTests($TestSuiteGlobals::testNum,$lastTest);
}


#Hook routine for the 'gprof' command
sub hookGprof
{
	my ($analysis, $arg) = @_;
	
	my $err = chdir($TestSuiteGlobals::srcDir);
	die "Changing directory to $TestSuiteGlobals::srcDir: $!" if(!$err);
	eval("system(\"gprof $arg\") == 0 || die;");
	if($@) {
		my $subr = (caller(0))[3];
		die "$subr: $@";
	}
	$err = chdir($TestSuiteGlobals::testDir);
	die "Changing directory to $TestSuiteGlobals::testDir: $!" if(!$err);
	
#	print "[$analysis]:Gprof command was successful.\n" if($verbose);
}

#Hook routine for the 'diff' command
sub hookDiff
{
	my ($analysis, $arg) = @_;

	#print STDERR "Diff args are *$arg*\n";
	eval("system(\"diff $arg\");");
	if($@) {
		my $subr = (caller(0))[3];
		die "$subr: $@";
	}
}

sub hookSmartDiff
{
	my ($analysis, $arg) = @_;

	my @temp = split/ /,$arg;
	die "$0: hookSmartDiff $arg\n" unless (scalar(@temp) == 4);
	die "$0: hookSmartDiff $arg\n" unless ($temp[2] eq ">");
	my ($file1,$file2,$ignore,$file3) = @temp;
	open(FILE1,"$file1") or die "$0: Cannot open $file1\n";
	open(FILE2,"$file2") or die "$0: Cannot open $file2\n";
	open(FOUT,">$file3") or die "$0: Cannot open > $file3\n";
	my $eps = 1e-6;
	my $maxDiff = 0;
	while (1) {
		my $line1 = <FILE1>;
		my $line2 = <FILE2>;
		last if (!$line1 || !$line2);
	
		my @temp1 = split/=/,$line1;
		(scalar(@temp1) == 2) or next;
		my @temp2 = split/=/,$line2;
		(scalar(@temp2) == 2) or next;
		if ($temp1[0] ne $temp1[0]) {
			print FOUT "$0: Mismatch $line1 $line2";
		}

		my $d = abs($temp1[1] - $temp2[1]);
		if ($d>$maxDiff) {
			$maxDiff = $d;
		}
	}

	if ($maxDiff > $eps) {
		print FOUT "$0: MaxDifference $maxDiff > $eps\n";
	}

	if (<FILE1> || <FILE2>) {
		print FOUT "$0: $file1 and $file2 have different number of lines\n";
	}

	close(FOUT);
	close(FILE1);
	close(FILE2);	
}

#Hook routine for the 'grep' command
sub hookGrep
{
	my ($analysis, $arg) = @_;
	
	eval("system(\"grep $arg\") == 0 || die;");
	if($@) {
		my $subr = (caller(0))[3];
		die "$subr: $@ argument=$arg";
	}
	
#	print "[$analysis]:Grep command was successful.\n" if($verbose);
}

#Returns the hash key
sub getSpecKey
{
	my $buffer = `cat ../TestSuite/inputs/$TestSuiteGlobals::specFile`;
	$buffer .= `cat ../src/Makefile`;
	$buffer .= `git rev-parse HEAD`;
	my $tmp = md5_hex($buffer);
	return substr($tmp,0,8);
}

#Displays available tests until user selects a valid one
sub selectTest
{
	my $available = getAvailableTests();

	print "Type the number of the test you want to run.\n";
	print "Available tests: $available\n";
	print "Default is 0 (press ENTER): ";
	my $testNum = <STDIN>;
	chomp($testNum);
	return $testNum;
}

#Extracts from the descriptions file all the available tests that can be run
sub getAvailableTests
{
	my $available = "";
	my $descriptionFile = $TestSuiteGlobals::inputsDir."descriptions.txt";
	
	open(FILE,$descriptionFile) || die "Opening $descriptionFile: $!";	
	while(<FILE>) {
		last if(/^\#TAGEND/);
		next if(/^\#TAGSTART/);
		if(/(^\d+)\)/) {
			$available .= "$1 ";	
		}
#		print if($verbose);	
	}
	close(FILE) || die "Closing $descriptionFile: $!";	

	my @testsArray = split(/ /,$available);	
	my $temp;

	return $available;
}

#Runs a single test
sub testSuite
{
	my ($testNum)=@_;
	#$tempNum -= 100 if($testNum >= 100);
	my $procFile = $TestSuiteGlobals::inputsDir."processing$testNum.txt";
	my $procLib = $TestSuiteGlobals::inputsDir."processingLibrary.txt";
	
	if(-r $procLib) {
		if(-r "$procFile") {
			print "*******START OF TEST $testNum*******\n";
			$TestSuiteGlobals::specFile = getSpecFile($procFile);
			my @analyses = extractAnalyses($procFile) ;
			(@analyses) ? (processing(@analyses, $procLib)) : (print "Test $testNum does not includes any processing analyses.\n");
			print "*******END OF TEST ".$testNum."*******\n";
		} else {
			die "Could not find $procFile: $!";
		}
	} else {
		die "$!";
	}
}

#Runs multiple tests by invoking the testSuite routine for each test
sub runAllTests
{
	my ($start,$lastTest) = @_;
	#All test numbers declared in @nonFunctionalTests will be skipped and not ran
	#test102 features wft+su2 which is currently broken
	#my @nonFunctionalTests = (); #41,42,60,102,104,105,106,107,108,109,110,111,124,125,141,142,160);
	my @testsList = split(/ /,getAvailableTests());
	
	if(defined($lastTest)) {
		die "<Error>: Invalid tests range [$start,$lastTest].\n" if($lastTest < $start);
		print "Preparing to run all tests from Test $start to Test $lastTest.\n";
	} else {
		$lastTest = $testsList[$#testsList];

		print "Preparing to run all tests starting from Test $start to $lastTest ".($#testsList)."\n";
	}
	
	for (my $i=0;$i<=$#testsList;$i++) {
		my $tn = $testsList[$i];
		next if ($tn eq "");
		next if ($tn<$start);

		my $inputFile =  $TestSuiteGlobals::inputsDir."input$tn.inp";
		next  if (nonFunctionalTest($inputFile));

		$TestSuiteGlobals::testNum = $tn;
		testSuite($TestSuiteGlobals::testNum);
		last if($tn == $lastTest);
	}
}

sub nonFunctionalTest
{
	my ($specFile)=@_;
	open(FILESPEC,$specFile) or return 1;
	$_=<FILESPEC>;
	close(FILESPEC);
	chomp;
	return 1 if (/DISABLED/);
	return 0;
}

#Reads all analyses described in the processing file for a specific test
sub extractAnalyses
{
	my ($procFile) = @_;
	my @analyses;

	open(FILE, "<$procFile") || die "Opening $procFile: $!";
	while(<FILE>) {
		chomp;
		last if($_ eq "");
		next if(/^#/);
		push(@analyses, $_);
	}
	close (FILE) || die "Closing $procFile: $!";
	
	return @analyses;
}

#Extracts the commands for each analysis of the current test, sends them to a key:value parser routine,
#and then the commands are sent to an interpreter routine for execution
sub processing
{
	my $lib = pop(@_);
	my (@analyses) = @_;
	my %procHash;
	my @commands;
	
	print "Starting processing phase...\n";
	
	foreach my $analysis(@analyses) {
		my @operations;
		open(LIB, "<$lib") || die "Opening $lib: $!";
		while(<LIB>) {
			if(/^\[$analysis\]/i) {
				while(<LIB>) {
					chomp;
					last if($_ eq "" || /(^\[)*(\])/);
					next if(/^#/);
					push @operations, $_;
				}
			}
		}
		close(LIB) || die "Closing $lib: $!";
		
		if(!@operations) {
			print "<Warning>: Missing descriptions for [$analysis] analysis in $lib.\n";
		} else {
			my @commands = keyValueParser(\@operations);
			if(!@commands) {
				print "<Warning>: No runnable commands for [$analysis] analysis in $lib.>\n";
			} else {
				$procHash{$analysis} = join(":", @commands);
			}
		}
	}
	
	die "No analysis was found for Test $TestSuiteGlobals::testNum.\n" if(!keys %procHash);
	
	#The following section of code resolves dependencies among the different analysis in the
	#processing file for the current test
	my %procCount;
	my %tmpHash = %procHash;
	my @dependencies;
	my $depFlag;
	my @depKeys;
	my $keyword = "CallOnce";	#Keyword that establishes dependencies in the processing library
	my $prevCount = 0;
	
	foreach my $analysis (keys %tmpHash) {
		$procCount{$analysis} = 0;
	}
	
	while($prevCount = keys %tmpHash) {
		foreach my $analysis( keys %tmpHash) {
			$depFlag = 0;
			@commands = split(/:/, $tmpHash{$analysis});
			if(@dependencies = grep{/$keyword/} @commands) {
				@depKeys = grep{s/$keyword|\s+//g} @dependencies;
				foreach my $a(@depKeys) {
					if(!defined($procCount{$a})) {
						die "Unresolved dependency for analysis [$analysis]: inactive analysis [$a]. Verify the processing file for Test $TestSuiteGlobals::testNum or processing library.\n";
					} elsif($procCount{$a} eq 0) {
						$depFlag = 1;
					}
				}

				if($depFlag) {
					next;
				} else {
					@commands = grep {!/$keyword/} @commands;
				}
			}
			
			die "No runable command in library for [$analysis] analysis.\n" if(!@commands);
			commandsInterpreter(@commands, $analysis);
			$procCount{$analysis}++;
			delete $tmpHash{$analysis};
		}

		die "Unresolved processing dependencies in $lib.\n" if($prevCount == keys %tmpHash);
	}
	
	print "Ending processing phase...\n";
}

#Resolves the variables in the commands for each analysis of the current test
sub keyValueParser
{
	my ($opsRef) = @_;
	my @tmpKV;
	my $keyword = "Let";	#Keyword that marks key:value pairs used in the parsing action
	my %tmpHash;
	my @commands;
	my %varHash;
	#Only variables found in @varArray can be used in the processing library for substitution purposes
	my $srcDir = $TestSuiteGlobals::srcDir;
	my $testNum = $TestSuiteGlobals::testNum;
	my $inputsDir = $TestSuiteGlobals::inputsDir;
	my $oraclesDir= $TestSuiteGlobals::oraclesDir;
	my $resultsDir = $TestSuiteGlobals::resultsDir;
	my @varArray = ("\$executable", "\$srcDir", "\$inputsDir", "\$resultsDir", "\$oraclesDir", "\$testNum");
	#Variables in @nonSubsArray will not be resolved during the parsing, instead
	#they are resolved prior to executing the command
	my @nonSubsArray = ("\$executable");

	foreach (@varArray) {
		my $tmp = "\\$_";
		if(grep {/$tmp/} @nonSubsArray) {
			$varHash{$_} = $_;
		} else {
			$varHash{$_} = eval($_);
		}
	}

	#print "RESULTSDIR=$resultsDir ORACLESDIR=$oraclesDir\n";
	
	if(@tmpKV = grep {/^$keyword/} @{$opsRef}) {
		@{$opsRef} = grep {!/^$keyword/} @{$opsRef};
		grep {s/(^$keyword\s+)//g} @tmpKV;
		foreach my $keyval (@tmpKV) {
			my @t = split(/ = /, $keyval);
			$tmpHash{$t[0]} = $t[1];
		}
	}	
	
	foreach my $comm (@{$opsRef}) {
		if(@tmpKV) {
			grep {s/(\$\w+)/$tmpHash{$1}/g} $comm;
			#grep {s/(\$\w+)(\s+)([^<>])/$varHash{$1}$3/g} $comm;
			grep {s/(\$\w+)/$varHash{$1}/g} $comm;
		}
		
		push @commands, $comm;
		#print STDERR "COMM $comm\n";
	}

	return @commands;
}

#Executes commands from the processing library by hooking the command to its routine
sub commandsInterpreter
{
	my $analysis = pop(@_);
	my (@commands) = @_;
	#Keywords in @metaLang are used to hook a command with its routine
	#Routines, in conjunction with meta language keywords, can be added to expand the runable commands in the processing library
	#The commands will be executed following the order below from left to right
	my @metaLang = ("Grep", "Execute", "Gprof", "CombineContinuedFraction","ComputeContinuedFraction",
	                "MettsAverage","TimeEvolution","Diff","Xmgrace","SmartDiff");
	my @arrangeCommands;
	
	foreach my $word(@metaLang) {
		if(my @tmpComm = grep {/^$word/} @commands) {
			@commands = grep {!/^$word/} @commands;
			foreach my $comm (@tmpComm) {
				push @arrangeCommands, $comm;
			}
		}
	}

	die "Unknown commands in analysis [$analysis]: @commands\n" if(@commands);

	foreach my $arg (@arrangeCommands) {
		my @tmpFunc = $arg =~ /^(\w+)/;
		$arg =~ s/^\s*(\w+)\s*//;
		eval("hook$tmpFunc[0](\$analysis,\$arg);");
		if($@) {
			eval("TestSuiteHooks::hook$tmpFunc[0](\$analysis,\$arg);");
		}
		if($@) {
			eval("TestSuiteGlobals::hook$tmpFunc[0](\$analysis,\$arg);");
		}
		if ($@) {
			eval("hook$tmpFunc[0](\$analysis,\$arg);");
		}
		if($@) {
			my $subr = (caller(0))[3];
			die "$subr: $@";
		}
	}
}

#Subroutine for the 'Execute' keyword
#'Execute' is used when the user defines custom routines 
sub hookExecute
{
	my ($analysis, $arg) = @_;
	
	$arg =~ s/(\()/$1"/g;
	$arg =~ s/(\s*)(,)(\s*)/"$2"/g;
	$arg =~ s/(\))/"$1/g;
	$arg = "TestSuiteHooks::$arg";

	#print "About to eval $arg;\n";
	eval("$arg;");
	if($@) {
		my $subr = (caller(0))[3];
		die "$subr: $@";
	}
	
#	print "[$analysis]:Execute command was successful.\n" if($verbose);
}

sub getLabel
{
	my ($file,$label,$dieIfNotFound)=@_;
	defined($dieIfNotFound) or $dieIfNotFound = 1;
	open(FILELABEL,$file) or die "$0: Could not open $file: $!\n";
	my $value;
	while(<FILELABEL>) {
		chomp;
		if (/$label(.*$)/) {
			$value=$1;
			last;
		}
	}
	close(FILELABEL);
	if ($dieIfNotFound and !defined($value)) {
		die "$0: Label $label not found in file $file\n";
	}

	return $value;
}

sub getSpecFile
{
	my ($file) = @_;
	my $value = getLabel($file,"CONFIG_MAKE=",0);
	return "Config.make" if (!defined($value));
	return $value;
}

sub hookComputeContinuedFraction
{
	my ($analysis, $arg) = @_;
	my @temp=split/ /,$arg;
	die "$0: Error in hookComputeContinuedFraction with arg=$arg\n" if (scalar(@temp)<2);

	my $label = getLabel($temp[0],"#ContinuedFraction=");
	$arg="";
	for (my $i=1;$i<scalar(@temp);$i++) {
		$arg .= " $label " if ($temp[$i]=~/\>/);
		$arg .= $temp[$i]." ";
	}

	print STDERR "Executing ./continuedFractionCollection $arg\n";
	system("./continuedFractionCollection $arg");
}

sub hookCombineContinuedFraction
{
	my ($analysis, $arg) = @_;
	print STDERR "Executing ./combineContinuedFraction $arg\n";
	system("./combineContinuedFraction $arg");
}

sub hookMettsAverage
{
	my ($analysis, $arg) = @_;
	my @temp=split/ /,$arg;
	die "$0: Error in hookMettsAverage with arg=$arg\n" if (scalar(@temp)<3);

	my $executable = $temp[0];
	$executable=~s/\\s/ /g;
	my $label = getLabel($temp[1],"BetaDividedByTwo=");
	$arg="";
	for (my $i=2;$i<scalar(@temp);$i++) {
		if ($temp[$i]=~/\>/ || $temp[$i]=~/\</) {
			$arg .= " $label ";
			$label="";
		}
		$arg .= $temp[$i]." ";
	}

	print STDERR "Executing $executable $arg\n";
	system("$executable $arg");
}

sub hookTimeEvolution
{
	my ($analysis, $arg) = @_;
	my $executable = "perl ../scripts/timeEvolution.pl ";
	print STDERR "Executing $executable $arg\n";
	system("$executable $arg");
}

sub hookXmgrace
{
	my ($analysis, $arg) = @_;
	my $executable = "xmgrace  ";
	print STDERR "Executing $executable $arg\n";
	system("$executable $arg");
}

1;

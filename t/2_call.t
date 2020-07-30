# $Id$
# t/02_call.t - check for accurate results from programs.

use strict;
use Test::More;
use Module::Build;

# Direct useless output to STDERR, to avoid confusing Test::Harness
#my $stdin = select STDERR;
# Restore STDOUT as default filehandle
#select $stdin;

my $has_samtools = `which samtools 2>/dev/null`;
my $has_edlib = `which edlib-aligner 2>/dev/null`;
my $has_nucmer = `which nucmer 2>/dev/null`;
my $has_delta_filter = `which delta-filter 2>/dev/null`;

plan tests => 17;

my $out;
# Test SVrefine: (2 tests--requires samtools)
my $script = 'blib/script/SVrefine';

SKIP: {
    ($has_samtools) or skip "Skipping SVrefine tests because no samtools in path", 4;

    system("perl -w -I blib/lib $script --delta t/refine.qdelta --regions t/regions.bed --outvcf t/refined.vcf --ref_fasta t/hs37d5_1start.fa --query_fasta t/utg7180000002239.fa --includeseqs --maxsize 1000000 > t/refine.out 2>&1");
    $out = `grep '#' t/refined.vcf | wc -l`;
    like $out, qr/^\s*13\s*$/, "$script headerlines";
    $out = `awk -F"\t" '\$2==1016054 {print \$8}' t/refined.vcf`;
    like $out, qr/REPTYPE=SIMPLEINS/, "$script vartype";
    system("perl -w -I blib/lib $script --delta t/refine.qdelta --regions t/regions.bed --outvcf t/refined.vcf --ref_fasta t/hs37d5_1start.fa --query_fasta t/utg7180000002239.fa --svregions t/refine.sv.bed --includeseqs > t/refine.out 2>&1");
    $out = `wc -l t/refine.sv.bed`;
    like $out, qr/^\s*4\s/, "$script svregions";
    $out = `awk -F"\t" '\$2==1074450 {print \$6}' t/refine.sv.bed`;
    like $out, qr/REPTYPE=CONTRAC/, "$script svbedregions";
}

SKIP: {
    # Test SVwiden:
    ($has_samtools && $has_nucmer && $has_delta_filter) or skip "Skipping SVwiden tests because one of samtools, nucmer or delta-filter in path", 2;
    $script = 'blib/script/SVwiden';
    
    mkdir "t/test";
    system("perl -w -I blib/lib $script --variants t/widen.vcf --prefix t/widened --ref t/hs37d5_1start.fa --workdir t/ > t/test2.out 2>&1");
    $out = `awk -F"\t" '\$2==821604 {print \$8}' t/widened.vcf`;
    like $out, qr/REPTYPE=DUP/, "$script vartype";
    $out = `awk -F"\t" '\$2==842057 {print \$8}' t/widened.vcf`;
    like $out, qr/REFWIDENED=1:842056-842090/, "$script widensmall";
    #system("rm t/widened.vcf");
    #system("rm t/test2.out");
}

SKIP: {
    # Test SVmerge:
    ($has_samtools && $has_edlib) or skip "Skipping SVmerge tests because one of samtools or edlib-aligner is missing from path", 2;
    $script = 'blib/script/SVmerge';
    
    mkdir "t/test";
    system("perl -w -I blib/lib $script --variants t/merge.vcf --prefix t/merged --ref t/hs37d5_1start.fa > t/test3.out 2>&1");
    $out = `awk -F"\t" '\$2==66442 {print \$8}' t/merged.clustered.vcf`;
    like $out, qr/NumExactMatchSVs=1/, "$script exactcluster";
    $out = `awk -F"\t" '\$2=="HG2_Ill_GATKHC_1" \&\& \$3=="HG3_Ill_GATKHC_2" {print \$6}' t/merged.distances`;
    ok($out == -34, "$script widensmall");
    system("perl -w -I blib/lib $script --fof t/merge.fof --prefix t/mergedfof --ref t/hs37d5_1start.fa > t/test3a.out 2>&1");
    $out = `awk -F"\t" '\$2==533244 {print \$8}' t/mergedfof.clustered.vcf`;
    like $out, qr/ExactMatchIDs=5/, "$script fofoptionworks";
    $out = `awk -F"\t" '\$4=="<INS>" {print}' t/mergedfof.clustered.vcf`;
    ok($out == "", "$script seqspecificoption");
    system("perl -w -I blib/lib $script --variants t/mergens.vcf --prefix t/mergednsvcf --ref t/hs37d5_1start.fa > t/test3b.out 2>&1");
    $out = `awk '\$3=="HG2_SnifflesTelo" {print \$8}' t/mergednsvcf.clustered.vcf`;
    like $out, qr/NumClusterSVs=1/, "$script telomereskip";
    #system("rm t/merged.vcf");
    #system("rm t/merged.distances");
    #system("rm t/test3.out");
    #system("rm t/mergedfof.vcf");
    #system("rm t/mergedfof.distances");
    #system("rm t/test3a.out");
}

SKIP: {
    # Test SVcomp:
    ($has_samtools && $has_edlib) or skip "Skipping SVcomp tests because one of samtools or edlib-aligner is missing from path", 1;
    $script = 'blib/script/SVcomp';
    
    mkdir "t/test";
	    system("perl -w -I blib/lib $script --first t/first.vcf --second t/second.vcf --prefix t/comp --ref t/hs37d5_1start.fa > t/test4.out 2>&1");
	    $out = `awk -F"\t" '\$2=="HG4_Ill_svaba_1" \&\& \$3=="HG3_Ill_GATKHC_1" {print \$6}' t/comp.distances`;
	    ok($out == -37, "$script compsize");
	    #system("rm t/comp.distances");
	    #system("rm t/test4.out");
	}

	SKIP: {
	    # Test SVbenchmark:
	    ($has_samtools && $has_edlib) or skip "Skipping SVbenchmark tests because one of samtools or edlib-aligner is missing from path", 4;
	    $script = 'blib/script/SVbenchmark';
	    
	    mkdir "t/test";
	    system("perl -w -I blib/lib $script --test t/benchmark.test.vcf --truth t/benchmark.truth.vcf --prefix t/benchmark --ref t/hs37d5_1start.fa > t/test5.out 2>&1");
	    $out = `grep 'Precision' t/benchmark.report | awk '{print \$NF}'`;
	    like $out, qr/20.00/, "$script precision";
	    system("perl -w -I blib/lib $script --test t/benchmark.test.vcf --truth t/benchmark.truth.vcf --minsize 10000 --prefix t/benchmark.minsize --ref t/hs37d5_1start.fa  > t/test5.out 2>&1");
	    $out = `grep 'Precision' t/benchmark.minsize.report | awk '{print \$NF}'`;
	    like $out, qr/0.00/, "$script precision";
	    system("perl -w -I blib/lib $script --test t/minreadtest.vcf --truth t/minreadtruth.vcf --prefix t/benchmark.minreadsupport --minreadsupport 10 --ref t/hs37d5_1start.fa --verbose > t/test6.out 2>&1");
	    $out = `grep 'Recall' t/benchmark.minreadsupport.report | awk '{print \$NF}'`;
	    like $out, qr/36\.36/, "$script minreadsupport recall";
	    system("perl -w -I blib/lib $script --test t/minreadtest.vcf --truth t/minreadtruth.vcf --prefix t/benchmark.minreadfrac --minreadfrac 0.5 --ref t/hs37d5_1start.fa --verbose > t/test7.out 2>&1");
	    $out = `grep 'F1' t/benchmark.minreadfrac.report | awk '{print \$NF}'`;
	    like $out, qr/0\.705/, "$script minreadfrac recall";
	    #system("rm t/benchmark.distances");
	    #system("rm t/test5.out");
	}

	SKIP: {
	    # Test svanalyzer launch script, using SVcomp:
	    ($has_samtools && $has_edlib) or skip "Skipping svanalyzer tests because one of samtools or edlib-aligner is missing from path", 1;
	    $script = 'blib/script/svanalyzer';
	    
	    mkdir "t/test";
	    system("PATH=\$PATH:blib/script PERL5LIB=\$PERL5LIB:blib/lib $script comp --first t/first.vcf --second t/second.vcf --prefix t/comp --ref t/hs37d5_1start.fa > t/test6.out 2>&1");
    $out = `awk -F"\t" '\$2=="HG4_Ill_svaba_1" \&\& \$3=="HG3_Ill_GATKHC_1" {print \$6}' t/comp.distances`;
    ok($out == -37, "$script compsize");
    #system("rm t/comp.distances");
    #system("rm t/test6.out");
}

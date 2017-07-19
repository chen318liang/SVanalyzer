#!/usr/bin/perl -w
# $Id:$

use strict;
use warnings;
use Getopt::Long;
use Pod::Usage;
use GTB::File qw(Open);
use GTB::FASTA;
use NISC::Sequencing::Date;

use lib qw( /home/nhansen/projects/SVanalyzer/github/SVanalyzer/lib );
use NHGRI::MUMmer::AlignSet;
our %Opt;

=head1 NAME

SVwiden.pl - Read a VCF file and use MUMmer to determine widened coordinates for structural variants add custom tags to the VCF record.

=head1 SYNOPSIS

  SVwiden.pl --vcf <path to input VCF file> --ref_fasta <path to reference multi-FASTA file> --outvcf <path to output VCF file>

For complete documentation, run C<SVwiden.pl -man>

=cut

#------------
# Begin MAIN 
#------------

process_commandline();

my $ref_fasta = $Opt{ref_fasta}; # will use values from delta file if not supplied as arguments

my $invcf = $Opt{invcf};
my $invcf_fh = Open($invcf, "w");

my $outvcf = $Opt{outvcf};
my $outvcf_fh = Open($outvcf, "w");

write_header($invcf_fh, $outvcf_fh) if (!$Opt{noheader});

my $ref_db = GTB::FASTA->new($ref_fasta);

while (<$invcf_fh>) {
    next if (/^#/);

    my $vcf_line = $_;
    my ($chr, $pos, $end, $id, $ref, $alt) = parse_vcf_line($vcf_line);

    process_region($chrom, $ra_regions, $delta_obj, $nocovregions_fh, $ref_db, $query_db, $ra_variant_lines, $ra_ref_cov); # populates $ra_variant_lines, $ra_ref_cov
    write_variants_to_vcf($outvcf_fh, $refregions_fh, $ra_variant_lines, $ra_ref_cov);
}

close $outvcf_fh;

#------------
# End MAIN
#------------

sub process_commandline {
    # Set defaults here
    %Opt = ( minbuffer => 1000 );
    GetOptions(\%Opt, qw( vcf=s ref_fasta=s outvcf=s minbuffer=i verbose noheader manual help+ version)) || pod2usage(0);
    if ($Opt{manual})  { pod2usage(verbose => 2); }
    if ($Opt{help})    { pod2usage(verbose => $Opt{help}-1); }
    if ($Opt{version}) { die "SVwiden.pl, ", q$Revision:$, "\n"; }

    if (!($Opt{vcf})) {
        print STDERR "Must specify a VCF file path of variants to widen!\n"; 
        pod2usage(0);
    }

    if (!($Opt{outvcf})) {
        print STDERR "Must specify a VCF file path to output confirmed variants!\n"; 
        pod2usage(0);
    }

}

sub parse_vcf_line {
    my $vcf_line = shift;

    if ($vcf_line =~ /^(\S+)\t(\d+)\t(\S+)\t(\S+)\t(\S+)\t(\S+)\t(\S+)\t(\S+)/) {
        my ($chr, $start, $id, $ref, $alt, $info) = ($1, $2, $3, $4, $5, $8);
        $ref = uc($ref);
        $alt = uc($alt);

        my $end; # if we have sequence, end will be determined as last base of REF, otherwise, from END=
        if (($ref =~ /^([ATGC]+)$/) && ($alt =~ /^([ATGC]+)$/)) {
            $end = $start + length($ref) - 1;
        }
        else { # check for END= INFO tag
            if ($info =~ /END=\s*(\d+)/) {
                $end = $1;
            }
            else {
                die "Variants without END in INFO field must have sequence alleles in REF and ALT fields!\n";
            }
        }

        if (!$Opt{'ignore_length'} && ($ref =~ /^([ATGC]+)$/) && ($end - $start + 1 != length($ref))) {
            die "Length of reference allele does not match provided POS, END!  Use --ignore_length option to ignore this discrepancy.\n";
        }

        return ($chr, $start, $end, $id, $ref, $alt);
    }
    else {
        die "Unexpected VCF line:\n$vcf_line";
    }
}

sub write_header {
    my $fh = shift;

    print $fh "##fileformat=VCFv4.3\n";
    my $date_obj = NISC::Sequencing::Date->new(-plain_language => 'today');
    my $year = $date_obj->year();
    my $month = $date_obj->month();
    $month =~ s/^(\d)$/0$1/;
    my $day = $date_obj->day();
    $day =~ s/^(\d)$/0$1/;
    print $fh "##fileDate=$year$month$day\n";
    print $fh "##source=SVwiden.pl\n";
    print $fh "##reference=$Opt{refname}\n" if ($Opt{refname});
    print $fh "##INFO=<ID=END,Number=1,Type=Integer,Description=\"End coordinate of SV\">\n";
    print $fh "##INFO=<ID=SVTYPE,Number=1,Type=String,Description=\"Type of SV:DEL=Deletion, INS=Insertion, INV=Inversion\">\n";
    print $fh "##INFO=<ID=REPTYPE,Number=1,Type=String,Description=\"Type of SV, with designation of uniqueness of new or deleted sequence:SIMPLEDEL=Deletion of at least some unique sequence, SIMPLEINS=Insertion of at least some unique sequence, CONTRAC=Contraction, or deletion of sequence entirely similar to remaining sequence, DUP=Duplication, or insertion of sequence entirely similar to pre-existing sequence, INV=Inversion, SUBSINS=Insertion of new sequence with alteration of some pre-existing sequence, SUBSDEL=Deletion of sequence with alteration of some remaining sequence\">\n";
    print $fh "##INFO=<ID=SVLEN,Number=1,Type=Integer,Description=\"Difference in length between ALT and REF alleles (negative for deletions from reference, positive for insertions to reference)\">\n";
    print $fh "##INFO=<ID=BREAKSIMLENGTH,Number=1,Type=Integer,Description=\"Length of alignable similarity at event breakpoints as determined by the aligner\">\n";
    print $fh "##INFO=<ID=REFWIDENED,Number=1,Type=String,Description=\"Widened boundaries of the event in the reference allele\">\n";
    print $fh "##INFO=<ID=ALTWIDENED,Number=1,Type=String,Description=\"Widened boundaries of the event in the alternate allele\">\n";
    print $fh "##INFO=<ID=ALTPOS,Number=1,Type=String,Description=\"Position (CHROM:POS-END) of the event in the sample assembly\">\n";
    print $fh "##FORMAT=<ID=GT,Number=1,Type=String,Description=\"Genotype\">\n";
    print $fh "##FORMAT=<ID=CONTIG,Number=1,Type=String,Description=\"Supporting contigs, in same order as alleles reported in genotype\">\n";
    print $fh "##FORMAT=<ID=GTMATCH,Number=1,Type=Character,Description=\"Genotype match type: E=Exact match, H=Position boundary match, L=Inexact match\">\n";
    print $fh "#CHROM\tPOS\tID\tREF\tALT\tQUAL\tFILTER\tINFO\tFORMAT\tSAMPLE\n";
}

sub process_variant {
    my $chrom = shift;
    my $ra_regions = shift;
    my $delta_obj = shift;
    my $outnc_fh = shift;
    my $ref_db = shift;
    my $query_db = shift;
    my $ra_vcf_lines = shift;
    my $ra_ref_coverage = shift;

    # examine regions for broken alignments:

    my $rh_ref_entrypairs = $delta_obj->{refentrypairs}; # store entry pairs by ref entry for quick retrieval
    my $rh_query_entrypairs = $delta_obj->{queryentrypairs}; # store entry pairs by query entry for quick retrieval

    my $ra_rentry_pairs = $rh_ref_entrypairs->{$chrom}; # everything aligning to this chromosome

    foreach my $ra_region (@{$ra_regions}) {
        my ($start, $end) = @{$ra_region};

        if (!check_region($ref_db, $chrom, $start, $end)) {
            print STDERR "SKIPPING REGION $chrom\t$start\t$end because it is too close to chromosome end!\n" if ($Opt{verbose});
            next;
        }

        # check small regions to the left and right of region of interest for aligning contigs:
        my $refleftstart = $start - $Opt{buffer};
        my $refleftend = $start - $Opt{buffer} + $Opt{bufseg} - 1;
        my $refrightstart = $end + $Opt{buffer} - $Opt{bufseg} + 1;
        my $refrightend = $end + $Opt{buffer};

        # find entries with at least one align spanning left and right contig align, with same comp value (can be a single align, or more than one)

        print STDERR "PROCESSING REGION $chrom\t$start\t$end\n" if ($Opt{verbose});
        my @valid_entry_pairs = find_valid_entry_pairs($ra_rentry_pairs, $refleftstart, $refleftend, $refrightstart, $refrightend);

        if (!@valid_entry_pairs) { # no consistent alignments across region
            print $outnc_fh "$chrom\t$start\t$end\n";
            next;
        }
        
        my @aligned_contigs = map { $_->{query_entry} } @valid_entry_pairs;
        my $contig_string = join ':', @aligned_contigs;
        my $no_entry_pairs = @valid_entry_pairs;
        print STDERR "VALID PAIRS $chrom\t$start\t$end $no_entry_pairs aligning contigs: $contig_string\n" if ($Opt{verbose});

        my @refaligns = ();
        foreach my $rh_rentry_pair (@valid_entry_pairs) { # for each contig aligned across region
            my $contig = $rh_rentry_pair->{query_entry};
            my $ra_qentry_pairs = $rh_query_entrypairs->{$contig}; # retrieve all alignments for this contig, i.e., "contig_aligns"
            my @contig_aligns = ();
            my $comp = $rh_rentry_pair->{comp}; # determines whether to sort contig matches in decreasing contig coordinate order
            foreach my $rh_entrypair (@{$ra_qentry_pairs}) {
                push @contig_aligns, @{$rh_entrypair->{aligns}};
            }
            my @sorted_contigaligns = ($comp) ? 
                      sort {($b->{query_start} <=> $a->{query_start}) || ($b->{query_end} <=> $a->{query_end})} @contig_aligns : 
                      sort {($a->{query_start} <=> $b->{query_start}) || ($a->{query_end} <=> $b->{query_end})} @contig_aligns;

            # pull contiguous set of contig alignments in region aligned to reference region:
            my @region_aligns = pull_region_contig_aligns(\@sorted_contigaligns, $chrom, $refleftend, $refrightstart);

            #my %contigrefentries = map { $_->{ref_entry} => 1 } @region_aligns;
            #my $refstring = join ':', keys %contigrefentries;
            #print STDERR "CONTIG $contig matches to ref entries $refstring\n" if ($Opt{verbose});

            # is there only one alignment to $chrom and does it span the region of interest?  If so, store reference coverage for this contig:
            my @ref_aligns = grep {$_->{ref_entry} eq $chrom} @region_aligns;

            my $nonref_found = 0;
            foreach my $ref_align (@ref_aligns) {
                if ($ref_align->{ref_start} < $refleftstart && $ref_align->{ref_end} > $refrightend) {
                    push @{$ra_ref_coverage}, [$chrom, $ref_align->{ref_start}, $ref_align->{ref_end}, $ref_align->{query_entry}, $ref_align->{query_start}, $ref_align->{query_end}];
                }
                else {
                    $nonref_found = 1;
                }
            }
            next if (!$nonref_found);

            if (@region_aligns > 1) { # potential SV--print out alignments if verbose option
                foreach my $rh_align (@region_aligns) {
                    my $ref_entry = $rh_align->{ref_entry};
                    my $query_entry = $rh_align->{query_entry};
                    my $ref_start = $rh_align->{ref_start};
                    my $ref_end = $rh_align->{ref_end};
                    my $query_start = $rh_align->{query_start};
                    my $query_end = $rh_align->{query_end};
    
                    print STDERR "ALIGN\t$chrom\t$start\t$end\t$ref_entry\t$ref_start\t$ref_end\t$query_entry\t$query_start\t$query_end\n" if ($Opt{verbose});
                }
            }

            # if three or fewer alignments all to desired chrom, find left and right matches among aligns (or, at some point, deal with inversions):
           
            if ((@region_aligns <= 3) && !(grep {$_->{ref_entry} ne $chrom} @region_aligns)) { # simple insertion, deletion, or inversion
                my @simple_breaks = ();
                my @inversion_aligns = ();
                if (@region_aligns == 2 && $region_aligns[0]->{comp} == $region_aligns[1]->{comp}) {
                    # order them, if possible, checking for consistency:
                    @simple_breaks = find_breaks($region_aligns[0], $region_aligns[1]);
                    print STDERR "ONE SIMPLE BREAK\n" if (@simple_breaks==1);
                }
                elsif ((@region_aligns==3) && ($region_aligns[0]->{comp} == $region_aligns[1]->{comp}) && 
                    ($region_aligns[1]->{comp} == $region_aligns[2]->{comp})) {
                    @simple_breaks = find_breaks($region_aligns[0], $region_aligns[1], $region_aligns[2]);
                    print STDERR "TWO SIMPLE BREAKS\n" if (@simple_breaks==2);
                }
                elsif ((@region_aligns==3) && ($region_aligns[0]->{comp} != $region_aligns[1]->{comp}) &&
                       ($region_aligns[1]->{comp} != $region_aligns[2]->{comp})) {
                    @inversion_aligns = ($region_aligns[0], $region_aligns[1], $region_aligns[2]);
                    print STDERR "INVERSION!\n";
                }

                foreach my $ra_simple_break (@simple_breaks) {
                    my $left_align = $ra_simple_break->[0];
                    my $right_align = $ra_simple_break->[1];
    
                    my $ref1 = $left_align->{ref_end};
                    my $ref2 = $right_align->{ref_start};
                    my $refjump = $ref2 - $ref1 - 1;
               
                    my $query1 = $left_align->{query_end}; 
                    my $query2 = $right_align->{query_start}; 
                    my $queryjump = ($comp) ? $query1 - $query2 - 1 : $query2 - $query1 - 1; # from show-diff code--number of unaligned bases

                    my $svsize = $refjump - $queryjump; # negative for insertions/positive for deletions
                 
                    my $type = ($refjump < 0 && $queryjump < 0) ? (($svsize < 0) ? 'DUP' : 'CONTRAC') :
                               (($svsize < 0 ) ? 'SIMPLEINS' : 'SIMPLEDEL'); # we reverse this later on so that deletions have negative SVLEN

                    if (($svsize < 0) && ($refjump > 0)) {
                        $type = 'SUBSINS';
                    }
                    elsif (($svsize > 0) && ($queryjump > 0)) {
                        $type = 'SUBSDEL';
                    }
                    elsif ($svsize == 0) { # is this even possible?--yes, but these look like alignment artifacts
                        next;
                    }
                    $svsize = abs($svsize);
                    my $repeat_bases = ($type eq 'SIMPLEINS' || $type eq 'DUP') ? -1*$refjump : 
                                        (($type eq 'SIMPLEDEL' || $type eq 'CONTRAC') ? -1*$queryjump : 0);
  
                    if ($repeat_bases > 10*$svsize) { # likely alignment artifact?
                        next;
                    }

                    if ($svsize > $Opt{maxsize}) {
                        print STDERR "SKIPPING $type of size $svsize because it is larger than max size ($Opt{maxsize})\n";
                        next;
                    }

                    print STDERR "TYPE $type size $svsize (REFJUMP $refjump QUERYJUMP $queryjump)\n"; 
    
                    if ($type eq 'SIMPLEINS' || $type eq 'DUP') {
                        process_insertion($delta_obj, $left_align, $right_align, $chrom, $contig,
                              $ref1, $query1, $ref2, $query2, $comp, $type, $svsize, 
                              $refjump, $queryjump, $repeat_bases, $ra_vcf_lines);
                    }
                    elsif ($type eq 'SIMPLEDEL' || $type eq 'CONTRAC') {
                        process_deletion($delta_obj, $left_align, $right_align, $chrom, $contig,
                              $ref1, $query1, $ref2, $query2, $comp, $type, $svsize, 
                              $refjump, $queryjump, $repeat_bases, $ra_vcf_lines);
                    }
                    else {
                        my $altpos = ($comp) ? $query1 - 1 : $query1 + 1;
                        my $altend = ($comp) ? $query2 + 1 : $query2 - 1;
                        my $rh_var = {'type' => $type,
                                      'svsize' => $svsize,
                                      'repbases' => 0,
                                      'chrom' => $chrom,
                                      'pos' => $ref1 + 1,
                                      'end' => $ref2 - 1,
                                      'contig' => $contig,
                                      'altpos' => $altpos,
                                      'altend' => $altend,
                                      'ref1' => $ref1,
                                      'ref2' => $ref2,
                                      'refjump' => $refjump,
                                      'query1' => $query1,
                                      'query2' => $query2,
                                      'queryjump' => $queryjump,
                                      'comp' => $comp,
                                     };
                        write_simple_variant($ra_vcf_lines, $rh_var);
                    }
                }

                # is it an inversion?
                if (@inversion_aligns) {
                    # OOPS! Not implemented yet
                }
            }
        }
    }
}

sub check_region {
    my $ref_db = shift;
    my $chrom = shift;
    my $start = shift;
    my $end = shift;

    my $chrlength = $ref_db->len($chrom);
    if ((0 >= $start - $Opt{buffer}) || ($chrlength < $end + $Opt{buffer})) {
        print STDERR "REGION $chrom:$start-$end is too close to an end of the chromosome $chrom!\n";
        return 0;
    }
    else {
        return 1;
    }
}

sub find_valid_entry_pairs {
    my $ra_rentry_pairs = shift;
    my $ref_left_start = shift;
    my $ref_left_end = shift;
    my $ref_right_start = shift;
    my $ref_right_end = shift;

    my @valid_entry_pairs = ();
    foreach my $rh_entrypair (@{$ra_rentry_pairs}) { # each contig with alignments to this reference entry
        my @left_span_aligns = grep {$_->{ref_start} < $ref_left_start && $_->{ref_end} > $ref_left_end} @{$rh_entrypair->{aligns}}; # aligns that span left
        my @right_span_aligns = grep {$_->{ref_start} < $ref_right_start && $_->{ref_end} > $ref_right_end} @{$rh_entrypair->{aligns}}; # aligns that span right
        if (!(@left_span_aligns) || !(@right_span_aligns)) { # need to span both sides
            next;
        }
        else {
            my $no_left_aligns = @left_span_aligns;
            my $no_right_aligns = @right_span_aligns;
            print STDERR "Contig $rh_entrypair->{query_entry} has $no_left_aligns left aligns and $no_right_aligns right aligns!\n";
        }

        # want to find the same comp value on left and right side:
        if (grep {$_->{comp} == 0} @left_span_aligns && grep {$_->{comp} == 0} @right_span_aligns) {
            $rh_entrypair->{comp} = 0;
            push @valid_entry_pairs, $rh_entrypair;
            print STDERR "At least one forward alignment on left and right\n";
        }
        elsif (grep {$_->{comp} == 1} @left_span_aligns && grep {$_->{comp} == 1} @right_span_aligns) {
            $rh_entrypair->{comp} = 1;
            push @valid_entry_pairs, $rh_entrypair;
            print STDERR "At least one reverse alignment on left and right\n";
        }
        else {
            print STDERR "Odd line up of alignments for contig $rh_entrypair->{query_entry}\n";
            next;
        }
    }

    return @valid_entry_pairs;
}

sub pull_region_contig_aligns {
    my $ra_contigaligns = shift;
    my $chrom = shift;
    my $refleftend = shift;
    my $refrightstart = shift;

    my $in_region = 0;
    my @region_aligns = ();
    foreach my $rh_contigalign (@{$ra_contigaligns}) { # these should in theory be stepping up through the reference, down through the contig for comp aligns
        if (!($in_region) && ($rh_contigalign->{ref_entry} eq $chrom && $rh_contigalign->{ref_end} > $refleftend)) {
           $in_region = 1;
        }
        elsif (($in_region) && ($rh_contigalign->{ref_entry} eq $chrom && $rh_contigalign->{ref_start} > $refrightstart)) {
            last;
        }

        if ($in_region) {
            push @region_aligns, $rh_contigalign;
        }
    }

    return @region_aligns;
}

sub find_breaks {
    my @aligns = @_;

    # right now this routine accepts 2 or 3 alignments, all of which have the same value of "comp".
    # it attempts to order them left to right wrt the reference, and create pairs of alignments
    # that represent breaks corresponding to structural variants

    my @valid_breaks = ();
    my @sorted_aligns = sort {($a->{ref_start} <=> $b->{ref_start}) || ($a->{ref_end} <=> $b->{ref_end})} @aligns;
    for (my $left_index = 0; $left_index <= $#sorted_aligns - 1; $left_index++) { # consider consecutive pairs
        my $left_align = $sorted_aligns[$left_index];
        my $right_align = $sorted_aligns[$left_index + 1];

        # is it a valid pair of aligns?

        if ($left_align->{ref_end} < $right_align->{ref_end}) {
            if ((!$left_align->{comp} && # should line up left to right
                   $left_align->{query_start} < $right_align->{query_start} && 
                   $left_align->{query_end} < $right_align->{query_end}) ||
                ($left_align->{comp} && # query decreasing
                   $left_align->{query_start} > $right_align->{query_start} && 
                   $left_align->{query_end} > $right_align->{query_end})) {

                push @valid_breaks, [$left_align, $right_align];
            }
            else {
                print STDERR "INVALID ALIGNS $left_align->{query_start}-$left_align->{query_end}, then $right_align->{query_start}-$right_align->{query_end}\n";
            }
        }
        else {
            print STDERR "REF ENDS OUT OF ORDER $left_align->{ref_start}-$left_align->{ref_end}, then $right_align->{ref_start}-$right_align->{ref_end}\n";
        }
    }

    return @valid_breaks;
}

sub process_insertion {
    my $delta_obj = shift;
    my $left_align = shift;
    my $right_align = shift;
    my $chrom = shift;
    my $contig = shift;
    my $ref1 = shift;
    my $query1 = shift;
    my $ref2 = shift;
    my $query2 = shift;
    my $comp = shift;
    my $type = shift;
    my $svsize = shift;
    my $refjump = shift;
    my $queryjump = shift;
    my $repeat_bases = shift;
    my $ra_vcf_lines = shift;

    print STDERR "Type $type comp $comp, varcontig $contig query1 $query1, query2 $query2, ref $chrom ref1 $ref1, ref2 $ref2\n" if ($Opt{verbose});
    print STDERR "Refjump $refjump, query jump $queryjump, svsize $svsize\n" if ($Opt{verbose});

    $delta_obj->find_query_coords_from_ref_coord($ref1, $chrom);
    $delta_obj->find_query_coords_from_ref_coord($ref2, $chrom);

    if (!$left_align->{query_matches}->{$ref1} || $query1 != $left_align->{query_matches}->{$ref1}) {
        die "QUERY1 $query1 doesn\'t match $left_align->{query_matches}->{$ref1}\n"; 
    }
    
    if (!$right_align->{query_matches}->{$ref2} || $query2 != $right_align->{query_matches}->{$ref2}) {
        die "QUERY2 $query2 doesn\'t match $right_align->{query_matches}->{$ref2}\n"; 
    }
    
    my $query1p = $right_align->{query_matches}->{$ref1};
    my $query2p = $left_align->{query_matches}->{$ref2};

    print STDERR "query1p $query1p corresponds to ref $ref1 in second align, query2p $query2p corresponds to ref2 $ref2 in first align\n" if ($Opt{verbose});

    if (!defined($query1p)) {
        print STDERR "NONREPETITIVE INSERTION--need to check\n";
        $query1p = $query2 - 1;
    }
    if (!defined($query2p)) {
        print STDERR "NONREPETITIVE INSERTION--need to check\n";
        $query2p = $query1 - 1;
    }

    my $altpos = ($comp) ? $query2p + 1 : $query2p - 1;
    my $altend = ($comp) ? $query2 + 1 : $query2 - 1;
    my $rh_var = {'type' => $type,
                  'svsize' => -1.0*$svsize,
                  'repbases' => $repeat_bases,
                  'chrom' => $chrom,
                  'pos' => $ref2 - 1,
                  'end' => $ref2 - 1,
                  'contig' => $contig,
                  'altpos' => $altpos,
                  'altend' => $altend,
                  'ref1' => $ref1,
                  'ref2' => $ref2,
                  'refjump' => $refjump,
                  'query1' => $query1,
                  'query2' => $query2,
                  'queryjump' => $queryjump,
                  'comp' => $comp,
                  'query1p' => $query1p,
                  'query2p' => $query2p,
                  };

    write_simple_variant($ra_vcf_lines, $rh_var);
}

sub process_deletion {
    my $delta_obj = shift;
    my $left_align = shift;
    my $right_align = shift;
    my $chrom = shift;
    my $contig = shift;
    my $ref1 = shift;
    my $query1 = shift;
    my $ref2 = shift;
    my $query2 = shift;
    my $comp = shift;
    my $type = shift;
    my $svsize = shift;
    my $refjump = shift;
    my $queryjump = shift;
    my $repeat_bases = shift;
    my $ra_vcf_lines = shift;

    print STDERR "Type $type comp $comp, varcontig $contig query1 $query1, query2 $query2, ref $chrom ref1 $ref1, ref2 $ref2\n" if ($Opt{verbose});
    print STDERR "Refjump $refjump, query jump $queryjump, svsize $svsize\n" if ($Opt{verbose});

    $delta_obj->find_ref_coords_from_query_coord($query1, $contig);
    $delta_obj->find_ref_coords_from_query_coord($query2, $contig);

    if (!$left_align->{ref_matches}->{$query1} || $ref1 != $left_align->{ref_matches}->{$query1}) {
        die "REF1 $ref1 doesn\'t match $left_align->{ref_matches}->{$query1}\n"; 
    }
    
    if (!$right_align->{ref_matches}->{$query2} || $ref2 != $right_align->{ref_matches}->{$query2}) {
        die "REF2 $ref2 doesn\'t match $right_align->{ref_matches}->{$query2}\n"; 
    }
    
    my $ref1p = $right_align->{ref_matches}->{$query1};
    my $ref2p = $left_align->{ref_matches}->{$query2};

    if (!defined($ref1p)) {
        print STDERR "NONREPETITIVE DELETION (ref1p undefined)--need to check\n";
        $ref1p = $ref2 - 1;
    }
    if (!defined($ref2p)) {
        print STDERR "NONREPETITIVE DELETION (ref2p undefined)--need to check\n";
        $ref2p = $ref1 + 1;
    }

    print STDERR "ref1p $ref1p corresponds to query $query1 in second align, ref2p $ref2p corresponds to query2 $query2 in first align\n" if ($Opt{verbose});

    my $altpos = ($comp) ? $query2 + 1 : $query2 - 1;
    my $altend = ($comp) ? $query2 + 1 : $query2 - 1;
    my $rh_var = {'type' => $type,
                  'svsize' => -1.0*$svsize,
                  'repbases' => $repeat_bases,
                  'chrom' => $chrom,
                  'pos' => $ref2p - 1,
                  'end' => $ref2 - 1,
                  'contig' => $contig,
                  'altpos' => $altpos,
                  'altend' => $altend,
                  'ref1' => $ref1,
                  'ref2' => $ref2,
                  'refjump' => $refjump,
                  'query1' => $query1,
                  'query2' => $query2,
                  'queryjump' => $queryjump,
                  'comp' => $comp,
                  'ref1p' => $ref1p,
                  'ref2p' => $ref2p,
                 };

    write_simple_variant($ra_vcf_lines, $rh_var);
}

sub write_simple_variant {
    my $ra_vcf_lines = shift;
    my $rh_var = shift;

    my $vartype = $rh_var->{type};
    my $svsize = $rh_var->{svsize};
    my $repbases = $rh_var->{repbases};
    my $chrom = $rh_var->{chrom};
    my $pos = $rh_var->{pos};
    my $end = $rh_var->{end};
    my $varcontig = $rh_var->{contig};
    my $altpos = $rh_var->{altpos};
    my $altend = $rh_var->{altend};
    my $ref1 = $rh_var->{ref1};
    my $ref2 = $rh_var->{ref2};
    my $refjump = $rh_var->{refjump};
    my $query1 = $rh_var->{query1};
    my $query2 = $rh_var->{query2};
    my $queryjump = $rh_var->{queryjump};
    my $comp = $rh_var->{comp};
    my $query1p = $rh_var->{query1p};
    my $query2p = $rh_var->{query2p};
    my $ref1p = $rh_var->{ref1p};
    my $ref2p = $rh_var->{ref2p};

    my $chrlength = $ref_db->len($chrom);
    my $varcontiglength = $query_db->len($varcontig);

    if ($vartype eq 'SIMPLEINS' || $vartype eq 'DUP') {
        my ($refseq, $altseq) = ('N', '<INS>');
        $svsize = abs($svsize); # insertions always positive

        if ($Opt{includeseqs}) {
            if ($pos >= 1 && $pos <= $chrlength) {
                $refseq = uc($ref_db->seq($chrom, $pos, $pos));
            }
            else {
                print "Ref position of $vartype at $pos is not within chromosome $chrom boundaries--skipping!\n";
                return;
            }

            if ($altpos > $altend) { # extract and check:
                $altseq = uc($query_db->seq($varcontig, $altend, $altpos)); # GTB::FASTA will reverse complement if necessary unless altpos = altend
                if ($altseq =~ /[^ATGCatgcNn]/) { # foundit!
                    die "Seq $varcontig:$altend-$altpos has non ATGC char!\n";
                }
            }
            if (($altpos >= 1 && $altpos <= $varcontiglength) && ($altend >= 1 && $altend <= $varcontiglength)) {
                $altseq = uc($query_db->seq($varcontig, $altpos, $altend)); # GTB::FASTA will reverse complement if necessary unless altpos = altend
                if (($comp) && ($altpos == $altend)) { # need to complement altseq
                    $altseq =~ tr/ATGCatgc/TACGtacg/;
                }
            }
            else {
                print "Varcontig positions of $vartype at $varcontig:$altpos-$altend are not within contig $varcontig boundaries--skipping!\n";
                return;
            }
        }

        my $compstring = ($comp) ? '_comp' : '';
        my $svtype = 'INS';

        my $varstring = "$chrom\t$pos\t.\t$refseq\t$altseq\t.\tPASS\tEND=$end;SVTYPE=$svtype;REPTYPE=$vartype;SVLEN=$svsize;BREAKSIMLENGTH=$repbases;REFWIDENED=$chrom:$ref2-$ref1;ALTPOS=$varcontig:$altpos-$altend$compstring;ALTWIDENED=$varcontig:$query2p-$query1p$compstring";
        push @{$ra_vcf_lines}, "$varstring";
    }
    elsif ($vartype eq 'SIMPLEDEL' || $vartype eq 'CONTRAC') {
        my ($refseq, $altseq) = ('N', '<DEL>');
        $svsize = -1.0*abs($svsize); # deletions always negative
        if (!$repbases) { # kludgy for now
            $ref2p++;
            if ($comp) {
                $query2++;
            }
            else {
                $query2--;
            }
        }
        if ($pos > $end) {
            die "Deletion position $pos is greater than endpoint $end for $chrom:$pos, svlen $svsize, breaksimlength $repbases\n";
        }
        if ($Opt{includeseqs}) {
            if ($pos >= 1 && $end <= $chrlength) {
                $refseq = uc($ref_db->seq($chrom, $pos, $end));
            }
            else {
                print "Ref position of $vartype at $pos-$end is not within chromosome $chrom boundaries--skipping!\n";
                return;
            }
            if ($altpos >= 1 && $altpos <= $varcontiglength) {
                $altseq = uc($query_db->seq($varcontig, $altpos, $altpos));
                if ($comp) { # need to complement altseq
                    $altseq =~ tr/ATGC/TACG/;
                }
            }
            else {
                print "Varcontig positions of $vartype at $varcontig:$altpos-$altpos are not within contig $varcontig boundaries--skipping!\n";
                return;
            }
        }
        my $svtype = 'DEL';

        my $compstring = ($comp) ? '_comp' : '';
        my $varstring = "$chrom\t$pos\t.\t$refseq\t$altseq\t.\tPASS\tEND=$end;SVTYPE=$svtype;REPTYPE=$vartype;SVLEN=$svsize;BREAKSIMLENGTH=$repbases;REFWIDENED=$chrom:$ref2p-$ref1p;ALTPOS=$varcontig:$altpos-$altpos$compstring;ALTWIDENED=$varcontig:$query2-$query1$compstring";
        push @{$ra_vcf_lines}, "$varstring";
    }
    else { # complex "SUBS" types--note, this code is NOT appropriate for inversions!
        my ($refseq, $altseq) = ('N', 'N');
        $svsize = ($vartype =~ /DEL/) ? -1.0*abs($svsize) : abs($svsize); # insertions always positive
        my $svtype = ($vartype =~ /DEL/) ? 'DEL' : 'INS';

        if ($Opt{includeseqs}) {
            $refseq = uc($ref_db->seq($chrom, $pos, $end));
            $altseq = uc($query_db->seq($varcontig, $altpos, $altend));
            if (($altpos == $altend) && ($comp)) {
                $altseq =~ tr/ATGC/TACG/;
            }
        }

        my $compstring = ($comp) ? '_comp' : '';
        my $varstring = "$chrom\t$pos\t.\t$refseq\t$altseq\t.\tPASS\tEND=$end;SVTYPE=$svtype;REPTYPE=$vartype;SVLEN=$svsize;BREAKSIMLENGTH=$repbases;REFWIDENED=$chrom:$ref1-$ref2;ALTPOS=$varcontig:$altpos-$altend$compstring;ALTWIDENED=$varcontig:$query1-$query2$compstring";
        push @{$ra_vcf_lines}, "$varstring";
    }
}

sub write_variants_to_vcf {
    my $vcf_fh = shift;
    my $ref_fh = shift;
    my $ra_variant_lines = shift;
    my $ra_ref_cov = shift;

    # write VCF lines in order, adding genotypes and avoiding redundancy:
    my @sorted_vcf_lines = sort byposthenend @{$ra_variant_lines};

    my %written = ();
    foreach my $vcf_line (@sorted_vcf_lines) {
        my ($pos, $end) = ($vcf_line =~ /^(\S+)\s(\d+).*END=(\d+)/) ? ($2, $3) : (0, 0);
        my $gt = covered($ra_ref_cov, $pos, $end) ? '0/1' : '1';
        if (!$written{"$pos:$end"}) {
            print $vcf_fh "$vcf_line\tGT\t$gt\n";
            $written{"$pos:$end"} = 1;
        }
    }

    # write reference regions to BED formatted "ref coverage" file
    foreach my $ra_refregion (sort {$a->[1] <=> $b->[1]} @{$ra_ref_cov}) {
        my $region_line = join "\t", @{$ra_refregion};
        print $ref_fh "$region_line\n";
    }
}

sub covered {
    my $ra_ref_cov = shift;
    my $pos = shift;
    my $end = shift;

    foreach my $ra_hr (@{$ra_ref_cov}) {
        if ($ra_hr->[1] <= $pos && $ra_hr->[2] >= $end) {
            return 1;
        }
    }
    return 0;
}

sub byposthenend {
    my ($pos_a, $end_a) = ($a =~ /^(\S+)\s(\d+).*END=(\d+)/) ? ($2, $3) : (0, 0);
    my ($pos_b, $end_b) = ($b =~ /^(\S+)\s(\d+).*END=(\d+)/) ? ($2, $3) : (0, 0);

    if ($pos_a != $pos_b) {
        return $pos_a <=> $pos_b;
    }
    else { # equal starts, sort ends:
        return $end_a <=> $end_b;
    }
}

__END__

=head1 OPTIONS

=over 4

=item B<--delta <path to delta file>>

Specify a delta file produced by MUMmer with the alignments to be used for
retrieving SV sequence information.  Generally, one would use the same
filtered delta file that was used to create the "diff" file (see below).
(Required).

=item B<--regions <path to a BED file of regions>>

Specify a BED file of regions to be investigated for structural variants
in the assembly (i.e., the query fasta file).
(Required).

=item B<--ref_fasta <path to reference multi-fasta file>>

Specify the path to a multi-fasta file containing the sequences used as 
reference in the MUMmer alignment.  If not specified on the command line,
the script uses the reference path obtained by parsing the delta file's
first line.

=item B<--query_fasta <path to query multi-fasta file>>

Specify the path to a multi-fasta file containing the sequences used as 
the query in the MUMmer alignment.  If not specified on the command line,
the script uses the query path obtained by parsing the delta file's
first line.

=item B<--outvcf <path to which to write a new VCF-formatted file>>

Specify the path to which to write a new VCF file containing the structural
variants discovered in this comparison.  BEWARE: if this file already 
exists, it will be overwritten!

=item B<--refname <string to include as the reference name in the VCF header>>

Specify a string to be written as the reference name in the ##reference line 
of the VCF header.

=item B<--samplename <string to include as the sample name in the "CHROM" line>>

Specify a string to be written as the sample name in the header specifying a 
genotype column in the VCF line beginning with "CHROM".

=item B<--maxsize <maximum size of SV to report>>

Specify an integer for the maximum size of SV to report. 

=item B<--noheader>

Flag option to suppress printout of the VCF header.

=item B<--help|--manual>

Display documentation.  One C<--help> gives a brief synopsis, C<-h -h> shows
all options, C<--manual> provides complete documentation.

=back

=head1 AUTHOR

 Nancy F. Hansen - nhansen@mail.nih.gov

=head1 LEGAL

This software/database is "United States Government Work" under the terms of
the United States Copyright Act.  It was written as part of the authors'
official duties for the United States Government and thus cannot be
copyrighted.  This software/database is freely available to the public for
use without a copyright notice.  Restrictions cannot be placed on its present
or future use. 

Although all reasonable efforts have been taken to ensure the accuracy and
reliability of the software and data, the National Human Genome Research
Institute (NHGRI) and the U.S. Government does not and cannot warrant the
performance or results that may be obtained by using this software or data.
NHGRI and the U.S.  Government disclaims all warranties as to performance,
merchantability or fitness for any particular purpose. 

In any work or product derived from this material, proper attribution of the
authors as the source of the software or data should be made, using "NHGRI
Genome Technology Branch" as the citation. 

=cut
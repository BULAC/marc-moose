package MARC::Moose::Formater::UnimarcToMarc21;
# ABSTRACT: Convert biblio record from UNIMARC to MARC21
use Moose;

use 5.010;
use utf8;

extends 'MARC::Moose::Formater';

use MARC::Moose::Field::Control;
use MARC::Moose::Field::Std;


# Equivalence UNIMARC author type code > MARC21
# Each UNIMARC code points to a array ref which first entry contains MARC21
# code and second MARC21 author type description. The second entry isn't used
# yet.
my %authcode = map { /^(\d*) (\w*) (.*)$/; $1 => [$2, $3] } split /\n/, <<EOS;
005 act actor
010 adp adapter
020 ann annotator
030 arr arranger
040 art artist
050 asg assignee
060 asn associated name
065 auc auctioneer
070 aut author
072 aqt author in quotations or text abstract
075 aft author of afterword, colophon, etc.
080 aui author of introd
090 aus author of screenplay
100 ant bibl. antecedent
110 bnd binder
120 bdd binding designer
130 bkd book designer
140 bjd bkjacket designer
150 bpd bkplate designer
160 bsl bookseller
170 cll calligrapher
180 ctg cartographer
190 cns censor
200 chr choreographer
205 clb collaborator
210 cmm commentator
212 cwt commentator for written text
220 com compiler
230 cmp composer
240 cmt compositor
245 ccp conceptor
250 cnd conductor
255 csp consultant to a project
260 cph copyright holder
270 crr corrector
273 cur curator
275 dnc dancer
280 dte dedicatee
290 dto dedicator
295 dgg degree grantor
300 drt director
305 dis dissertant
310 dst distributor
320 dnr donor
330 dub dubious author
340 edt editor
350 egr engraver
360 etr etcher
365 exp expert
370 flm film editor
380 frg forger
390 fmo former owner
400 fnd funder
410 grt graphic technician
420 hnr honoree
430 ilu illuminator
440 ill illustrator
450 ins inscriber
460 ive interviewee
470 ivr interviewer
480 lbt librettist
490 lse licensee
500 lso licensor
510 ltg lithographer
520 lyr lyricist
530 mte metal engraver
540 mon monitor/contractor
545 mus musician
550 nrt narrator
555 opn opponent
557 orm organizer of meeting
560 org originator
570 oth other
580 ppm papermaker
582 pta patent applicant
584 inv inventor
587 pth patent holder
590 prf performer
595 res research
600 pht photographer
610 prt printer
620 pop printer of plates
630 pro producer
635 prg programmer
640 pfr proofreader
650 pbl publisher
651 pbd publishing director
660 rcp recipient
670 rce recording engineer
673 rth research team head
675 rev reviewer
677 rtm research team member
680 rbr rubricator
690 sce scenarist
695 sad scientific advisor
700 scr scribe
705 scl sulptor
710 sec secretary
720 sgn signer
721 sng singer
723 spn sponsor
725 stn standards body
727 ths thesis advisor
730 trl translator
740 tyd type designer
750 tyg typographer
755 voc vocalist
760 wde wood engraver
770 wam writer of accompanying material
EOS

# UNIMARC 100 Type of pub
my %typeofpub = map { /(\w) (\w)/; $1 => $2;  } split /\n/, <<EOS;
a c
b d
c u 
d s
e r
f q
g m
h t
i p
j e
EOS

# UNIMARC 100 Target Audience Code
my %target_audience = map { /(\w|\|) (\w|\|)/; $1 => $2;  } split /\n/, <<EOS;
b a
c b
a j
d c
e d
k e
m g
| |
EOS

# List of moved fields unchanged
my @unchanged;
push @unchanged, [$_, 500]  for 300..315;
push @unchanged, [320, 504],
                 [321, 500],
                 [322, 508],
                 [323, 511],
                 [324, 500],
                 [328, 502],
                 [330, 520],
                 [332, 524],
                 [333, 521],
                 [337, 538],
                 [686, '084'];


override 'format' => sub {
    my ($self, $unimarc) = @_;

    my $record = MARC::Moose::Record->new();

    $record->_leader("     nam a22     7a 4500");

    my $code008 = '120130t        xxu||||| |||| 00| 0 ||| d';

    my @sf040;

    # 001 => 001
    for my $field ( $unimarc->field('001' ) ) {
        $record->append($field->clone());
    }

    # ISBN 010 => 020
    for my $field ( $unimarc->field('010') ) {
        my @sf;
        for ( @{$field->subf} ) {
            my ($letter, $value) = @$_;
            given ($letter) {
                when ( /a|z/ ) {
                    $value =~ s/-//g;
                    push @sf, [ $letter => $value ];
                }
                when ( /b/ ) {
                    $value = "($value)" unless $value =~ /^\(/;
                    if (@sf) {
                        $sf[-1]->[1] .= " $value";
                    }
                    else {
                        push @sf, [ c => $value ];
                    }
                }
                when ( /d/ ) {
                    if (@sf) {
                        $sf[-1]->[1] .= " :";
                    }
                    push @sf, [ c => $value ];
                }
            }
        }
        $record->append( MARC::Moose::Field::Std->new(
            tag => '020', subf => \@sf ) );
    }

    # ISSN 011 => 022
    # Except 011$b$d => 365
    for my $field ( $unimarc->field('011') ) {
        my (@sf, @price);
        for ( @{$field->subf} ) {
            my ($letter, $value) = @$_;
            given ($letter) {
                when ( /a/ ) {
                    $value =~ s/-//g;
                    push @sf, [ a => $value ];
                }
                when ( /z/ ) {
                    $value =~ s/-//g;
                    push @sf, [ y => $value ];
                }
                when ( /b|d/ ) {
                    $value = "($value)" unless $value =~ /^\(/;
                    my $newlet = $letter eq 'b' ? 'b' : 'd';
                    push @price, [ $newlet => $value ];
                }
            }
        }
        $record->append( MARC::Moose::Field::Std->new(
            tag => '022', subf => \@sf ) ) if @sf;
        $record->append(MARC::Moose::Field::Std->new(
            tag => '365', subf => \@price ) ) if @price;
    }

    # 100 => 008
    if ( my $field = $unimarc->field('100') ) {
        my $code100 = $field->subfield('a');
        if ( $code100 && length($code100) > 20 ) {
            # Date entered on file
            substr $code008, 0, 6, substr($code100, 2, 6);

            # Type of publication date
            my $value = substr($code100, 8, 1);
            $value = $typeofpub{$value} || ' ';
            substr $code008, 6, 1, $value;

            # Date 1
            $value = substr($code100, 9, 4);
            if ( 1 ) { #FIXME Determine if it's a serials
                # Not serials
                my $count = 0;
                for ( split //, $value ) { $count++ if / /; }
                $value =~ s/ /0/g  if $count <= 3;
            }
            else {
                # A serials
                $value =~ s/ /u/g;
            }
            substr $code008, 7, 4, $value;

            # Date 2
            $value = substr($code100, 13, 4);
            if ( 1 ) { #FIXME Determine if it's a serials
                # Not serials
                my $count = 0;
                for ( split //, $value ) { $count++ if / /; }
                $value =~ s/ /0/g  if $count <= 3;
            }
            else {
                # A serials
                $value =~ s/ /u/g;
            }
            substr $code008, 11, 4, $value;

            # 3 positions for target audience
            $value = substr($code100, 17, 3);
            for (my $i=0; $i < 3; $i++) {
                $value = substr($code100, 17+$i, 1);
                $value = $target_audience{$value} || ' ';   
                substr $code008, 17+$i, 1, $value;
            }
            
            # Language of cataloging
            push @sf040, [ b => substr($code100, 22, 3) ];

            # Alphabet of title, converted if serials
            # FIXME
            if ( 0 ) {
                substrr $code008, 33, 1, substr($code100,34,1);
            }
        }
    }

    # Language 101 => 041 and 008
    if ( my $field = $unimarc->field('101') ) {
        # FIXME: à virer
        if ( ref($field) eq 'MARC::Moose::Field::Control' ) {
            say $unimarc->as('Text');
            exit;
        }
        my @all = @{$field->subf};
        my $count_a = 0;
        my (@sf, @sf_b);
        for (@all) {
            my ($letter, $value) = @$_;
            given ($letter) {
                when ( /a/ ) {
                    next if $count_a >= 6;
                    $count_a++;
                    if ( $count_a == 1 ) {
                        $value .= '   ';
                        $value = substr($value, 0, 3);
                        substr $code008, 35, 3, $value; 
                    }
                    push @sf, [ a => $value];
                }
                when ( /c/ ) { push @sf, [ h => $value ]; }
                when ( /b/ ) { push @sf_b, $value; }
                when ( /d/ ) { push @sf, [ b => $value ]; }
                when ( /e/ ) { push @sf, [ f => $value ]; }
                when ( /f|g/ ) { }
                when ( /j/ ) { push @sf, [ b => $value ]; }
                when ( /h/ ) { push @sf, [ e => $value ]; }
                when ( /i/ ) { push @sf, [ g => $value ]; }
            }
        }
        if ( @sf_b ) {
            for ( @sf ) {
                if ($_->[0] eq 'h') {
                    $_->[1] .= ' ' . join(' ', @sf_b);
                    last;
                }
            }
        }
        my $ind1 = $field->ind1;
        $ind1 = '0' if $ind1 eq ' ';
        $ind1 = '1' if $ind1 eq '2';
        $record->append( MARC::Moose::Field::Std->new(
            tag => '041',
            ind1 => $ind1,
            subf => \@sf ) );
    }
    else {
        substr($code008, 35, 3) = '|||'; 
    }

    # 125 => 008
    # FIXME: 125$b isn't handled at all
    if ( my $field = $unimarc->field('125') ) {
        my $value = $field->subfield('a');
        my ($pos0, $pos1);
        $pos0 =  substr($value, 0, 1) if $value && length($value) >= 1;
        $pos1 =  substr($value, 1, 1) if $value && length($value) >= 2;
        $pos0 ||= '|';
        $pos0 = 'n' if $pos0 eq 'x';
        $pos1 ||= '|';
        $pos1 = 'n' if $pos1 eq 'x';
        $pos1 = ' ' if $pos1 eq 'y';
        substr($code008, 20, 2) = $pos0 . $pos1;
    }

    $record->append( MARC::Moose::Field::Control->new(
        tag => '008', value => $code008 ) );

    # Title
    for my $field ( $unimarc->field('200') ) {
        my @sf;
        my ($a_index, $h_index) = (-1, -1);
        for ( @{$field->subf} ) {
            my ($letter, $value) = @$_;
            given ($letter) {
                when ( 'a' )   {
                    if ( $a_index == -1 ) {
                        push @sf, [ a => $value ];
                        $a_index = $#sf;
                    }
                    else {
                        $sf[$a_index]->[1] .= " ; $value";
                    }
                }
                when ( 'b')    { 
                    if ( $h_index == -1 ) {
                        push @sf, [ h => $value ];
                        $h_index = $#sf;
                    }
                    else {
                        if ( $#sf == $h_index ) {
                            $sf[$h_index]->[1] .= " + $value";
                        }
                        else {
                            $sf[-1]->[1] .= " ($value)";
                        }
                    }
                }
                when ( 'c' ) {
                    next unless @sf; #FIXME warning required
                    $sf[-1]->[1] .= ". $value";
                }
                when ( 'd' ) {
                    next unless @sf; #FIXME warning required
                    if ( $sf[-1]->[0] =~ /a|n|p/ ) {
                        $sf[-1]->[1] .= ' =';
                        $value =~ s/^= //;
                        push @sf, [ b => $value ];
                    }
                    else {
                        $sf[-1]->[1] .= " $value";
                    }
                }
                when ( 'e' ) {
                    next unless @sf; #FIXME warning required
                    if ( $sf[-1]->[0] =~ /a|n|p/ ) {
                        $sf[-1]->[1] .= ' :';
                        push @sf, [ b => $value ];
                    }
                    else {
                        $sf[-1]->[1] .= " : $value";
                    }
                }
                when ( 'f') {
                    next unless @sf; #FIXME warning required
                    if ( $sf[-1]->[0] =~ /a|b|n|p/ ) {
                        $sf[-1]->[1] .= ' /';
                        push @sf, [ c => $value ];
                    }
                    else {
                        $sf[-1]->[1] .= " / $value";
                    }
                }
                when ( 'g') {
                    next unless @sf; #FIXME warning required
                    $sf[-1]->[1] .= " ; $value";
                }
                when ( 'h' ) {
                    next unless @sf; #FIXME warning required
                    if ( $sf[-1]->[0] =~ /a|n|p/ ) {
                        $sf[-1]->[1] .= '.';
                        push @sf, [ n => $value ];
                    }
                    else {
                        $sf[-1]->[1] .= ". $value";
                    }
                }
                when ( 'i' ) {
                    next unless @sf; #FIXME warning required
                    if ( @sf && $sf[-1]->[0] =~ /a|n|p/ ) {
                        $sf[-1]->[1] .= ',';
                        push @sf, [ p => $value ];
                    }
                    else {
                        $sf[-1]->[1] .= ". $value";
                    }
                }
                when ( /v|z|5|6|7/ ) { next }
            }
        }
        next unless @sf;
        $sf[$h_index]->[1] = '[' . $sf[$h_index]->[1] . ']' unless $h_index == -1;
        # Point final
        $sf[-1][1] = $sf[-1][1] . '.' if @sf;

        # Indicators
        my ($ind1, $ind2) = ($field->ind1, 0);
        given ($ind1) {
            when ( /0/ ) { }
            when ( /1/ ) {
                #FIXME Test marc21 100/110/111/130 presence
                $ind1 = $unimarc->field('700|710' ) ? 1 : 0;
            }
            default { $ind1 = 1; }
        }

        $record->append( MARC::Moose::Field::Std->new(
            tag => '245', ind1 => $ind1, ind2 => $ind2,
            subf => \@sf ) );
    }
    
    # TODO 204

    # 205 => 250
    for my $field ($unimarc->field('205') ) {
        my @sf;
        my ($a_index, $b_index) = (-1, -1);
        for ( @{$field->subf} ) {
            my ($letter, $value) = @$_;
            given ($letter) {
                when ( /a/ ) {
                    if ( $a_index == -1 ) {
                        push @sf, [ a => $value ];
                        $a_index = $#sf;
                    }
                    else {
                        $sf[$a_index]->[1] .= ", $value";
                    }
                }
                when ( /b/ ) {
                    if ( @sf ) {
                        $sf[-1]->[1] .= ", $value";
                    }
                    else {
                        push @sf, [ a => $value ];
                        $a_index = $#sf;
                    }
                }
                when ( /d/ ) {
                    if ( $b_index == -1 ) {
                        push @sf, [ b => $value];
                        $b_index = $#sf;
                    }
                    else {
                        $sf[-1]->[1] .= " $value";
                    }
                }
                when ( /f/ ) {
                    if ( $b_index == -1 ) {
                        $sf[-1]->[1] .= " / " if @sf;
                        push @sf, [ b => $value];
                        $b_index = $#sf;
                    }
                    else {
                        $sf[-1]->[1] .= " / $value";
                    }
                }
                when ( /g/ ) {
                    if ( @sf ) { $sf[-1]->[1] .= " / $value"; }
                    else       { push @sf, [ a => $value ] }
                }
            }
        }
        next unless @sf;
        if ( $b_index >= 1 ) {
            my $value = $sf[$b_index]->[1];
            if ( $value =~ /= $/ ) {
                $value =~ s/= $//;
                $sf[$b_index]->[1] = $value;
                $sf[$b_index-1]->[1] .= '= ';
            }
        }
        # Point final
        $sf[-1][1] = $sf[-1][1] . '.' if @sf && $sf[-1][1] !~ /\.$/;
        $record->append( MARC::Moose::Field::Std->new(
            tag => '250', ind1 => $field->ind1, ind2 => $field->ind2,
            subf => \@sf ) );
    }

    # TODO 206

    # 207 => 362
    for my $field ($unimarc->field('207') ) {
        my @sf;
        my $a_index = -1;
        for ( @{$field->subf} ) {
            my ($letter, $value) = @$_;
            given ($letter) {
                when ( /a/ ) {
                    if ( $a_index == -1 ) {
                        push @sf, [ a => $value ];
                        $a_index = $#sf;
                    }
                    else {
                        my $prev = $sf[$a_index]->[1];
                        $prev =~ s/ *$//;
                        $prev =~ s/;$//;
                        $prev =~ s/ *$//;
                        $sf[$a_index]->[1] = "$prev ; $value";
                    }
                }
                when ( /v/ ) {
                    push @sf, [ z => $value ];
                }
            }
        }
        next unless @sf;
        # Point at the end
        $sf[-1][1] = $sf[-1][1] . '.' if @sf && $sf[-1][1] !~ /\.$/;
        $record->append( MARC::Moose::Field::Std->new(
            tag => '362', ind2 => $field->ind1,
            subf => \@sf ) );
    }

    #TODO 208

    # 210 => 260
    for my $field ( $unimarc->field('210') ) {
        my @sf;
        for ( @{$field->subf} ) {
            my ($letter, $value) = @$_;
            $value =~ s/^ *//, $value =~ s/ *$//;
            my %found;
            given ($letter) {
                when ( /a/ ) {
                    push @sf, [ a => $value ];
                }
                when ( /b/ ) {
                    $value = "($value)" if $value !~ /^\(/;
                    if ( @sf ) {
                        $sf[-1]->[1] .= " $value";
                    }
                    else {
                        push @sf, [ a => $value ];
                    }
                }
                when ( /c/ ) {
                    push @sf, [ b => $value ];
                }
                when ( /d/ ) {
                    push @sf, [ c => $value ];
                }
                when ( /e/ ) {
                    unless ( $found{$letter} ) {
                        $found{$letter} = 1;
                        push @sf, [ a => $value ];
                    }
                }
                when ( /f/ ) {
                    unless ( $found{$letter} ) {
                        $found{$letter} = 1;
                        $sf[-1]->[1] .= ", $value" if @sf;
                    }
                }
                when ( /g/ ) {
                    unless ( $found{$letter} ) {
                        $found{$letter} = 1;
                        push @sf, [ f => $value ];
                    }
                }
                when ( /h/ ) {
                    unless ( $found{$letter} ) {
                        $found{$letter} = 1;
                        push @sf, [ g => $value ];
                    }
                }
                when ( /j/ ) {
                    $record->append( MARC::Moose::Field::Std->new(
                        tag => '265', subf => [ a => $value ] ) );
                }
                when ( /k/ ) {
                    $record->append( MARC::Moose::Field::Std->new(
                        tag => '265', ind1 => '0', ind2 => '0',
                        subf => [ a => $value ] ) );
                }
                when ( /l/ ) {
                    $record->append( MARC::Moose::Field::Std->new(
                        tag => '265', ind1 => '1', ind2 => '0',
                        subf => [ [  a => $value ] ] ) );
                }
                when ( /m/ ) {
                    $record->append( MARC::Moose::Field::Std->new(
                        tag => '265', ind1 => '2', ind2 => '0',
                        subf => [ a => $value ] ) );
                }
            }
        }
        next unless @sf;
        # Ponctuation
        for (my $i=0; $i < @sf; $i++) {
            my ($letter, $value) = @{$sf[$i]};
            given ($letter) {
                when ( /a/ ) {
                    $sf[$i-1]->[1] .= ' ;'  if $i;
                }
                when ( /b|f/ ) {
                    $sf[$i-1]->[1] .= ' :'  if $i;
                }
                when ( /c|g/ ) {
                    $sf[$i-1]->[1] .= ','  if $i;
                }
            }
            $value = "($value)" if $letter =~ /e|f|g/;
            if ( $value =~ /^= / ) {
                $value =~ s/^= //;
                $sf[$i-1]->[1] .= ' ='  if $i;
            }
            $sf[$i]->[1] = $value;
        }
        $sf[-1][1] = $sf[-1][1] . '.' if @sf && $sf[-1][1] !~ /\.$/;
        $record->append( MARC::Moose::Field::Std->new( tag => '260', subf => \@sf ) );
    }

    # TODO 211 => 263

    # 215 => 300
    for my $field ( $unimarc->field('215') ) {
        my @sf;
        for ( @{$field->subf} ) {
            my ($letter, $value) = @$_;
            $value =~ s/^ *//, $value =~ s/ *$//;
            given ($letter) {
                when ( /c/ ) { $letter = 'b'; }
                when ( /d/ ) { $letter = 'c'; }
                when ( /6|7/ ) { next; }
            }
            push @sf, [ $letter => $value ];
        }
        next unless @sf;
        # Ponctuation
        for (my $i=1; $i < @sf; $i++) {
            my ($letter, $value) = @{$sf[$i]};
            given ($letter) {
                when ( /b/ ) { $sf[$i-1]->[1] .= ' :'; }
                when ( /c/ ) { $sf[$i-1]->[1] .= ' ;'; }
                when ( /e/ ) { $sf[$i-1]->[1] .= ' + '; }
            }
        }
        $sf[-1][1] = $sf[-1][1] . '.' if $sf[-1][1] !~ /\.$/;
        $record->append( MARC::Moose::Field::Std->new( tag => '300', subf => \@sf ) );
    }

    # 225 => 490
    for my $field ( $unimarc->field('225') ) {
        my (@sf, @a, @vx);
        my $prev_letter = '';
        for ( @{$field->subf} ) {
            my ($letter, $value) = @$_;
            $value =~ s/^ *//, $value =~ s/ *$//;
            $value =~ s/\x88//g, $value =~ s/\x89//;
            given ($letter) {
                when ( /a/ ) { push @a, $value; }
                when ( /d/ ) { push @a, " = $value" }
                when ( /e/ ) { push @a, " : $value" }
                when ( /f/ ) { push @a, " / $value" }
                when ( /h/ ) { push @a, ". $value" }
                when ( /i/ ) {
                    push @a, $prev_letter eq 'h' ? ", $value " : ". $value";
                }
                when ( /v|x/ ) { push @vx, [ $letter => $value ] }
            }
            $prev_letter = $letter;
        }
        next unless @a;
        push @sf, [ a => join('', @a) ];
        push @sf, @vx;
        $record->append( MARC::Moose::Field::Std->new(
            tag => '490',
            ind1 => $field->ind1 =~ /0|2/ ? 1 : 0,
            subf => \@sf ) );
    }

    # 230 => 256
    for my $field ( $unimarc->field('230') ) {
        $record->append($field->clone('256'));
    }

    # Unchanged fields
    for my $fromto ( @unchanged ) {
        my ($from, $to) = @$fromto;
        for my $field ( $unimarc->field($from) ) {
            $record->append($field->clone($to));
        }
    }

    # 325 => 533
    for my $field ( $unimarc->field('325') ) {
        $record->append( MARC::Moose::Field::Std->new(
            tag => '533',
            subf => [ [ n => $field->subfield('a') ] ] ) );
    }

    # 326 => 533
    for my $field ( $unimarc->field('326') ) {
        # FIXME Should be done depending on biblio record type:
        # MAP, SERIALS
        my $type = 'SERIALS'; 
        my $new_field;
        given ($type) {
            when ( /SERIALS/ ) {
                $new_field = $field->clone('310');
            }
        }
        $record->append($new_field);
    }

    # 327 => 505
    for my $field ( $unimarc->field('327') ) {
        my $ind1 = $field->ind1;
        $ind1 = 0 if $ind1 =~ /1/;
        $ind1 = 1 if $ind1 =~ /0/;
        my @a = map { $_->[1] } @{$field->subf};
        $record->append( MARC::Moose::Field::Std->new(
            tag => '505', ind1 => $ind1,
            subf => [ [ a => join('  ', @a) ] ] ) );
    }

    # 336 => 500
    for my $field ( $unimarc->field('336') ) {
        $record->append( MARC::Moose::Field::Std->new(
            tag => '500',
            subf => [ [ a => 'Type of computer file: ' . $field->subfield('a') ] ] ) );
    }

    # 345 => 037
    for my $field ( $unimarc->field('345') ) {
        my @sf;
        for ( @{$field->subf} ) {
            my ($letter, $value) = @$_;
            $letter = $letter eq 'a' ? 'b' :
                      $letter eq 'b' ? 'a' :
                      $letter eq 'c' ? 'f' :
                      $letter eq 'd' ? 'c' : $letter;
            push @sf, [ $letter => $value ];
        }
        $record->append( MARC::Moose::Field::Std->new(
            tag => '037', subf => \@sf ) );
    }

    # TODO 410 411 421 422 423 430 431 432 433 434 435 436 437 440 441 442 443
    # 444 445 446 447 448 451 452 453

    # 454 => 765
    for my $ft ( (
        [410, 760],
        [411, 762],
        [421, 770],
        [422, 772],
        [423, 777],
        [430, 780, 0],
        [431, 780, 1],
        [432, 780, 2],
        [433, 780, 3],
        [434, 780, 5],
        [435, 780, 6],
        [436, 780, 4],
        [437, 780, 7],
        [440, 785, 0],
        [441, 785, 1],
        [442, 785, 2],
        [443, 785, 3],
        [444, 785, 4],
        [445, 785, 5],
        [446, 785, 6],
        [447, 785, 7],
        [448, 785, 8],
        [451, 775],
        [452, 776],
        [453, 767],
        [454, 765],
        [455, 787, 8, 'Reproduction of:'],
        [456, 787, 8, 'Reproduced as:'],
        [461, 774],
        [462, 774],
        [463, 773],
        [464, 774],
        [470, 787, 8, 'Item reviewed:'],
        [488, 787, 8, 'Reproduced as:'],
        [491, 774],
    ) ) {
        my ($from, $to, $ind2, $text) = @$ft;
        $ind2 = ' ' unless $ind2;
        for my $field ( $unimarc->field($from) ) {
            my @sf;
            push @sf, [ i => $text ] if $text;
            for ( @{$field->subf} ) {
                my ($letter, $value) = @$_;
                if ( $letter eq 't') {
                    $value =~ s/\x{0088}//g;
                    $value =~ s/\x{0089}//g;
                }
                $letter = $letter eq '1' ? 'a' :
                          $letter eq '3' ? 'w' :
                          $letter eq 'v' ? 'g' :
                          $letter eq 'y' ? 'z' : $letter;
                push @sf, [ $letter => $value ];
            }
            my $ind1 = $field->ind2 =~ /0/ ? 1 : 0;
            $record->append( MARC::Moose::Field::Std->new(
                tag => $to, ind1 => $ind1, ind2 =>$ind2, subf => \@sf ) );
        }
    }

    # 545 => 773, on passe t en a
    for my $field ( $unimarc->field('545') ) {
        $field->tag('773');
        $field->subf( [ grep { $_->[0] = 't' if $_->[0] eq 'a'; $_ } @{$field->subf} ] );
        $record->append( $field );
    }

    # 600 => 600
    # Suppr 6 et 7. f => d
    for my $field ( $unimarc->field('600') ) {
        my @names;
        my $date;
        for ( @{$field->subf} ) {
            my ($letter, $value) = @$_;
            $value =~ s/^ *//; $value =~ s/ *$//;
            next unless $value;
            given ($letter) {
                when ( /6|7/ ) { next; }
                when ( /a|b/ ) { push @names, $value; }
                when ( /f/   ) { $date = $value; }
            }
        }
        if (@names) {
            my @sf = ( [ a => join(', ', @names) . ($date ? ',' : '') ] );
            push @sf, [ d => $date ] if $date;
            $record->append( MARC::Moose::Field::Std->new(
                tag => '600', subf => \@sf ) );
        }
    }

    # 605 => 630 - 606 => 650 - 607 => 651 - 608 => 650
    # On conserve à leur place les lettres a x j (subdivision de forme)
    # On inverse y et z. et déplacée en v.
    # On suppr les $3
    for my $fromto ( ( [605, 630], [606, 650], [607, 651], [608, 650] ) ) {
        my ($from, $to) = @$fromto;
        for my $field ( $unimarc->field($from) ) {
            my @sf;
            for ( @{$field->subf} ) {
                my ($letter, $value) = @$_;
                $value =~ s/^ *//, $value =~ s/ *$//;
                next if $letter =~ /3/;
                if ( $letter eq 'j' ) {
                    $letter = 'v';
                }
                elsif ( $letter eq 'y' ) {
                    $letter = 'z';
                }
                elsif ( $letter eq 'z' ) {
                    $letter = 'y';
                }
                push @sf, [ $letter => $value ];
            }
            next unless @sf;
            $sf[-1][1] = $sf[-1][1] . '.' if $sf[-1][1] !~ /\.$/;
            $record->append( MARC::Moose::Field::Std->new(
                tag => $to, subf => \@sf ) );
        }
    }


    # 676 => 082, $v => $2
    for my $field ( $unimarc->field('676') ) {
        my @sf = map { $_->[0] = '2' if $_->[0] eq 'v'; $_; } @{$field->subf};
        $record->append( MARC::Moose::Field::Std->new(  
            tag => '082', subf => \@sf ) );
    }

    # Les auteurs 700 => 100, 
    # Suppr sous $3, $6 et $7 $9
    for my $fromto ( ( [700, 100], [701, 700], [702, 700] ) ) {
        my ($from, $to) = @$fromto;
        for my $field ( $unimarc->field($from) ) {
            my $ind1 = $field->ind2;
            my @sf;
            my @codes;
            for ( @{$field->subf} ) {
                my ($letter, $value) = @$_;
                given ($letter) {
                    when ( 'a' ) {
                        push @sf, [ a => $value ];
                    }
                    when ( 'b' ) {
                        if ( @sf ) {
                            $sf[-1]->[1] .= ", $value";
                        }
                        else {
                            push @sf, [ a => $value ];
                        }
                    }
                    when ( 'c' ) {
                        $sf[-1]->[1] .= ',';
                        push @sf, [ c => $value ];
                    }
                    when ( 'd' ) {
                        push @sf, [ b => $value ];
                    }
                    when ( 'f' ) {
                        $sf[-1]->[1] .= ',' if @sf;
                        push @sf, [ d => $value ];
                    }
                    when ( 'g' ) {
                        $sf[-1]->[1] .= '(';
                        push @sf, [ q => "$value)" ];
                    }
                    when ( '4' ) {
                        next if $from eq '700' && $value eq '070';
                        my $code = $authcode{$value};
                        next unless $code;
                        push @codes, $code->[0];
                    }
                }
            }
            next unless @sf;
            my $value = $sf[-1]->[1];
            $value =~ s/ *$//;
            $value =~ s/\.*$//;
            $value .= '.' if $value !~ /[-\?]$/;
            $sf[-1]->[1] = $value;
            push @sf, [ 4 => $_ ] for @codes;
            $record->append( MARC::Moose::Field::Std->new(
                tag => $to, ind1 => $field->ind2, subf => \@sf ) );
        }
    }

    # Les collectivités 
    # Suppr sous $3, $6 et $7 $9
    for my $fromto ( ( [710, 110, 111], [711, 710, 711], [712, 710, 711] ) ) {
        my ($from, $to_corporate, $to_meeting) = @$fromto;
        for my $field ( $unimarc->field($from) ) {
            my @sf;
            my @codes;
            for ( @{$field->subf} ) {
                my ($letter, $value) = @$_;
                given ($letter) {
                    when ( 'a' ) {
                        push @sf, [ a => $value ];
                    }
                    when ( 'g' ) {
                        $value = "($value)" unless $value =~ /^\(/;
                        $sf[-1]->[1] .= " $value" if @sf;
                    }
                    when ( 'h' ) {
                        $sf[-1]->[1] .= " $value";
                    }
                    when ( 'g' ) {
                        $sf[-1]->[1] .= " ($value)";
                    }
                    when ( 'b' ) {
                        if ( @sf ) {
                            $sf[-1]->[1] .= '.' unless  $sf[-1]->[1] =~ /\.$/;
                        }
                        push @sf, [ b => $value ];
                    }
                    when ( 'd' ) {
                        $value = "($value" unless $value =~ /^\(/;
                        push @sf, [ n => $value ];
                    }
                    when ( 'e' ) {
                        $value = " :$value)";
                        push @sf, [ c => $value ];
                    }
                    when ( 'f' ) {
                        $value = $sf[-1]->[0] eq 'n'
                                 ? " :$value"
                                 : "($value" if @sf;
                        push @sf, [ d => $value ];
                    }
                    when ( '4' ) {
                        next if $from eq '700' && $value eq '070';
                        my $code = $authcode{$value};
                        next unless $code;
                        push @codes, $code->[0];
                    }
                }
            }
            next unless @sf;
            my $value = $sf[-1]->[1];
            $value =~ s/ *$//;
            $value =~ s/\.*$//;
            $value .= '.';
            $sf[-1]->[1] = $value;
            push @sf, [ 4 => $_ ] for @codes;
            my $to = $field->ind1 eq '1' ? $to_meeting : $to_corporate;
            $record->append( MARC::Moose::Field::Std->new(
                tag => $to, ind1 => $field->ind2, subf => \@sf ) );
        }
    }

    # 856: copied as it is
    if ( my @fields = $unimarc->field('856') ) {
        $record->append(@fields)
    }

    return $record;
};

__PACKAGE__->meta->make_immutable;

1;

=head1 SYNOPSYS

Read a UNIMARC ISO2709 file and dump it to STDOUT in text transformed into
MARC21:

 my $reader = MARC::Moose::Reader::File::Iso2709->new(
   file => 'biblio-unimarc.iso' );
 my $formater = MARC::Moose::Formater::UnimarcToMarc21->new();
 while ( my $unimarc = $reader->read() ) {
   my $marc21 = $formater->format($unimarc);
   print $marc21->as('Text');
 }

Same with shortcut:

 my $reader = MARC::Moose::Reader::File::Iso2709->new(
   file => 'biblio-unimarc.iso' );
 while ( my $unimarc = $reader->read() ) {
   print $unimarc->as('UnimarcToMarc21')->as('Text');
 }

Read a UNIMARC ISO2709 file and dump it to another ISO2709 file transformed
into MARC21:

 my $reader = MARC::Moose::Reader::File::Iso2709->new(
   file => 'biblio-unimarc.iso' );
 my $writer = MARC::Moose::Writer::File->new(
   file => 'biblio-marc21.iso',
   formater => MARC::Moose::Formater::Iso2709->new()
 );
 my $tomarc21 = MARC::Moose::Formater::UnimarcToMarc21->new();
 while ( my $unimarc = $reader->read() ) {
   $writer->write( $tomarc21->format($unimarc) );
 }


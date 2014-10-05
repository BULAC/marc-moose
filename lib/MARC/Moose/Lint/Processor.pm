package MARC::Moose::Lint::Processor;
# ABSTRACT: Processor to lint a biblio records file

use Moose;
use Modern::Perl;
use MARC::Moose::Reader::File::Iso2709;
use MARC::Moose::Writer;
use MARC::Moose::Lint::Checker;

extends 'AnyEvent::Processor';

=attr linter

A L<MARC::Moose::Lint::Checker> to be used to validate biblio record.

=cut
has lint => (is => 'rw', isa => 'MARC::Moose::Lint::Checker');


=attr file

The name of an ISO2709 file containing biblio records to control. When the
processor object is created with this attribute, other attributes are
automatically constructed: C<reader> as L<MARC::Moose::Reader::File::Iso2709>
object reading the file, C<writer_ok> and C<writer_bad> as
L<MARC::Moose::Writer> object with an ISO2709 formater writing to files named
F<file.ok> and F<file.bad>, and C<fh_log> as a L<IO::File>, writing a text file
named F<file.log>.

=cut
has file => (
    is => 'ro',
    isa => 'Str',
    trigger => sub {
        my ($self, $file) = @_;
        $self->reader( MARC::Moose::Reader::File::Iso2709->new(
            file => $file,
            parser => MARC::Moose::Parser::Iso2709->new( lint => $self->lint ) ) );
        $self->writer_ok( MARC::Moose::Writer->new(
            formater => MARC::Moose::Formater::Iso2709->new(),
            fh => IO::File->new("$file.ok", ">:encoding(utf8)")
        ) );
        $self->writer_bad( MARC::Moose::Writer->new(
            formater => MARC::Moose::Formater::Iso2709->new(),
            fh => IO::File->new("$file.bad", ">:encoding(utf8)")
        ) );
        $self->fh_log( IO::File->new("$file.log", ">:encoding(utf8)") );
    },
);


=attr cleaner

A L<MARC::Moose::Formater> which transform a L<MARC::Moose::Record> into
another L<MARC::Moose::Record>. Using a cleaner, it's possible to clean biblio
records before validating them.

=cut
has cleaner => (is => 'rw', isa => 'MARC::Moose::Formater');


=attr reader

A L<MARC::Moose::Reader> object from which biblio records are read.

=cut
has reader => (is => 'rw', isa => 'MARC::Moose::Reader' );


=attr writer_ok

A L<MARC::Moose::Writer> object in which valid biblio records are written.

=cut
has writer_ok => (is => 'rw', isa => 'MARC::Moose::Writer' );


=attr writer_bad

A L<MARC::Moose::Writer> object in which invalid biblio records are written.

=cut
has writer_bad => (is => 'rw', isa => 'MARC::Moose::Writer' );


=attr writer_bad

A L<IO::File> file handle which is used to write invalid biblio records with
generated warnings.

=cut
has fh_log => (is => 'rw', isa => 'IO::File');

has count_ok => (is => 'rw', isa => 'Int', default => 0);
has count_bad => (is => 'rw', isa => 'Int', default => 0);



sub process {
    my $self = shift;

    my $record = $self->reader->read();
    return unless $record;

    $record = $self->cleaner->format($record) if $self->cleaner;

    if ( my @result = $record->check() ) {
        $self->writer_bad->write($record);
        my $rectext = $record->as('Text');
        chop $rectext;
        my $fh = $self->fh_log;
        print $fh $rectext, '-' x 80, "\n", join("\n", @result), "\n\n";
        $self->count_bad( $self->count_bad + 1 );
    }
    else {
        $self->writer_ok->write($record);
        $self->count_ok( $self->count_ok + 1 );
    }
    $self->SUPER::process();
}


sub start_message {
    say "Start linting biblio records";
}


sub process_message {
    my $self = shift;
    say $self->count, " - OK ", $self->count_ok, " - BAD ", $self->count_bad;
}


sub end_message {
    my $self = shift;
    my $file = $self->file;
    say "Processed records: ", $self->count, "\n",
        "Valid records:     ", $self->count_ok, "\n",
        "Invalid records:   ", $self->count_bad, "\n",
        "Lint result files: $file.ok, $file.bad, $file.log", ;
}

__PACKAGE__->meta->make_immutable;

1;

=head1 SYNOPSYS

 package PeterCleaner;
 
 use Moose;
 
 extends 'MARC::Moose::Formater';
 
 override 'format' => sub {
     my ($self, $record) = @_;
 
     for my $field (@{$record->fields}) {
        # clean content
     }
     return $record;
 };
 
 package Main;
 
 my $processor = MARC::Moose::Lint::Processor->new(
     lint => MARC::Moose::Lint::Checker::RulesFile->new( file => 'unimarc.rules',
     file => 'biblio.mrc',
     cleaner => PeterCleaner->new(),
     verbose => 1,
 };
 $processor->run();

The above script validates an ISO2709 file named F<biblio.mrc> on a rules file
named F<unimarc.rules>. As a result, 3 files are created: (1)
F<biblio.mrc.ok>, an ISO2709 containing biblio records complying to the rules,
(2) F<biblio.mrc.bad> containing biblios violating the rules, and (3)
F<biblio.mrc.log> containing a textual representation of biblio records
violating the rules + a description of violated rules.

A more specific construction is also possible:

 my $lint => MARC::Moose::Lint::Checker::RulesFile->new( file => 'marc21.rules' );
 my $processor = MARC::Moose::Lint::Processor->new(
     reader => MARC::Moose::Reader::File::Marcxml->new(
         file => 'biblio.xml',
         parser => MARC::Moose::Parser::Marcxml->new( lint => $lint ),
     writer_ok => MARC::Moose::Writer->new(
         formater => MARC::Moose::Formater::Marcxml->new(),
         fh => IO::File->new('ok.xml', '>:encoding(utf8')
     ),
     writer_bad => MARC::Moose::Writer->new(
         formater => MARC::Moose::Formater::Marcxml->new(),
         fh => IO::File->new('bad.xml', '>:encoding(utf8'))
     ),
     fh_log => IO::File->new('warnings.log', '>:encoding(utf8')),
     verbose => 1,
 );
 $processor->run();


=head1 SEE ALSO

=for :list
* L<MARC::Moose>
* L<MARC::Moose::Lint::Checker>
* L<MARC::Moose::Lint::Checker::RulesFile>


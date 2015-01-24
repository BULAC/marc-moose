package MARC::Moose::Reader::File::Iso2709;
# ABSTRACT: File reader for MARC::Moose record from ISO2709 file

use Moose;
use Modern::Perl;
use MARC::Moose::Record;
use MARC::Moose::Parser::Iso2709;

with 'MARC::Moose::Reader::File';


has '+parser' => ( default => sub { MARC::Moose::Parser::Iso2709->new() } );


sub read {
    my $self = shift;

    $self->count( $self->count + 1);

    my $fh = $self->{fh};

    return if eof($fh);

    local $/ = "\x1D"; # End of record
    my $raw = <$fh>;

    # remove illegal garbage that sometimes occurs between records
    $raw =~ s/^[ \x00\x0a\x0d\x1a]+//;

    my $record = $self->parser->parse( $raw );
    return unless $record;
    $record->lint( $self->lint ) if $self->lint;
    return $record;
}


__PACKAGE__->meta->make_immutable;

1;


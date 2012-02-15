package MARC::Moose::Reader::File;
# ABSTRACT: A reader from a file

use Moose;

use Carp;
use MARC::Moose::Record;

extends 'MARC::Moose::Reader';

=attr file

Name of the file to read MARC::Moose::Record from. A error is thrown if the file
does't exist. Setting this attribute will set L<fh> attribute

=cut

has file => (
    is => 'rw',
    isa => 'Str',
    trigger => sub {
        my ($self, $file) = @_; 
        unless ( -e $file ) { 
            croak "File doesn't exist: " . $file;
        }   
        $self->{file} = $file;
        open my $fh, '<',$self->file
             or croak "Impossible to open file: " . $self->file;
        $self->fh($fh);
    }   
);


=attr fh

File handle form which reading records.

=cut

has fh => ( is => 'rw' );


sub read {
    my $self = shift;
    $self->SUPER::read();
}

__PACKAGE__->meta->make_immutable;

1;

=head1 SEE ALSO

=for :list
* L<MARC::Moose>
* L<MARC::Moose::Reader>

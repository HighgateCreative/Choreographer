package Dancer::Choreographer::Crew;
use Moo;

use strict;
use warnings;

has cpanfile => (is => 'rw');

# Do everything a standard Choreographer App should have
sub init {
   my $self = shift;
}

1;

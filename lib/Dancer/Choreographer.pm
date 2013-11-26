package Dancer::Choreographer;

use strict;
use warnings;

use 5.008_005;
use version; our $VERSION = version->declare("0.01");

use JSON;

sub choreograph {
   my $json = shift;
   my $params = from_json($json);
}

1;
__END__

=encoding utf-8

=head1 NAME

Dancer::Choreographer - Blah blah blah

=head1 SYNOPSIS

  use Dancer::Choreographer;

=head1 DESCRIPTION

Dancer::Choreographer is

=head1 AUTHOR

Sean Zellmer E<lt>sean@lejeunerenard.comE<gt>

=head1 COPYRIGHT

Copyright 2013 Sean Zellmer

=head1 LICENSE

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 SEE ALSO

=cut

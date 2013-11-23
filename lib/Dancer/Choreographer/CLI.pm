package Dancer::Choreographer::CLI;
use Moo;

use Dancer;

use Term::ANSIColor qw(:constants);
use Getopt::Long;
use Try::Tiny;

Getopt::Long::Configure('bundling');

sub run {
   my($self, @args) = @_;

   my @commands;

   my $p = Getopt::Long::Parser->new(
      config => [ 'no_ignore_case', 'pass_through' ],
   );

   $p->getoptionsfromarray(
      \@args,
      "h|help"    => sub { unshift @commands, 'help' },
      "v|version" => sub { unshift @commands, 'version' },
   );

   push @commands, @args;

   my $cmd = shift @commands || 'init';   # Get Command or set default

   my $code = try {
      my $call = $self->can("cmd_$cmd")
         or die "Could not find command '$cmd'";
      $self->$call(@commands);
      return 0;
   } catch {
      die $_ unless blessed $_ && $_->can('rethrow'); # @TODO Figure out if I should use Throwable or Exception::Class
   };

   return $code;
}

# Brilliant piece of Code by Tatsuhiko Miyagawa
sub commands {
    my $self = shift;

    no strict 'refs';
    map { s/^cmd_//; $_ }
        grep { /^cmd_.*/ && $self->can($_) } sort keys %{__PACKAGE__."::"};
}

# By Tatsuhiko Miyagawa
sub parse_options {
    my($self, $args, @spec) = @_;
    my $p = Getopt::Long::Parser->new(
        config => [ "no_auto_abbrev", "no_ignore_case" ],
    );
    $p->getoptionsfromarray($args, @spec);
}

sub cmd_install {
   # Create Dancer app
}



# @TODO Reintegrate the following code.
# There is no significance to the function "something" itself.

sub something {
   my $json_file = '';

   GetOptions( 'json|f=s', \$json_file )
   or die("Error in command line arguments\n");

   setting_the_stage();

   # Get json string;
   my $json = '';

   # If file exists slurp
   if (-f $json_file) {
      open my $json_fh, "<", $json_file or die $!;
      {
         local $/;
         $json = <$json_fh>;
      }
      close $json_fh;
   } else {
      $json = $json_file;
   }

   my $msgs = choreograph($json);


   if (@{ $msgs->{'success'} }) {
      #print "Success:\n";
      foreach my $msg ( @{ $msgs->{'success'} } ) {
         print GREEN, $msg."\n", RESET;
      }
   }
   if (@{ $msgs->{'errors'} }) {
      #print "Errors:\n";
      foreach my $msg ( @{ $msgs->{'errors'} } ) {
         print RED, $msg."\n", RESET;
      }
   }
   if (@{ $msgs->{'output'} }) {
      print "Output:\n";
      foreach my $msg ( @{ $msgs->{'output'} } ) {
         print $msg."\n";
      }
   }
}
1;

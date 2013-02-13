package Dancer::Choreographer;
use lib 'local/lib/perl5'; # TODO: Convert to local::lib

use strict;
use warnings;

use Exporter;
use vars qw($VERSION @ISA @EXPORT @EXPORT_OK);

$VERSION = 0.100;
@ISA = qw(Exporter);
@EXPORT = qw(choreograph);
@EXPORT_OK = qw(setup);

use PPI;
use JSON;
use File::Which;

use Data::Dumper;

#print Dumper(\%Config);
#use lib $Config{INSTALLSCRIPT};

sub setup {
   my $dancer_cmd_path;
   unless ($dancer_cmd_path = which('dancer')) {
      die "No dancer command was found. Install Dancer from CPAN with 'curl -L http://cpanmin.us | perl - --sudo Dancer'";
   }

   # Pull in all subs from dancer script
   my $Document = PPI::Document->new($dancer_cmd_path) or die "oops";
   for my $sub ( @{ $Document->find('PPI::Statement::Sub') || [] } ) {
       unless ( $sub->forward ) {
           my $sub_content = $sub->content;
           $sub_content =~ s/exit;//g; # Remove lines that will cause script to exit. Let the script decide itself.
           eval $sub_content;
       }
   }
}

sub choreograph {
   my $json = shift;
   my $params = from_json($json);

   setup();
   
   for my $i ( 0 .. $#$params ) {
      # Check if working with a module only or not
      if ($params->[$i]{'settings'}{'module_only'}) {
      } else {
         print "App Shit to be added later";
         if (eval "validate_app_name(\$params->[\$i]{'settings'}{'app_name'});") {
            # There is an error
         } else {
            # There isnt an error
         }
      }
   }
}
1;

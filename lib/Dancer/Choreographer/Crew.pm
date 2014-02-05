package Dancer::Choreographer::Crew;
use Moo;
use Git::Wrapper;
use Carton::CLI;
use Dancer::Choreographer::Producer;

has cpanfile => (is => 'rw');
has app_dir => (is => 'rw');
has app_name => (is => 'rw');

# Do everything a standard Choreographer App should have
sub init {
   my $self = shift;

   # Create Git
   my $git = Git::Wrapper->new($self->app_dir);

   print "Initializing Git...\n";
   $git->init();

   # Add submodules
   # @TODO Check if existing submodules are up-to-date and prompt to update if not
   print "Adding Git Submodules...\n";

   # Form Functions
   if (-e $self->app_dir.'/public/javascripts/form_functions') {
      print "Form Functions already exists. Skipping.\n";
   } else {
      $git->submodule( 'add', 'https://github.com/HighgateCross/Form-Functions.git', $self->app_dir.'/public/javascripts/form_functions' );
   }

   # Stagehand
   if (-e $self->app_dir.'/lib/Stagehand') {
      print "Stagehand already exists. Skipping.\n";
   } else {
      $git->submodule( 'add', 'https://github.com/HighgateCross/Stagehand.git', $self->app_dir.'/lib/Stagehand' );
   }

   # Malsup's Form
   if ( -e $self->app_dir.'/public/javascripts/form' ) {
      print "Malsup's Form already exists. Skipping.\n";
   } else {
      $git->submodule('add', 'https://github.com/malsup/form.git',$self->app_dir.'/public/javascripts/form');
   }

   # Makeup
   if ( -e $self->app_dir.'/public/css/makeup' ) {
      print "Makeup already exists. Skipping.\n";
   } else {
      $git->submodule( 'add', 'https://github.com/HighgateCross/Makeup.git', $self->app_dir.'/public/css/makeup' );
   }

   print "Creating share folder...\n";
   # Create migrations folder
   $self->app_dir->child('share')->mkpath;

   print "Creating documents folder...\n";
   # Create documents folder
   $self->app_dir->child('public/documents')->mkpath;

   # Create Reuqirements
   print "Creating cpanfile...\n";
   my $req;
   if ($self->cpanfile and $self->cpanfile->prereq_specs) {
      $req = CPAN::Meta::Requirements->from_string_hash($self->cpanfile->prereq_specs->{runtime}{requires});
   } else {
      $req = CPAN::Meta::Requirements->new();
   }
   $req->add_minimum('Dancer' => 0);
   $req->add_minimum('Dancer::Plugin::DBIC' => 0);
   $req->add_minimum('YAML' => 0);
   $req->add_minimum('Template' => 0);
   $req->add_minimum('HTML::TagFilter' => 0);
   $req->add_minimum('DBIx::Class::Validation::Structure' => 0);
   $req->add_minimum('HTML::FillInForm' => 0);
   
   # @TODO Make it so other phases arent clobbered
   # @TODO Support reading from other file formats for dependencies
   # Set new cpanfile
   $self->cpanfile(Module::CPANfile->from_prereqs({
      runtime => {
         requires => $req->as_string_hash,
      }
   }));

   # Save cpanfile
   $self->cpanfile->save($self->app_dir."/cpanfile");

   # Append to .gitignore
   print "Creating .gitignore...\n";
   open(GITIGN, ">> ".$self->app_dir."/.gitignore");
   print GITIGN ".carton\n"; 
   print GITIGN "local/\n"; 
   print GITIGN "*.sw[pqor]\n"; 
   close GITIGN;

   # Run Carton
   print "Running Carton...";

   my $carton = Carton::CLI->new; # Create a Carton instance
   # Check if Carton has already installed everything
   my $check = do {
      my $null;
      open(local *STDOUT, '>', \$null);   # This is to redirect the STDOUT of Carton. Noone wants to see that for a simple check.
      $carton->run('check','--cpanfile', $self->app_dir."/cpanfile");
   };

   if ($check) { # If some dependencies are missing, install them
      print "\n";
      $carton->run('install','--cpanfile', $self->app_dir."/cpanfile", '--path',$self->app_dir."/local");
      print "Done\n";
   } else {
      print " Skipped\n";
   }

   # Add use lib for local carton installed module
   print "Adding 'local/lib/perl5' to bin/app.pl... ";
   if ( not Dancer::Choreographer::Producer::match_in_file($self->app_dir."/bin/app.pl", 'local\/lib\/perl5') ) {
      open(my $bin_app, '<', $self->app_dir."/bin/app.pl") or warn "Unable to add lib dir to bin/app.pl : $!";
      (my $bin_app_content = join('', <$bin_app>)) =~ s/use Dancer;/use lib 'local\/lib\/perl5';\nuse Dancer;/i;
      open($bin_app, '>', $self->app_dir."/bin/app.pl") or warn "Unable to add lib dir to bin/app.pl : $!";
      print $bin_app $bin_app_content;
      close $bin_app;
      print "Done\n";
   } else {
      print "Skipped.\n";
   }

   print "Creating Schema package... ";
   # Check to see if Schema has been created
   if (-f $self->app_dir."/lib/".$self->app_name."/Schema.pm") {
      print "Skipped.";
   } else {
      Dancer::Choreographer::Producer::our_safe_mkdir($self->app_dir."/lib/".$self->app_name."/");
      Dancer::Choreographer::Producer::write_files( $self->app_dir."/lib/".$self->app_name."/Schema.pm",
"package ".$self->app_name."::Schema;

use strict;
use warnings;

use base 'DBIx::Class::Schema';

our \$VERSION = 1;

__PACKAGE__->load_namespaces;

1;");
      print "Done\n";
   }
}

1;

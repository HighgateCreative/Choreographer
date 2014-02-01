package Dancer::Choreographer::Crew;
use Moo;
use Git::Wrapper;
use Carton::CLI;

has cpanfile => (is => 'rw');
has app_dir => (is => 'rw');

# Do everything a standard Choreographer App should have
sub init {
   my $self = shift;

   # Create Git
   my $git = Git::Wrapper->new($self->app_dir);

   print "Initializing Git...\n";
   $git->init();

   # Add submodules
   print "Adding Git Submodules...\n";
   $git->submodule('add', 'https://github.com/HighgateCross/Form-Functions.git',$self->app_dir.'/public/javascripts/form_functions');
   # Shouldnt be necessary with DBIx::Class::Validation::Structure
   #$git->submodule('add', 'https://github.com/HighgateCross/Validate.git',$self->app_dir.'/lib/Validate');
   $git->submodule('add', 'https://github.com/HighgateCross/Stagehand.git',$self->app_dir.'/lib/Stagehand');
   $git->submodule('add', 'https://github.com/malsup/form.git',$self->app_dir.'/public/javascripts/form');
   $git->submodule('add', 'https://github.com/HighgateCross/Makeup.git',$self->app_dir.'/public/css/makeup');

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
   print "Running Carton...\n";

   Carton::CLI->new->run('install','--cpanfile', $self->app_dir."/cpanfile", '--path',$self->app_dir."/local");

   # Add use lib for local carton installed module
   print "Running Carton...\n";
   open(my $bin_app, '<', $self->app_dir."/bin/app.pl") or warn "Unable to add lib dir to bin/app.pl : $!";
   (my $bin_app_content = join('', <$bin_app>)) =~ s/use Dancer;/use lib 'local\/lib\/perl5';\nuse Dancer;/i;
   open($bin_app, '>', $self->app_dir."/bin/app.pl") or warn "Unable to add lib dir to bin/app.pl : $!";
   print $bin_app $bin_app_content;
   close $bin_app;
}

1;

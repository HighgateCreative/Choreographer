package Dancer::Choreographer::Environment;
use Moo;
use strict;
use warnings;

use Module::CPANfile;
use CPAN::Meta::Requirements;
use Path::Tiny;

has cpanfile => (is => 'rw');
has sequences => (is => 'rw'); # json file with the current definition for the Choreogrpaher app
has app_dir => (is => 'rw', lazy => 1, builder => 1, coerce => sub { Path::Tiny->new($_[0])->absolute });

sub _build_app_dir {
    my $self = shift;

    # Base App_dir first on the directory of 
    my $try = Path::Tiny->cwd->child('config.yml');

    if ($try->is_file) {
      return Path::Tiny->cwd;
    # else base it off the location of the cpanfile
    } elsif ($self->cpanfile) {
      return $self->cpanfile->dirname;
    } else {
      die "Could not determine app_dir";
    }
}

# Setup Environment
sub build {
   my($class, $app_dir, $cpanfile_path) = @_;

   # Create Moo object
   my $self = $class->new;

   # ----- Setup Carton file -----
   $cpanfile_path &&= Path::Tiny->new($cpanfile_path)->absolute;

   # Setup App Directory
   $self->app_dir($app_dir) if $app_dir;

   my $cpanfile = $self->locate_cpanfile($cpanfile_path);
   if ($cpanfile && $cpanfile->is_file) {
        $self->cpanfile( Module::CPANfile->load($cpanfile) );
   } else {
      if ( Path::Tiny->new($self->app_dir."/cpanfile")->is_file ) {
         $self->cpanfile( Module::CPANfile->load($self->app_dir."/cpanfile") );
      } else {
         $self->cpanfile( Module::CPANfile->from_prereqs() );
      }
   }

    $self;
}

sub locate_cpanfile {
    my($self, $path) = @_;

    if ($path) {
        return Path::Tiny->new($path)->absolute;
    }

    my $current  = Path::Tiny->cwd;
    my $previous = '';

    until ($current eq '/' or $current eq $previous) {
        my $try = $current->child('cpanfile');
        if ($try->is_file) {
            return $try->absolute;
        }

        ($previous, $current) = ($current, $current->parent);
    }

    return;
}
1;

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

   my $return;
   
   for my $i ( 0 .. $#$params ) {
      if (eval "validate_app_name(\$params->[\$i]{'settings'}{'app_name'});") {
         die "Try a new app name.";
      }
      # Check if working with a module only or not
      if ($params->[$i]{'settings'}{'module_only'}) {
         my $msgs = create_models(  models      => $params->[$i]{'models'},
                                    app_name    => $params->[$i]{'settings'}{'app_name'},
                                    app_path    => $params->[$i]{'settings'}{'app_path'},
                                    write_files => $params->[$i]{'settings'}{'write_files'},
                                    overwrite   => $params->[$i]{'settings'}{'overwrite'},
                                 );
         $return = $msgs;
      } else {
         print "App Shit to be added later";
      }
   }

   return $return;
}

# ===== Models Preprocessing =====
sub model_preprocessing {
   my %options = @_;
   my $models = ($options{'models'}) ? $options{'models'} : undef;
   
   for my $i ( 0 .. $#$models ) {
      for my $j ( 0 .. $#{$models->[$i]{'attributes'}} ) {
         my $unreadable_label = lc $models->[$i]{'attributes'}[$j]{'label'};
         $unreadable_label =~ s/ /_/g;
         $models->[$i]{'attributes'}[$j]{'label_unreadable'} = $unreadable_label;
      }
   }

   return $models;
}

# ===== Create Models =====
# 3 components: Schema (model), controller and templates (views)
sub create_models {
   my %options = @_;
   my $models = ($options{'models'}) ? $options{'models'} : undef;
   my $app_path = ($options{'app_path'}) ? $options{'app_path'} : undef;
   my $app_name = ($options{'app_name'}) ? $options{'app_name'} : undef;
   my $write_files = ($options{'write_files'}) ? 1 : 0;
   my $overwrite = ($options{'overwrite'}) ? 1 : 0;

   # Errors
   die "Models are required to create models. Duh." unless defined $models;

   my $return->{'output'} = [];
   $return->{'success'} = [];
   $return->{'errors'} = [];

   $models = model_preprocessing( models => $models );

   my $schema_result = create_model_schemas(    models      => $models,
                                                app_path    => $app_path,
                                                app_name    => $app_name,
                                                write_files => $write_files,
                                                overwrite   => $overwrite,
                                           );
   if (ref($schema_result) eq 'ARRAY') {
      push @{ $return->{'success'} }, "Schema(s) successfully printed.";
      @{ $return->{'output'} } = ( @{$return->{'output'}}, @$schema_result );
   } elsif ($schema_result) {
      push @{ $return->{'success'} }, "Schema(s) successfully created.";
   } else {
      push @{ $return->{'errors'} }, "Creating Schema(s) failed.";
   }

   return $return;
}

# ----- Create Models Schemas -----
sub create_model_schemas {
   my %options = @_;
   my $models = ($options{'models'}) ? $options{'models'} : undef;
   my $app_path = ($options{'app_path'}) ? $options{'app_path'} : undef;
   my $app_name = ($options{'app_name'}) ? $options{'app_name'} : undef;
   my $write_files = ($options{'write_files'}) ? 1 : 0;
   my $overwrite = ($options{'overwrite'}) ? 1 : 0;

   # Errors
   die "Models are required to create model schemas." unless defined $models;

   # Set return to 1 (success) if writing to files
   my $return = ($write_files && $app_path && $app_name) ? 1 : undef;

   # Hard Coded for now. Eventually adding columns will be a plugin system. 
   my %data_types = (
      text           => 'varchar',
      email          => 'varchar',
      textarea       => 'text',
      checkbox       => 'integer',
      select         => 'varchar',
      datepicker     => 'date',
      tinymce        => 'text',
      sessionvarible => 'integer',
      radio          => 'varchar',
   );

   # TODO: check and create folders such as lib/app_name/Schema/Result

   for my $i ( 0 .. $#$models ) {
      my $result_name = join "_", map {ucfirst} split / /, $models->[$i]{'table_name'}; #Uppercase first letter of every word and replace spaces with underscores.

      # ----- Generate schema pm text -----
      my $schema =
"package $app_name\::Schema::Result::$result_name;

use strict;
use warnings;

use base 'DBIx::Class::Core';

__PACKAGE__->table('$models->[$i]{'table_name'}');
__PACKAGE__->add_columns(
   'id' => {
      data_type => 'integer',
      is_auto_increment => 1,
   },
";
      # Loop through model attributes adding column info
      for my $j ( 0 .. $#{ $models->[$i]{'attributes'} } ) {
         my $data_type = $data_types{ $models->[$i]{'attributes'}[$j]{'type'} };
         $schema .=
"   '$models->[$i]{'attributes'}[$j]{'label_unreadable'}' => {
      data_type => '$data_type',
      size => '$models->[$i]{'attributes'}[$j]{'max_length'}',
   },
";
      }
      $schema .=
"); 

__PACKAGE__->set_primary_key('id');

# Relationships go here

1;
";
      if ( $write_files && $app_path && $app_name && $schema ) {
         $app_name =~ s{::}{/}g; # Convert app name to file path
         if ( not write_files($app_path."/lib/".$app_name."/Schema/Result/$result_name.pm", $schema, $overwrite) ) {
            $return = 0;
         }
      } else {
         push @$return, $schema;
      }
   }
   return $return;
      }

sub write_files {
   my ($file, $content, $DO_OVERWRITE_ALL) = @_;

   # if file already exists and overwrite not set
   if (-f $file && (not $DO_OVERWRITE_ALL)) {
      return 0;
   } else {
      my $fh;
      open $fh, '>', $file or die "unable to open file `$file' for writing: $!";
      print $fh $content;
      close $fh;
   }
}
1;

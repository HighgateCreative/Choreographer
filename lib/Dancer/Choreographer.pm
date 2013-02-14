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

   my $views_results = create_model_views(  models      => $models,
                        app_path    => $app_path,
                        app_name    => $app_name,
                        write_files => $write_files,
                        overwrite   => $overwrite,
                     );
   if (ref($views_results) eq 'ARRAY') {
      push @{ $return->{'success'} }, "Views successfully printed.";
      @{ $return->{'output'} } = ( @{$return->{'output'}}, @$views_results );
   } elsif ($views_results) {
      push @{ $return->{'success'} }, "Views successfully created.";
   } else {
      push @{ $return->{'errors'} }, "Creating Views failed.";
   }

   create_model_controllers(  models      => $models,
                              app_path    => $app_path,
                              app_name    => $app_name,
                              write_files => $write_files,
                              overwrite   => $overwrite,
                           );

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

# ----- Create Models Schemas -----
sub create_model_views {
   my %options = @_;
   my $models = ($options{'models'}) ? $options{'models'} : undef;
   my $app_path = ($options{'app_path'}) ? $options{'app_path'} : undef;
   my $app_name = ($options{'app_name'}) ? $options{'app_name'} : undef;
   my $write_files = ($options{'write_files'}) ? 1 : 0;
   my $overwrite = ($options{'overwrite'}) ? 1 : 0;

   # Errors
   die "Models are required to create model views." unless defined $models;

   # Set return to 1 (success) if writing to files
   my $return = ($write_files && $app_path && $app_name) ? 1 : undef;

   # TODO: Check for general folders like views/models

   for my $i ( 0 .. $#$models ) {
      my $model_name = join "_", split / /, $models->[$i]{'table_name'}; #Uppercase first letter of every word and replace spaces with underscores.

      # TODO: Check for model specific folder like views/models/artists

      my $list_template = create_model_list_view( model => $models->[$i] );

      if ( $write_files && $app_path && $app_name && $list_template ) {
         if ( not write_files($app_path."/views/".$model_name."/".$model_name."_list.tt", $list_template, $overwrite) ) {
            $return = 0;
         }
      } else {
         push @$return, $list_template;
      }

      my $edit_template = create_model_edit_view( model => $models->[$i] );

      if ( $write_files && $app_path && $app_name && $edit_template ) {
         if ( not write_files($app_path."/views/".$model_name."/".$model_name."_edit.tt", $edit_template, $overwrite) ) {
            $return = 0;
         }
      } else {
         push @$return, $edit_template;
      }

      my $read_template = create_model_read_view( model => $models->[$i] );

      if ( $write_files && $app_path && $app_name && $read_template ) {
         if ( not write_files($app_path."/views/".$model_name."/".$model_name."_read.tt", $read_template, $overwrite) ) {
            $return = 0;
         }
      } else {
         push @$return, $read_template;
      }
   }
   return $return;
}

# ----- Create Model list view -----
sub create_model_list_view {
   my %options = @_;
   my $model = ($options{'model'}) ? $options{'model'} : undef;

   # Errors
   die "A Model is required to create a list view." unless defined $model;
   
   my $model_name = join "_", split / /, $model->{'table_name'}; #Uppercase first letter of every word and replace spaces with underscores.

   my $template =
"<% IF ".$model_name."s.size %>
    <table>
      <tr>
         <th></th>
";
   for my $i ( 0 .. $#{$model->{'attributes'}} ) {
      $template .=
"         <th>$model->{'attributes'}[$i]{'label'}</th>
";
   }
   $template .=
"</tr>
    <% FOREACH $model_name IN ".$model_name."s %>
      <tr>
         <td><a href='/".$model_name."s/<% $model_name.id %>'>View</a> <a href='/".$model_name."s/edit/<% $model_name.id %>'>Edit</a></td>
";
   for my $i ( 0 .. $#{$model->{'attributes'}} ) {
      $template .=
"         <td><% $model_name.$model->{'attributes'}[$i]{'label_unreadable'} %></td>
";
   }
   $template .=
"      </tr>
    <% END %>
    </table>
  <% ELSE %>
    <p>No results found</p>
  <% END %>
   <a href='/".$model_name."s/add'>Add a $model->{'readable_name'}</a>&nbsp;<a href='<% dashboard %>'>Dasbhoard</a>
";
   return $template;
}

# ----- Create Model add/edit view -----
sub create_model_edit_view {
   my %options = @_;
   my $model = ($options{'model'}) ? $options{'model'} : undef;

   # Errors
   die "A Model is required to create a list view." unless defined $model;
   
   my $model_name = join "_", split / /, $model->{'table_name'}; #Uppercase first letter of every word and replace spaces with underscores.

   my $template_whole =
"<div id='msgs'></div>
<form id='".$model_name."_form' action='/".$model_name."s' method=''>
   <input type='hidden' name='id' value='' />";
   for my $i ( 0 .. $#{$model->{'attributes'}} ) {
      my @label_classes;
      push @label_classes, ($model->{'attributes'}[$i]{'mandatory'}) ? "blabel" : "label";
      my $astk = ($model->{'attributes'}[$i]{'mandatory'}) ? "*" :"";

      my $template .= "
   <p class='wrap'>";
      # Add label for majority of field types
      if (not ( $model->{'attributes'}[$i]{'type'} eq 'checkox' ) ) {
         $template .= "
      <label for='$model->{'attributes'}[$i]{'label_unreadable'}' class='".join(' ',@label_classes)."'>$model->{'attributes'}[$i]{'label'}$astk</label>";

         # Add static label
         if ($model->{'attributes'}[$i]{'static_label'}) {
            $template .= "
         <label for='$model->{'attributes'}[$i]{'label_unreadable'}' class='".join(' ',@label_classes)."'>$model->{'attributes'}[$i]{'label'}</label>";
         }
      }

      # == Output fields based on type ==
      # -- Email --
      if ($model->{'attributes'}[$i]{'type'} eq 'email') {
         $template .= "
      <input type='email' name='$model->{'attributes'}[$i]{'label_unreadable'}' value='' maxlength='$model->{'attributes'}[$i]{'max_length'}' />";

      # -- Text Area --
      } elsif ($model->{'attributes'}[$i]{'type'} eq 'textarea') {
         $template .= "
      <textarea name='$model->{'attributes'}[$i]{'label_unreadable'}' id='$model->{'attributes'}[$i]{'label_unreadable'}' class='counter count_down' size='$model->{'attributes'}[$i]{'max_length'}' />
      <input type='text' size='4' readonly='readonly' class='counter' value='$model->{'attributes'}[$i]{'max_length'}' />";
      # -- Select --
      } elsif ($model->{'attributes'}[$i]{'type'} eq 'select') {
         $template .= "
      <select name='$model->{'attributes'}[$i]{'label_unreadable'}' id='$model->{'attributes'}[$i]{'label_unreadable'}'>
         <option value=''>Select...</option>";
         for my $j ( 0 .. $#{$model->{'attributes'}[$i]{'options'}} ) {
            $template .= "
         <option value='$model->{'attributes'}[$i]{'options'}[$j]'>$model->{'attributes'}[$i]{'options'}[$j]</option>";
         }
         $template .= "
      </select>";
      # -- Radio buttons --
      } elsif ($model->{'attributes'}[$i]{'type'} eq 'radio') {
         for my $j ( 0 .. $#{$model->{'attributes'}[$i]{'options'}} ) {
            $template .= "
         <input type='radio' name='$model->{'attributes'}[$i]{'label_unreadable'}' value='$model->{'attributes'}[$i]{'options'}[$j]'/> $model->{'attributes'}[$i]{'options'}[$j]";
         }
      # -- Checkbox --
      } elsif ($model->{'attributes'}[$i]{'type'} eq 'checkbox') {
         $template .= "
      <input type='checkbox' id='$model->{'attributes'}[$i]{'label_unreadable'}' name='$model->{'attributes'}[$i]{'label_unreadable'}' value='$model->{'attributes'}[$i]{'label_unreadable'}' class='check' /> <label for='$model->{'attributes'}[$i]{'label_unreadable'}' class='".join(' ',@label_classes)." nextto'>$model->{'attributes'}[$i]{'label'}$astk</label>";
         if ($model->{'attributes'}[$i]{'static_label'}) {
            $template .= "
               <label for='$model->{'attributes'}[$i]{'label_unreadable'}' class='".join(' ',@label_classes)." static_label nextto'></label>";
         }
      # -- File Uploads --
      } elsif ($model->{'attributes'}[$i]{'type'} eq 'file') {
         $template = "
            <!-- add to form tag:  enctype='multipart/form-data'-->
      <% IF $model_name.$model->{'attributes'}[$i]{'label_unreadable'} %>
         <p class='wrap'>
            <label for='server_image' class='label'>Existing</label>
            <input type='text' name='$model->{'attributes'}[$i]{'label_unreadable'}' value='' id='$model->{'attributes'}[$i]{'label_unreadable'}' readonly='readonly' /> OR...
         </p>
      <% END %>" . $template;
         $template .= "
      <input type='file' name='$model->{'attributes'}[$i]{'label_unreadable'}' value='' id='$model->{'attributes'}[$i]{'label_unreadable'}' /><!-- don't forget: enctype='multipart/form-data' -->";      
      # -- Datepicker --
      } elsif ($model->{'attributes'}[$i]{'type'} eq 'date_picker') {
         $template .= "
      <input type='text' class='date_picker' name='$model->{'attributes'}[$i]{'label_unreadable'}' value='' maxlength='$model->{'attributes'}[$i]{'max_length'}' />";
      # -- Text field --
      } else {
         $template .= "
      <input type='text' name='$model->{'attributes'}[$i]{'label_unreadable'}' value='' maxlength='$model->{'attributes'}[$i]{'max_length'}' />";
      }
      $template .="
   </p>";
      # Add field to overall template
      $template_whole .= $template;
   }
   $template_whole .= "
   <p>
      <input type='submit' value='<% IF ".$model_name.".id %>Update<% ELSE %>Save<% END %>' />
      <% IF ".$model_name.".id %><a href='/".$model_name."s/delete/<% ".$model_name.".id %>'>Delete</a><% END %>
      <a href='/".$model_name."s/'>Back to List</a>
   </p>
</form>
<script type='text/javascript'>
   \$(function() {
      \$('#".$model_name."_form').ajaxForm({
         url: '/".$model_name."s',
         type: '<% IF $model_name.id %>PUT<% ELSE %>POST<% END %>',
         datatype: 'json',
         beforeSubmit: function() {
            normalize_labels(\$('#".$model_name."_form'));
         },
         //data: \$(this).serialize(),
         success: function(result) {
            console.log(result);
            parse_results({
               result: result,
               form: '".$model_name."_form',
               msgdiv: 'msgs',
               success: function(result) {
               }
            });
         }
      });
   });
</script>
";
   return $template_whole;
}

# ----- Create Model read view -----
sub create_model_read_view {
   my %options = @_;
   my $model = ($options{'model'}) ? $options{'model'} : undef;

   # Errors
   die "A Model is required to create a read view." unless defined $model;
   
   my $model_name = join "_", split / /, $model->{'table_name'}; #Uppercase first letter of every word and replace spaces with underscores.

   my $template = '';
   for my $i ( 0 .. $#{$model->{'attributes'}} ) {
      $template .= "
   <p class='wrap'>";
      # Add label for majority of field types
      $template .= "
   <label for='$model->{'attributes'}[$i]{'label_unreadable'}'>$model->{'attributes'}[$i]{'label'}</label>";

      # == Output fields based on type ==
      # -- Email --
      if ($model->{'attributes'}[$i]{'type'} eq 'checkbox') {
         $template .= "
      <% IF $model_name.$model->{'attributes'}[$i]{'label_unreadable'} %>Yes<% ELSE %>No<% END %>";
      # -- File Uploads --
      } elsif ($model->{'attributes'}[$i]{'type'} eq 'file') {
         $template = "
            <!-- add to form tag:  enctype='multipart/form-data'-->
      <% IF $model_name.$model->{'attributes'}[$i]{'label_unreadable'} %>
         <p class='wrap'>
            <label for='server_image' class='label'>Existing</label>
            <input type='text' name='$model->{'attributes'}[$i]{'label_unreadable'}' value='' id='$model->{'attributes'}[$i]{'label_unreadable'}' readonly='readonly' /> OR...
         </p>
      <% END %>" . $template;
         $template .= "
      <a href='/documents/<% $model_name.$model->{'attributes'}[$i]{'label_unreadable'} %>'>Download</a>";      
      # -- Everything else --
      } else {
         $template .= "
      <% $model_name.$model->{'attributes'}[$i]{'label_unreadable'} %>";
      }
      $template .="
   </p>";
   }
   $template .= "
      <a href='/".$model_name."s/'>Back to List</a>
";
   return $template;
}

# ----- Create Models Schemas -----
sub create_model_controllers {
   my %options = @_;
   my $models = ($options{'models'}) ? $options{'models'} : undef;
   my $app_path = ($options{'app_path'}) ? $options{'app_path'} : undef;
   my $write_files = ($options{'write_files'}) ? 1 : 0;
   my $overwrite = ($options{'overwrite'}) ? 1 : 0;

   # Errors
   die "Models are required to create model controllers." unless defined $models;

   for my $i ( 0 .. $#$models ) {
      
   }
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

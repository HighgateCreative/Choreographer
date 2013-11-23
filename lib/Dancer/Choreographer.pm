package Dancer::Choreographer;

use strict;
use warnings;

use Exporter;
use vars qw($VERSION @ISA @EXPORT @EXPORT_OK);

use 5.008_005;
our $VERSION = '0.01';

@ISA = qw(Exporter);
@EXPORT = qw(setting_the_stage choreograph);
@EXPORT_OK = qw(setup);

use PPI;
use JSON;
use File::Which;
use File::Path 'mkpath';

use Data::Dumper;

#print Dumper(\%Config);
#use lib $Config{INSTALLSCRIPT};

sub setting_the_stage {
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

   my $return;
   
   for my $i ( 0 .. $#$params ) {
      if (eval "validate_app_name(\$params->[\$i]{'settings'}{'app_name'});") {
         die "Try a new app name.";
      }

      # Check if working with a module only or not
      if ($params->[$i]{'settings'}{'module_only'}) {
			   # Check to see if Schema has been created
		     our_safe_mkdir($params->[$i]{'settings'}{'app_path'}."/lib/".$params->[$i]{'settings'}{'app_name'}."/");
				 write_files( $params->[$i]{'settings'}{'app_path'}."/lib/".$params->[$i]{'settings'}{'app_name'}."/Schema.pm",
"package $params->[$i]{'settings'}{'app_name'}::Schema;

use strict;
use warnings;

use base 'DBIx::Class::Schema';

our \$VERSION = 1;

__PACKAGE__->load_namespaces;

1;");

         my $msgs = create_models(  models      => $params->[$i]{'models'},
                                    app_name    => $params->[$i]{'settings'}{'app_name'},
                                    app_path    => $params->[$i]{'settings'}{'app_path'},
                                    write_files => $params->[$i]{'settings'}{'write_files'},
                                    overwrite   => $params->[$i]{'settings'}{'overwrite'},
                                    json        => $json,
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
         if ($models->[$i]{'attributes'}[$j]{'type'} eq 'tinymce') {
            $models->[$i]{'has_tinymce'} = 1;
         }
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
   my $json = ($options{'json'}) ? $options{'json'} : undef;
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
      push @{ $return->{'errors'} }, { generic => "Creating Schema(s) failed." };
   }

   my $views_results = create_model_views(  models      => $models,
                        app_path    => $app_path,
                        app_name    => $app_name,
                        write_files => $write_files,
                        overwrite   => $overwrite,
                     );
   if (ref($views_results) eq 'ARRAY') {
      push @{ $return->{'success'} }, "View(s) successfully printed.";
      @{ $return->{'output'} } = ( @{$return->{'output'}}, @$views_results );
   } elsif ($views_results) {
      push @{ $return->{'success'} }, "View(s) successfully created.";
   } else {
      push @{ $return->{'errors'} }, { generic => "Creating View(s) failed." };
   }

   my $controller_results = create_model_controllers( models      => $models,
                                                      app_path    => $app_path,
                                                      app_name    => $app_name,
                                                      write_files => $write_files,
                                                      overwrite   => $overwrite,
                                                      json        => $json,
                                                    );
   if (ref($controller_results) eq 'ARRAY') {
      push @{ $return->{'success'} }, "Controller(s) successfully printed.";
      @{ $return->{'output'} } = ( @{$return->{'output'}}, @$controller_results );
   } elsif ($controller_results) {
      push @{ $return->{'success'} }, "Controller(s) successfully created.";
   } else {
      push @{ $return->{'errors'} }, { generic => "Creating Controller(s) failed." };
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
      file           => 'varchar',
   );

   # Make sure directories exist
   if ($write_files) {
      our_safe_mkdir($app_path."/lib/".$app_name."/");
      our_safe_mkdir($app_path."/lib/".$app_name."/Schema/");
      our_safe_mkdir($app_path."/lib/".$app_name."/Schema/Result/");
   }

   for my $i ( 0 .. $#$models ) {
      my $result_name = join "_", map {ucfirst} split / /, $models->[$i]{'table_name'}; #Uppercase first letter of every word and replace spaces with underscores.

      # ----- Generate schema pm text -----
      my $schema =
"package $app_name\::Schema::Result::$result_name;

use strict;
use warnings;

use base 'DBIx::Class::Core';

__PACKAGE__->load_components(qw/Validation::Structure/);

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
         my $size = $models->[$i]{'attributes'}[$j]{'max_length'};
         if ($models->[$i]{'attributes'}[$j]{'type'} eq 'file') {
            $size = 255;
         }
         $schema .=
"   '$models->[$i]{'attributes'}[$j]{'label_unreadable'}' => {
      data_type => '$data_type',
      size => '$size',";
         if ( not $models->[$i]{'attributes'}[$j]{'mandatory'} ) {
            $schema .= "
      is_nullable => 1,";
         }
         if ($models->[$i]{'attributes'}[$j]{'type'} eq 'email') {
            $schema .= "
      val_override => 'email',";
         } elsif ( ( $models->[$i]{'attributes'}[$j]{'type'} eq 'radio' or $models->[$i]{'attributes'}[$j]{'type'} eq 'select' ) and $models->[$i]{'attributes'}[$j]{'mandatory'} ) {
            $schema .= "
      val_override => 'selected',";
         }
         if ($models->[$i]{'attributes'}[$j]{'type'} eq 'checkbox') {
            $schema .= "
      default_value => 0,";
         }
         $schema .= "
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

   for my $i ( 0 .. $#$models ) {
      my $model_name = join "_", split / /, $models->[$i]{'table_name'}; #Uppercase first letter of every word and replace spaces with underscores.

      # Check for model specific folder like views/artists
      if ($write_files) {
         our_safe_mkdir($app_path."/views/".$model_name."/");
      }

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
      if ($model->{'attributes'}[$i]{'type'} eq 'file') {
         $template .=
   "         <td><% IF $model_name.$model->{'attributes'}[$i]{'label_unreadable'} %><a href='<% request.uri_base %>/documents/<% $model_name.$model->{'attributes'}[$i]{'label_unreadable'} %>'>Download</a><% END %></td>
   ";
      } else {
         $template .=
   "         <td><% $model_name.$model->{'attributes'}[$i]{'label_unreadable'} %></td>
   ";
      }
   }
   $template .=
"      </tr>
    <% END %>
    </table>
  <% ELSE %>
    <p>No results found</p>
  <% END %>
   <a class='button' href='/".$model_name."s/add/'>Add a $model->{'readable_name'}</a>
   &nbsp;&nbsp;<a href='<% dashboard %>'>Dashboard</a>
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
<form id='".$model_name."_form' action='/".$model_name."s' enctype='multipart/form-data' method=''>
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
      } elsif ($model->{'attributes'}[$i]{'type'} eq 'textarea' or $model->{'attributes'}[$i]{'type'} eq 'tinymce') {
         my $input_class = '';
         if ($model->{'attributes'}[$i]{'type'} eq 'tinymce') {
            $input_class .= ' tinymce';
         }
         $template .= "
      <textarea name='$model->{'attributes'}[$i]{'label_unreadable'}' id='$model->{'attributes'}[$i]{'label_unreadable'}' class='counter count_down$input_class' size='$model->{'attributes'}[$i]{'max_length'}'></textarea>
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
            <label for='server_$model->{'attributes'}[$i]{'label_unreadable'}' class='label'>Existing</label>
            <input type='text' name='server_$model->{'attributes'}[$i]{'label_unreadable'}' value='' id='server_$model->{'attributes'}[$i]{'label_unreadable'}' readonly='readonly' /> OR...
         </p>
      <% END %>" . $template;
         $template .= "
      <input type='file' name='$model->{'attributes'}[$i]{'label_unreadable'}' value='' id='$model->{'attributes'}[$i]{'label_unreadable'}' /><!-- don't forget: enctype='multipart/form-data' -->";      
      # -- Datepicker --
      } elsif ($model->{'attributes'}[$i]{'type'} eq 'datepicker') {
         $template .= "
      <input type='text' class='datepicker' name='$model->{'attributes'}[$i]{'label_unreadable'}' value='' maxlength='$model->{'attributes'}[$i]{'max_length'}' />";

         # Flag that the model has a datepicker
         $model->{datepicker} = 1;
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
      <input class='button' type='submit' value='<% IF ".$model_name.".id %>Update<% ELSE %>Save<% END %>' />
      &nbsp;<% IF ".$model_name.".id %>&nbsp;<a href='/".$model_name."s/delete/<% ".$model_name.".id %>'>Delete</a>&nbsp;|<% END %>
      &nbsp;<a href='/".$model_name."s/'>Back to List</a>
   </p>
</form>
<script type='text/javascript'>
   \$(function() {";
   if ($model->{'datepicker'}) {
      $template_whole .= "
      \$('.datepicker').datepicker( { dateFormat: \"mm-dd-yy\" } );";
   }
   if ($model->{'has_tinymce'}) {
      $template_whole .= "
      \$('textarea.tinymce').tinymce({
         script_url : '/javascripts/tiny_mce/tiny_mce.js',
         theme : 'advanced',
         theme_advanced_disable : 'underline,strikethrough,justifyright,justifyfull,styleselect,formatselect,numlist,outdent,indent,anchor,image,cleanup,help,hr,removeformat,visualaid,sub,sup,',
         theme_advanced_buttons1 : 'bold,italic,|,justifyleft,justifycenter,bullist,|,undo,redo,|,link,unlink,|,code,charmap',
         theme_advanced_buttons2 : '',
         theme_advanced_buttons3 : '',
         content_css : '/css/form.css',
         width : '400',
         height : '200'
         //theme_advanced_toolbar_location : 'top'
      });";
   }
   $template_whole .= "
      \$('#".$model_name."_form').ajaxForm({
         url: '/".$model_name."s<% IF $model_name.id %>/put<% END %>',
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

   # Additional Scripts
   if ($model->{'has_tinymce'}) {
      $template_whole .= "
   <script src='<% request.uri_base %>/javascripts/tiny_mce/jquery.tinymce.js' type='text/javascript'></script>";
   }

   # Additional Scripts
   if ($model->{'datepicker'}) {
      $template_whole .= "
   <script src=\"//ajax.googleapis.com/ajax/libs/jqueryui/1.10.3/jquery-ui.min.js\"></script>
   <link rel=\"stylesheet\" href=\"//ajax.googleapis.com/ajax/libs/jqueryui/1.10.3/themes/ui-lightness/jquery-ui.min.css\" />";
   }
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
         $template .= "
      <% IF $model_name.$model->{'attributes'}[$i]{'label_unreadable'} %>
      <a href='<% request.uri_base %>/documents/<% $model_name.$model->{'attributes'}[$i]{'label_unreadable'} %>'>Download</a>
      <% END %>";
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
   my $app_name = ($options{'app_name'}) ? $options{'app_name'} : undef;
   my $json = ($options{'json'}) ? $options{'json'} : undef;
   my $write_files = ($options{'write_files'}) ? 1 : 0;
   my $overwrite = ($options{'overwrite'}) ? 1 : 0;

   # Errors
   die "Models are required to create model controllers." unless defined $models;

   # Set return to 1 (success) if writing to files
   my $return = ($write_files && $app_path && $app_name) ? 1 : undef;

   for my $i ( 0 .. $#$models ) {
      my $result_name = join "_", map {ucfirst} split / /, $models->[$i]{'table_name'}; #Uppercase first letter of every word and replace spaces with underscores.
      my $model_name = join "_", split / /, $models->[$i]{'table_name'}; #Uppercase first letter of every word and replace spaces with underscores.

      my $route_file =
"package ".$result_name.";
use Dancer ':syntax';
use Dancer::Plugin::DBIC;
use HTML::FillInForm;
use Data::Dumper;
use Stagehand::Stagehand;

# Setup Models' 'aliases'
sub $result_name { model('$result_name'); }


prefix '/".$model_name."s' => sub {

my \%tmpl_params;
hook 'before' => sub {
   # Clear tmpl Params;
   \%tmpl_params = ();
};

# ==== CRUD =====

# Read
get '/?:id?' => sub {
   if ( param 'id' ) {
      \$tmpl_params{$model_name} = ".$result_name."->find(param 'id');   # \\\@{[ ]} will force a list context
      template '".$model_name."/".$model_name."_read', \\\%tmpl_params;
   } else {
      \$tmpl_params{".$model_name."s} = \\\@{[".$result_name."->all]};   # \\\@{[ ]} will force a list context
      template '".$model_name."/".$model_name."_list', \\\%tmpl_params;
   }
};

# Create
post '/?:id?' => sub {
   set serializer => 'JSON';

   my \%params = params;
   my \$success;

   my \$result = ".$result_name."->create( \\\%params );
   if (\$result->{errors}) {
      return \$result;
   }
   \$success = \"$models->[$i]{'table_name'} added Successfully\";
   return { success => [ { success => \$success } ] };
};

# Update
put '/?:id?' => sub {
   return put_cntrl();
};
post '/put/?:id?' => sub {
   return put_cntrl();
};
sub put_cntrl {
   set serializer => 'JSON';

   my \%params = params;
   my \$success;

   my \$result = ".$result_name."->find(param 'id')->update( \\\%params );
   if (\$result->{errors}) {
      return \$result;
   }
   \$success = \"$models->[$i]{'table_name'} updated Successfully\";
   return { success => [ { success => \$success } ] };
}

# Delete
get '/delete/:id' => sub {
   ".$result_name."->find(param 'id')->delete();
   redirect '/".$model_name."s/';
};
del '/:id' => sub {
   ".$result_name."->find(param 'id')->delete();
   redirect '/".$model_name."s/';
};

# ---- Views -----

get '/add/?' => sub {
	template '".$model_name."/".$model_name."_edit', \\\%tmpl_params;
};

get '/edit/:id' => sub {
   if (param 'id') { \$tmpl_params{$model_name} = ".$result_name."->find(param 'id'); }
   %tmpl_params = (%tmpl_params, %{".$result_name."->search({ id => param 'id' }, {
      result_class => 'DBIx::Class::ResultClass::HashRefInflator',
   })->next});";
   for my $j ( 0 .. $#{$models->[$i]{'attributes'}} ) {
      if ($models->[$i]{'attributes'}[$j]{'type'} eq 'file') {
         $route_file .= "
   \$tmpl_params{'server_$models->[$i]{'attributes'}[$j]{'label_unreadable'}'} = \$tmpl_params{'$models->[$i]{'attributes'}[$j]{'label_unreadable'}'};";
      }
   }
   $route_file .= "
	fillinform('$model_name/".$model_name."_edit', \\%tmpl_params);
};

}; # End prefix
1;
";

      # If original json give, append
      $route_file .= "\n__END__\n# The original json used to create this Model:\n".$json if $json;

      if ( $write_files && $app_path && $app_name && $route_file ) {
         $app_name =~ s{::}{/}g; # Convert app name to file path
         if ( not write_files($app_path."/lib/".$result_name.".pm", $route_file, $overwrite) ) {
            $return = 0;
         }
      } else {
         push @$return, $route_file;
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

sub our_safe_mkdir {
    my ($dir) = @_;
    if (not -d $dir) {
        mkpath $dir or die "could not mkpath $dir: $!";
    }
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

Copyright 2013- Sean Zellmer

=head1 LICENSE

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 SEE ALSO

=cut

package Rose::DBx::Object::Renderer;
use strict;
use Exporter 'import';

use base qw(Rose::Object);
our @EXPORT = qw(config load);
our @EXPORT_OK = qw(config load render_as_form render_as_table render_as_menu render_as_chart stringify_me stringify_class delete_with_file);
our %EXPORT_TAGS = (object => [qw(render_as_form stringify_me stringify_class delete_with_file)], manager => [qw(render_as_table render_as_menu render_as_chart)]);

use Lingua::EN::Inflect qw (PL);
use DateTime;
use Rose::DB::Object::Loader;
use CGI::FormBuilder;
use Template;
use File::Path;
use Digest::MD5 qw(md5_hex);
use Math::Round qw(nearest);
use Image::ExifTool qw(:Public);

eval
{
	require Scalar::Util::Clone;
	*clone = \&Scalar::Util::Clone::clone;
};

if($@)
{
	require Clone;
	*clone = \&Clone::clone;
}

our $VERSION = 0.32;
# build: 91.25

my $CONFIG = {
	db => {name => undef, type => 'mysql', host => '127.0.0.1', port => undef, username => 'root', password => 'root', tables_are_singular => undef, like_operator => 'like'},
	template => {path => 'templates', url => 'templates'},
	upload => {path => 'uploads', url => 'uploads', keep_old_files => undef},
	form => {download_message => 'Download File', cancel => 'Cancel'},
	table => {search_result_title => 'Search Results for "[% q %]"', empty_message => 'No Record Found.', per_page => 15, or_filter => undef, no_pagination => undef, delimiter => ', ', keyword_delimiter => ','},
	misc => {stringify_delimiter => ' ', html_head => '<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Transitional//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd"><head><title>[% title %]</title><style type="text/css">*{margin:0px;padding:0px;}body{font-family: "trebuchet ms", helvetica, sans-serif;font-size:small;color:#666666;}a{color:#ea440a;text-decoration: none;}a:hover{color:#ff6600;text-decoration: none;}p{margin:10px 20px;line-height: 180%;}form table{width:100%;}form td{border:0px;text-align:left;padding: 5px 20px;}form input, form textarea, form select{color: #666666;border: 1px solid #dddddd;background-color:#fff;margin-right: 10px;}form input[type="submit"]{padding:2px 7px;font-size:100%;}form input[type="text"]{padding-top:4px;}h2{font-size:300%;color:#aaa;font-weight:normal;}img{border:0px;}.light_container{padding:10px 10px 0px 10px;}.light_title_container{padding:30px 10px 0px 10px;}.light_table_searchable_container{width:100%;}.light_table_searchable{float:right;padding-top:6px;}.light_table_searchable_span{padding-right:3px;}.light_table_actions_container{position:relative;height:20px;}.light_table_actions{float:right;font-size:110%;padding-right:6px;}.light_table{width:100%;border:0px;padding:5px 10px; border-collapse:collapse;border-spacing:0px;}.light_table th, .light_table td{text-align:left;padding: 6px 2px;border-bottom: 1px solid #dddddd;}.light_table th{color:#666666;font-size:110%;font-weight:normal;background-color: #eee;}.light_menu{float:left;width:100%;background-color:#ddd;line-height:normal;}.light_menu ul{margin:0px;padding:10px 20px 0px 20px;list-style-type:none;}.light_menu ul li{display:inline;padding:0px;margin:0px;}.light_menu ul li a{float:left;display:block;color:#666;background:#d0d0d0;text-decoration:none;margin:0px 10px;padding:6px 20px;height:15px;}.light_menu ul li a:hover{background-color:#eee;color:#ff6600;}.light_menu ul li a.light_menu_current,.light_menu ul li a.light_menu_current:hover{cursor:pointer;background-color:#fff;}</style></head>'},
	columns => {
		'integer' => {validate => 'INT', sortopts => 'NUM'},
		'numeric' => {validate => 'NUM', sortopts => 'NUM'},
		'float' => {validate => 'FLOAT', sortopts => 'NUM', comment => 'e.g.: 2982.21'},
		'text' => {sortopts => 'LABELNAME', type => 'textarea', cols => '55', rows => '10', class => 'disable_editor'},
		'address' => {sortopts => 'LABELNAME', type => 'textarea', cols => '55', rows => '3', class => 'disable_editor', format => {for_view => sub {_view_address(@_);}}},
		'postcode' => {sortopts => 'NUM', validate => '/^\d{3,4}$/', maxlength => 4},
		'date' => {validate => '/^(0?[1-9]|[1-2][0-9]|3[0-1])\/(0?[1-9]|1[0-2])\/[0-9]{4}$/', format => {for_edit => sub {_edit_date(@_);}, for_update => sub {_update_date(@_);}, for_search => sub {_search_date(@_);}, for_filter => sub {_search_date(@_);}, for_view => sub {_edit_date(@_);}}},
		'datetime' => {validate => '/^(0?[1-9]|[1-2][0-9]|3[0-1])\/(0?[1-9]|1[0-2])\/[0-9]{4}\s+[0-9]{1,2}:[0-9]{2}$/', format => {for_edit => sub{_view_datetime(@_);}, for_view => sub{_view_datetime(@_);}, for_update => sub{_update_datetime(@_);}, for_search => sub{_search_timestamp(@_);}, for_filter => sub{_search_timestamp(@_);}}},
		'timestamp' => {readonly => 1, disabled => 1, format => {for_view => sub {_view_timestamp(@_);}, for_create => sub {_create_timestamp();}, for_edit => sub {_create_timestamp();}, for_update => sub {_update_timestamp(@_);}, for_search => sub{_search_timestamp(@_);}, for_filter => sub{_search_timestamp(@_);}}},
		'description' => {sortopts => 'LABELNAME', type => 'textarea', cols => '55', rows => '10'},
		'time' => {validate => 'TIME', format => {for_update => sub {_udpate_time(@_)}, for_search => sub {_search_time(@_);}, for_filter => sub {_search_time(@_);}, for_edit => sub{_edit_time(@_);}, for_view => sub{_edit_time(@_);}}},
		'length' => {validate => 'NUM', sortopts => 'NUM', format => {for_view => sub {my ($self, $column) = @_;my $value = $self->$column;return unless $value;return $value.' cm';}}},
		'weight' => {validate => 'NUM', sortopts => 'NUM', format => {for_view => sub {my ($self, $column) = @_;my $value = $self->$column;return unless $value;return $value.' kg';}}},
		'volume' => {validate => 'NUM', sortopts => 'NUM', format => {for_view => sub {my ($self, $column) = @_;my $value = $self->$column;return unless $value;return $value.' cm<sup>3</sup>';}}},
		'gender' => {options => ['Male', 'Female']},
		'name' => {sortopts => 'LABELNAME', required => 1, stringify => 1},
		'first_name' => {validate => 'FNAME', sortopts => 'LABELNAME', required => 1, stringify => 1},
		'last_name' => {validate => 'LNAME', sortopts => 'LABELNAME', required => 1, stringify => 1},
		'email' => {required => 1, validate => 'EMAIL', sortopts => 'LABELNAME', format => {for_view => sub {my ($self, $column) = @_;my $value = $self->$column;return unless $value;return qq(<a href="mailto:$value">$value</a>);}}, comment => 'e.g. your.name@work.com'},
		'url' => {sortopts => 'LABELNAME', format => {for_view => sub {my ($self, $column) = @_;my $value = $self->$column;return unless $value;return qq(<a href="$value">$value</a>);}}, comment => 'e.g. http://www.yourbusiness.com/'},
		'mobile' => {validate => '/^((\()?(\+)?\d{2}(\))?)?[-\s]?(\d{3}|\d{4})[-\s]?\d{3}[-\s]?\d{3}$/', comment => 'e.g. 0433 123 456'},
		'phone' => {validate => '/^((\()?(\+)?\d{2}[-\s]?\d?(\))?)?[-\s]?\d{4}[-\s]?\d{4}$/', comment => 'e.g. 02 9988 1288'},
		'username' => {validate => '/^[a-zA-Z0-9]{4,}$/', sortopts => 'LABELNAME', required => 1},
		'password' => {validate => '/^[\w.!?@#$%&*]{5,}$/', type => 'password', format => {for_view => sub {return '****';}, for_edit => sub {return;}, for_update => sub {my ($self, $column, $value) = @_;return $self->$column(md5_hex($value)) if $value;}}, comment => 'Minimum 5 characters', unsortable => 1},
		'confirm_password' => {required => 1, type => 'password', validate => {javascript => "!= form.elements['password'].value"}},
		'abn' => {label => 'ABN', validate => '/^(\d{2}\s*\d{3}\s*\d{3}\s*\d{3})$/', comment => 'e.g.: 12 234 456 678'},
		'money' => {validate => '/^\-?\d{1,11}(\.\d{2})?$/', sortopts => 'NUM', format => {for_view => sub {my ($self, $column, $value) = @_;$value = $self->$column;return unless $value ne ''; return '$'._round_float($value);}}},
		'percentage' => {validate => 'NUM', sortopts => 'NUM', comment => 'e.g.: 99.8', format => {for_view => sub {my ($self, $column, $value) = @_;$value = $self->$column;return unless $value;my $p = $value*100;return "$p%";}, for_edit => sub {my ($self, $column) = @_;my $value = $self->$column;return unless defined $value;return $value*100;}, for_update => sub {my ($self, $column, $value) = @_;return $self->$column($value/100) if $value;},  for_search => sub {_search_percentage(@_);}, for_filter => sub {_search_percentage(@_);}}},
		'document' => {validate => '/^\S+[\w\s.!?@#$\(\)\'\_\-:%&*\/\\\\\[\]]{1,255}$/', format => {path => sub {_get_file_path(@_);}, url => sub {_get_file_url(@_);}, for_update => sub {_update_file(@_);}, for_view => sub {_view_file(@_)}}, type => 'file'},
		'image' => {validate => '/^\S+[\w\s.!?@#$\(\)\'\_\-:%&*\/\\\\\[\]]{1,255}$/', format => {path => sub {_get_file_path(@_);}, url => sub {_get_file_url(@_);}, for_view => sub {_view_image(@_);}, for_update => sub {_update_file(@_);}}, type => 'file'},
		'media' => {validate => '/^\S+[\w\s.!?@#$\(\)\'\_\-:%&*\/\\\\\[\]]{1,255}$/', format => {path => sub {_get_file_path(@_);}, url => sub {_get_file_url(@_);}, for_view => sub {_view_media(@_);}, for_update => sub {_update_file(@_);}}, type => 'file'},
		'ipv4' => {validate => 'IPV4', format => {for_search => sub {_search_ipv4(@_)}, for_filter => sub {_search_ipv4(@_)}}},
		'boolean' => {validate => '/^[0-1]$/', sortopts => 'LABELNAME', options => {1 => 'Yes', 0 => 'No'}, format => {for_view => sub {my ($self, $column) = @_;my $options = {1 => 'Yes', 0 => 'No'};return $options->{$self->$column};}, for_search => sub {_search_boolean(@_)}, for_filter => sub {_search_boolean(@_)}}},
	}
};

$CONFIG->{columns}->{'doubleprecision'} = $CONFIG->{columns}->{'numeric'};
$CONFIG->{columns}->{'decimal'} = $CONFIG->{columns}->{'numeric'};
$CONFIG->{columns}->{'bigint'} = $CONFIG->{columns}->{'integer'};
$CONFIG->{columns}->{'serial'} = $CONFIG->{columns}->{'integer'};
$CONFIG->{columns}->{'bigserial'} = $CONFIG->{columns}->{'integer'};
$CONFIG->{columns}->{'quantity'} = $CONFIG->{columns}->{'integer'};
$CONFIG->{columns}->{'height'} = $CONFIG->{columns}->{'length'};
$CONFIG->{columns}->{'width'} = $CONFIG->{columns}->{'length'};
$CONFIG->{columns}->{'depth'} = $CONFIG->{columns}->{'length'};
$CONFIG->{columns}->{'title'} = $CONFIG->{columns}->{'name'};
$CONFIG->{columns}->{'birth'} = $CONFIG->{columns}->{'date'};
$CONFIG->{columns}->{'fax'} = $CONFIG->{columns}->{'phone'};
$CONFIG->{columns}->{'cost'} = $CONFIG->{columns}->{'money'};
$CONFIG->{columns}->{'price'} = $CONFIG->{columns}->{'money'};
$CONFIG->{columns}->{'blob'} = $CONFIG->{columns}->{'text'};
$CONFIG->{columns}->{'comment'} = $CONFIG->{columns}->{'text'};
$CONFIG->{columns}->{'file'} = $CONFIG->{columns}->{'document'};
$CONFIG->{columns}->{'report'} = $CONFIG->{columns}->{'document'};
$CONFIG->{columns}->{'photo'} = $CONFIG->{columns}->{'image'};
$CONFIG->{columns}->{'logo'} = $CONFIG->{columns}->{'image'};
$CONFIG->{columns}->{'sound'} = $CONFIG->{columns}->{'media'};
$CONFIG->{columns}->{'voice'} = $CONFIG->{columns}->{'media'};
$CONFIG->{columns}->{'video'} = $CONFIG->{columns}->{'media'};
$CONFIG->{columns}->{'movie'} = $CONFIG->{columns}->{'media'};

sub config
{
	my $self = shift;
	$self->{CONFIG} = clone($CONFIG) unless defined $self->{CONFIG};
	
	if (@_)
	{
		my $config = shift;
		if (exists $config->{columns})
		{
			foreach my $column (keys %{$config->{columns}})
			{
				if (exists $config->{columns}->{$column}->{format})
				{
					foreach my $method (keys %{$config->{columns}->{$column}->{format}})
					{
						$self->{CONFIG}->{columns}->{$column}->{format}->{$method} = $config->{columns}->{$column}->{format}->{$method};
					}
				}
				delete $config->{columns}->{$column}->{format};
				
				foreach my $key (keys %{$config->{columns}->{$column}})
				{
					$self->{CONFIG}->{columns}->{$column}->{$key} = $config->{columns}->{$column}->{$key};
				}
			}			
			delete $config->{columns};
		}
		
		foreach my $hash (keys %{$config})
		{
			foreach my $key (keys %{$config->{$hash}})
			{
				$self->{CONFIG}->{$hash}->{$key} = $config->{$hash}->{$key};
			}
		}
		
		return;
	}
	return $self->{CONFIG};
}

sub load
{
	my ($self, $args) = @_;
	$args = {} unless ref $args eq 'HASH';
	my $config = $self->config;
	unless (exists $args->{loader} && defined $args->{loader}->{class_prefix})
	{
		return unless $config->{db}->{name};
		$args->{loader}->{class_prefix} = $config->{db}->{name};
		$args->{loader}->{class_prefix} =~ s/_(.)/\U$1/g;
		$args->{loader}->{class_prefix} =~ s/[^\w:]/_/g;
		$args->{loader}->{class_prefix} =~ s/\b(\w)/\u$1/g;		
	}
	return if "$args->{loader}->{class_prefix}::DB::Object::AutoBase1"->isa('Rose::DB::Object');

	unless (defined $args->{loader}->{db})
	{
		unless (defined $args->{loader}->{db_dsn})
		{
			my $host;
		 	$host = 'host='. $config->{db}->{host} if $config->{db}->{host};
			$host .= ';port='.$config->{db}->{port} if $config->{db}->{port};
			$args->{loader}->{db_dsn} = qq(dbi:$config->{db}->{type}:dbname=$config->{db}->{name};$host);
		}
		
		$args->{loader}->{db_options}->{AutoCommit} ||= 1;
		$args->{loader}->{db_options}->{ChopBlanks} ||= 1;
		$args->{loader}->{db_username} ||= $config->{db}->{username};
		$args->{loader}->{db_password} ||= $config->{db}->{password};
	}
	
	my $loader = Rose::DB::Object::Loader->new(%{$args->{loader}});
	$loader->convention_manager->tables_are_singular(1) if $config->{db}->{tables_are_singular};
	
	my @loaded;
	foreach my $class ($loader->make_classes(%{$args->{make_classes}}))
	{
		my $package = qq(package $class;);
			
		if (($class)->isa('Rose::DB::Object'))
		{	
			my $foreign_keys = _get_foreign_keys($class);
			
			$package .= 'use Rose::DBx::Object::Renderer qw(:object);';

			foreach my $column (@{$class->meta->columns})
			{
				my $column_type;	
				unless ($column->{is_primary_key_member})
				{
					if (exists $config->{columns}->{$column})
					{	
						$column_type = $column;
					}
					elsif (exists $foreign_keys->{$column}) # special treatment
					{						
						my $foreign_object_name = $foreign_keys->{$column}->{name};
						$config->{columns}->{$column} = {label => _label($foreign_object_name), required => 1, validate => 'INT', sortopts => 'LABELNAME', format => {for_view => sub {my ($self, $column) = @_;return unless $self->$column;return $self->$foreign_object_name->stringify_me;}}};
						$column_type = $column;
					}
					else
					{
						DEF: foreach my $column_key (keys %{$config->{columns}})
						{
							if ($column =~ /$column_key/) # first match
							{
								$column_type = $column_key;
								last DEF;
							}
						}
						
						unless (defined $column_type)
						{
							my $rdbo_column_type = lc ref $class->meta->{columns}->{$column};
							($rdbo_column_type) = $rdbo_column_type =~ /^.*::([\w_]+)$/;	
							$column_type = $rdbo_column_type if exists $config->{columns}->{$rdbo_column_type};
						}
						
						unless (defined $column_type)
						{
							my $custom_definition;
							$custom_definition->{required} = 1 if $class->meta->{columns}->{$column}->{not_null};
							$custom_definition->{maxlength} = $class->meta->{columns}->{$column}->{length} if defined $class->meta->{columns}->{$column}->{length};
							$custom_definition->{multiple} = 1 if ref $class->meta->{columns}->{$column} eq 'Rose::DB::Object::Metadata::Column::Set';
							$custom_definition->{options} = $class->meta->{columns}->{$column}->{check_in} if defined $class->meta->{columns}->{$column}->{check_in};
							
							$config->{columns}->{$column} = $custom_definition;
							$column_type = $column;
						}
					}				
					$package .= _generate_methods($config, $column, $column_type);
				}				
			}
			$package .= "sub renderer_config {return \$config;}\n";
		}
		else
		{
			$package .= 'use Rose::DBx::Object::Renderer qw(:manager);';
		}
		
		$package .= '1;';
		eval $package;
		die "Can't load $class: $@" if $@;
		push @loaded, $class;
	}
	return @loaded;
}

sub _generate_methods
{
	my ($config, $column, $column_type) = @_;
	my $method;
	if (exists $config->{columns}->{$column_type}->{format})
	{
		foreach my $custom_method_key (keys %{$config->{columns}->{$column_type}->{format}})
		{					
			$method .= "sub $column\_$custom_method_key {my (\$self, \$value) = \@_; return \$config->{columns}->{$column_type}->{format}->{$custom_method_key}->(\$self, '$column', \$value);}\n";
		}
	}	
	$method .= "sub $column\_definition {return \$config->{columns}->{$column_type};}\n";
	return $method;
}

sub render_as_form
{
	my ($self, %args) = (@_);
	my ($class, $object_id, $form_action, $field_order, $output, $relationship_object);
	my $table = $self->meta->table;
	my $primary_key = $self->meta->primary_key_column_names->[0];
	my $form_title = $args{title};

	if (ref $self)
	{
		$class = ref $self;
		$object_id = $self->$primary_key;
		$form_action = 'update';
		$form_title ||= _label($form_action.' '.$self->stringify_me);
	}
	else
	{
		$class = $self;
		$object_id = 'new';
		$form_action = 'create';
		$form_title ||= _label($form_action.' '.$table);
	}
	
	my $renderer_config = _get_renderer_config($class);
	my $download_message = $args{download_message} || $renderer_config->{form}->{download_message};
	my $cancel = $args{cancel} || $renderer_config->{form}->{cancel};
	my $template_url = $args{template_url} || $renderer_config->{template}->{url};
	my $template_path = $args{template_path} || $renderer_config->{template}->{path};
	my $html_head = $args{html_head} || $renderer_config->{misc}->{html_head};
	$html_head =~ s/\[%\s*title\s*%\]/$form_title/;
	
	my $foreign_keys = _get_foreign_keys($class);
	my $relationships = _get_relationships($class);
	my $column_order = $args{order} || _get_column_order($class, $relationships);
	
	my $ui_type = (caller(0))[3];
	($ui_type) = $ui_type =~ /^.*_(\w+)$/;
	my $form_id = _identify($class, $args{prefix}, $ui_type);
	
	my $form_template;
	if ($args{template} eq 1)
	{
		$form_template = $ui_type . '.tt';
	}
	else
	{
		$form_template = $args{template};
	}
		
	my $form_def = $args{form};
	$form_def->{name} ||= $form_id;
	$form_def->{enctype} ||= 'multipart/form-data';
	$form_def->{method} ||= 'post';
	$form_def->{params} ||= $args{cgi} if exists $args{cgi};
	
	if($args{template})
	{
		$form_def->{jserror} ||= 'notify_error';
	}
	else
	{
		$form_def->{messages}->{form_required_text} = '';
	}
	
	$form_def->{jsfunc} ||= qq(if (form._submit.value == '$cancel') {return true;});
	my $form = CGI::FormBuilder->new($form_def);
	foreach my $column (@{$column_order})
	{		
		my $field_def;
		$field_def = $args{fields}->{$column} if exists $args{fields} && exists $args{fields}->{$column};
		
		my $column_definition_method = $column . '_definition';
		if ($class->can($column_definition_method))
		{
			my $column_definition = $class->$column_definition_method;
			foreach my $property (keys %{$column_definition})
			{
				$field_def->{$property} = $column_definition->{$property} unless defined $field_def->{$property} || $property eq 'format'  || $property eq 'stringify' || $property eq 'unsortable';
			}
		}
		
		if (exists $relationships->{$column}) #one to many or many to many relationships
		{	
			$field_def->{validate} ||= 'INT';
			$field_def->{sortopts} ||= 'LABELNAME';
			$field_def->{multiple} ||= 1;
			
			my $foreign_class_primary_key = $relationships->{$column}->{class}->meta->primary_key_column_names->[0];
			
			if (ref $self && not exists $field_def->{value})
			{
				my $foreign_object_value;
			
			 	foreach my $foreign_object ($self->$column)
				{
					$foreign_object_value->{$foreign_object->$foreign_class_primary_key} = $foreign_object->stringify_me;
					$relationship_object->{$column}->{$foreign_object->$foreign_class_primary_key} = undef; #keep it for update
				}
				$field_def->{value} = $foreign_object_value;
			}
			
			unless ($field_def->{static} || $field_def->{type} eq 'hidden' || exists $field_def->{options})
			{				
				my $objects = Rose::DB::Object::Manager->get_objects(object_class => $relationships->{$column}->{class});
				if (@{$objects})
				{
					foreach my $object (@{$objects})
					{
						$field_def->{options}->{$object->$foreign_class_primary_key} = $object->stringify_me;
					}
				}
				else
				{
					$field_def->{type} ||= 'select';
					$field_def->{disabled} ||= 1;
				}
			}
		}
		elsif (exists $class->meta->{columns}->{$column}) #normal column
		{	
			if (exists $foreign_keys->{$column}) #create or edit
			{				
				unless (exists $field_def->{options} || $field_def->{type} eq 'hidden')
				{
					my $foreign_class = $foreign_keys->{$column}->{class};
					my $foreign_class_primary_key = $foreign_class->meta->primary_key_column_names->[0];
					if ($field_def->{static})
					{
						if (ref $self)
						{
							if ($self->$column)
							{
								my $foreign_column = $foreign_keys->{$column}->{name};
								$field_def->{options} = {$self->$column => $self->$foreign_column->stringify_me};
							}
						}
						else
						{
							my $foreign_object_id;
							if (defined $field_def->{value})
							{
								$foreign_object_id = $field_def->{value};
							}
							elsif(defined $self->meta->{columns}->{$column}->{default})
							{
								$foreign_object_id = $self->meta->{columns}->{$column}->{default};
							}
							
							if ($foreign_object_id)
							{
								my $foreign_object = $foreign_class->new($foreign_class_primary_key => $foreign_object_id);
								$field_def->{options} = {$foreign_object_id => $foreign_object->stringify_me} if $foreign_object->load(speculative => 1);
							}
						}
					}
					else
					{
						my $objects = Rose::DB::Object::Manager->get_objects(object_class => $foreign_keys->{$column}->{class});
						if (@{$objects})
						{
							foreach my $object (@{$objects})
							{
								$field_def->{options}->{$object->$foreign_class_primary_key} = $object->stringify_me;
							}
						}
						else
						{
							$field_def->{type} ||= 'select';
							$field_def->{disabled} ||= 1;
						}
					}
				}
			}
						
			if (ref $self) #edit
			{
				unless (exists $field_def->{value})
				{
					my $current_value;
					if ($class->can($column . '_for_edit'))
					{
						my $edit_method = $column . '_for_edit';
						$current_value = $self->$edit_method;
						$field_def->{value} = "$current_value";
					}
					else
					{
						if (ref $self->meta->{columns}->{$column} eq 'Rose::DB::Object::Metadata::Column::Set')
						{
							$field_def->{value} = $self->$column;
						}
						else
						{
							$current_value = $self->$column;
							$field_def->{value} = "$current_value"; # double quote to make it literal to stringify object refs such as DateTime
						}
					}
				}
									
				if ($field_def->{type} eq 'file' && not defined $field_def->{comment}) #file: if value exist in db, or in cgi param when the same form reloads
				{							
					my $value = $form->cgi_param($form_id.'_'.$column) || $form->cgi_param($column) || $self->$column;
					my $file_location = _get_file_url($self, $column, $value);
					$field_def->{comment} = '<br/><a href="'.$file_location.'">'.$download_message.'</a>' if $file_location;
				}
			}
			else
			{
				if (not exists $field_def->{value})
				{
					if ($class->can($column . '_for_create'))
					{
						my $create_method = $column.'_for_create';
						my $create_result = $self->$create_method($self->meta->{columns}->{$column}->{default});
						$field_def->{value} = $create_result if defined $create_result;
					}
					else
					{
						$field_def->{value} = $self->meta->{columns}->{$column}->{default} if defined $self->meta->{columns}->{$column}->{default};
					}
				}
			}							
		}
		
		delete $field_def->{value} if $field_def->{multiple} && $form->submitted && not $form->cgi_param($column) && not $form->cgi_param($form_id.'_'.$column);
		
		$field_def->{label} ||= _label($column);
		
		unless (exists $field_def->{name})
		{
			if ($args{prefix})
			{
				push @{$field_order}, $form_id.'_'.$column;
				$field_def->{name} = $form_id.'_'.$column;
			}
			else
			{
				push @{$field_order}, $column;
				$field_def->{name} = $column;
			}
		}
		
		$form->field(%{$field_def});
	}	

	foreach my $query_key (keys %{$args{queries}})
	{
		if (ref $args{queries}->{$query_key} eq 'ARRAY')
		{
			foreach my $value (@{$args{queries}->{$query_key}})
			{				
				$form->field(name => $query_key, value => CGI::escapeHTML($value), type => 'hidden', force => 1);	
			}
		}
		else
		{			
			$form->field(name => $query_key, value => CGI::escapeHTML($args{queries}->{$query_key}), type => 'hidden', force => 1);
		}
		
	}
				
	unless (defined $args{controller_order})
	{
		foreach my $controller (keys %{$args{controllers}})
		{
			push @{$args{controller_order}}, $controller;			
		}
		
		push @{$args{controller_order}}, ucfirst ($form_action) unless $args{controllers} && exists $args{controllers}->{ucfirst ($form_action)};
		push @{$args{controller_order}}, $cancel unless $args{controllers} && exists $args{controllers}->{$cancel};
	}
	
	$form->{submit} = $args{controller_order};
		
	$form->template({
						variable => 'form', 
						data => {
									template_url => $template_url,
									javascript_code => $args{javascript_code},
									field_order => $field_order,
									form_id => $form_id,
									title => $form_title,
									description => $args{description},
									html_head => $html_head,
									no_head => $args{no_head},
									self => $self,
									extra => $args{extra},
									cancel => $cancel,
								 },
						template => $form_template, 
						engine => {INCLUDE_PATH => $template_path}, 
						type => 'TT2'
					}) if $args{template};
	
	if ($form->submitted && $form->validate(%{$args{validate}}))
	{
		no strict 'refs';
		my $form_action_callback = '_'.$form_action.'_object';
		if (exists $args{controllers}->{$form->submitted} && $form->submitted ne $cancel) #method buttons
		{	
			if (ref $args{controllers}->{$form->submitted} eq 'HASH')
			{				
				if ($args{controllers}->{$form->submitted}->{$form_action})
				{
					unless (ref $args{controllers}->{$form->submitted}->{$form_action} eq 'CODE' && not $args{controllers}->{$form->submitted}->{$form_action}->($self))
					{
						$self = $form_action_callback->($self, $class, $table, $field_order, $form, $form_id, $args{prefix}, $relationships, $relationship_object);
					}					
				}

				$output->{controller} = $args{controllers}->{$form->submitted}->{callback}->($self) if ref $args{controllers}->{$form->submitted}->{callback} eq 'CODE';
				
				$args{hide_form} = 1 if exists $args{controllers}->{$form->submitted}->{hide_form};
			}
			else
			{
				$output->{controller} = $args{controllers}->{$form->submitted}->($self) if ref $args{controllers}->{$form->submitted} eq 'CODE';
			}
		}
		elsif($form->submitted eq ucfirst ($form_action))
		{
			$self = $form_action_callback->($self, $class, $table, $field_order, $form, $form_id, $args{prefix}, $relationships, $relationship_object);
		}		
		$output->{validate} = $form->validate(%{$args{validate}});
	}
	elsif($form->submitted eq $cancel)
	{
		$output->{validate} = 1;
	}
	
	my ($hide_form, $html_form);
	$hide_form = $form_id.'_' if $args{prefix};
	$hide_form .= 'hide_form';
		
	$args{hide_form} = 1 if $form->cgi_param($hide_form);
	unless ($args{hide_form})
	{
		if ($args{template})
		{
			$html_form .= $form->render;
		}
		else
		{
			$html_form = $html_head unless $args{no_head};
			$html_form .= qq(<div class="light_container"><div class="light_title_container"><h2>$form_title</h2><p>$args{description}</p></div>) . $form->render . '</div>';			
		}

		$html_form .= qq(<script type="text/javascript">$args{javascript_code}</script>) unless $args{template};
		
		$args{output}?$output->{output} = $html_form:print $html_form;
	}
	
	return $output;
}

sub render_as_table
{
	my ($self, %args) = (@_);
	my ($table, @controllers, $output, $previous_page, $next_page, $last_page, $total, $query_hidden_fields, $q, $sort_by_column, $table_config);
	my $class = $self->object_class();
	
	my $query = $args{cgi} || CGI->new;
	my $url = $args{url} || $query->url(-absolute => 1);
	
	my $renderer_config = _get_renderer_config($class);	
	foreach my $option (keys %{$renderer_config->{table}})
	{
		if (defined $args{$option})
		{
			$table_config->{$option} = $args{$option};
		}
		else
		{
			$table_config->{$option} = $renderer_config->{table}->{$option};
		}
	}
	
	my $table_title = $args{title} || _label($class->meta->table);
	
	my $like_operator = $args{like_operator} || $renderer_config->{db}->{like_operator};
	my $template_url = $args{template_url} || $renderer_config->{template}->{url};
	my $template_path = $args{template_path} || $renderer_config->{template}->{path};
	my $html_head = $args{html_head} || $renderer_config->{misc}->{html_head};
	$html_head =~ s/\[%\s*title\s*%\]/$table_title/;
	
	my $ui_type = (caller(0))[3];
	($ui_type) = $ui_type =~ /^.*_(\w+)$/;
	my $table_id = _identify($class, $args{prefix}, $ui_type);
	
	my $primary_key = $class->meta->primary_key_column_names->[0];
	my $relationships = _get_relationships($class);	
	my $column_order = $args{order} || _get_column_order($class, $relationships);	
	my $foreign_keys = _get_foreign_keys($class);
	
	my $param_list = {'sort_by' => 'sort_by', 'per_page' => 'per_page', 'page' => 'page', 'q' => 'q', 'ajax' => 'ajax', 'action' => 'action', 'object' => 'object', 'hide_table'};
	
	if ($args{prefix})
	{
		foreach my $param (keys %{$param_list})
		{
			$param_list->{$param} = $table_id.'_'.$param;
		}
	}	
		
	my $sort_by = $query->param($param_list->{'sort_by'});
	if ($sort_by)
	{
		my $sort_by_column = $sort_by;
		$sort_by_column =~ s/\sdesc//;
		my $sort_by_column_definition_method = $sort_by_column . '_definition';
		my $sort_by_column_definition;
		$sort_by_column_definition = $class->$sort_by_column_definition_method if $class->can($sort_by_column_definition_method);
			
		unless (not exists $class->meta->{columns}->{$sort_by_column} || (defined $sort_by_column_definition && $sort_by_column_definition->{unsortable}) || (exists $args{columns} && exists $args{columns}->{$sort_by_column} && exists $args{columns}->{$sort_by_column}->{value}))
		{
			$args{get}->{sort_by} = $sort_by;
		}
	}
	
	if ($args{searchable})
	{
		$query_hidden_fields = _create_hidden_field($args{queries}); # this has to be done before appending 'q' to $args{queries}, which get serialised later as query stings

		$q = $query->param($param_list->{'q'});
		
		if ($q)
		{
			my ($or, @raw_qs, @qs);
			my $keyword_delimiter = $table_config->{keyword_delimiter};
			if ($keyword_delimiter)
			{
				@raw_qs = split /$keyword_delimiter/, $q;
			}
			else
			{
				@raw_qs = $q;
			}
			
			foreach my $raw_q (@raw_qs)
			{
				$raw_q =~ s/^\s+|\s+$//g;
				push @qs, $raw_q;
			}
						
			foreach my $searchable_column (@{$args{searchable}})
			{
				my ($search_values, $search_class, $search_column, $search_method);
				if ($searchable_column =~ /\./)
				{
					my $relationship_column;
					($relationship_column, $search_column) = split /\./, $searchable_column;
					$search_class = $relationships->{$relationship_column}->{class} if exists $relationships->{$relationship_column};
				}
				else
				{
					$search_class = $class;
					$search_column = $searchable_column;
				}
				
				if ($search_class && $search_class->can($search_column . '_for_search'))
				{
					$search_method = $search_column.'_for_search';
					foreach my $q (@qs)
					{
						my $search_result = $search_class->$search_method($q);
						push @{$search_values},  $search_class->$search_method($q) if defined $search_result;
					}
				}
				else
				{
					$search_values = \@qs;
				}
				
				if ($search_values)
				{
					if ($search_class && $search_method)
					{
						push @{$or}, $searchable_column => $search_values;
					}
					else
					{
						my $like_search_values;
						foreach my $search_value (@{$search_values})
						{
							push @{$like_search_values}, '%'. $search_value .'%' if defined $search_value;
						}
						push @{$or}, $searchable_column => {$like_operator => $like_search_values} if defined $like_search_values;
					}
				}
			}
			
			push @{$args{get}->{query}}, 'or' => $or;				
			$args{queries}->{$param_list->{q}} = $q;
			
			$table_title = $args{search_result_title} || $table_config->{search_result_title};
			$table_title =~ s/\[%\s*q\s*%\]/$q/;
		}
	}
	
	my $filtered_columns;
	foreach my $column (@{$column_order})
	{
		unless (exists $relationships->{$column})
		{
			my $cgi_column;
			$cgi_column = $table_id.'_' if $args{prefix};
			$cgi_column .= $column;

			if ($query->param($cgi_column))
			{
				my @cgi_column_values = $query->param($cgi_column);
				my $formatted_values;
				if ($class->can($column . '_for_filter'))
				{
					my $filter_method = $column . '_for_filter';
					foreach my $cgi_column_value (@cgi_column_values)
					{
						my $filter_result = $class->$filter_method($cgi_column_value);
						push @{$formatted_values}, $filter_result if $filter_result;
					}
				}
				elsif ($class->can($column))
				{
					$formatted_values = \@cgi_column_values;
				}
				
				if ($formatted_values)
				{
					push @{$filtered_columns}, $column => $formatted_values;
				}
			}
		}
	}
	
	if ($filtered_columns)
	{
		if($table_config->{or_filter})
		{
			push @{$args{get}->{query}}, 'or' => $filtered_columns;						
		}
		else
		{
			foreach my $filtered_column (@{$filtered_columns})
			{
				push @{$args{get}->{query}}, $filtered_column; 
			}
		}
	}
		
	$args{get}->{per_page} ||= $query->param($param_list->{'per_page'}) || $table_config->{per_page};
	$args{get}->{page} ||= $query->param($param_list->{'page'}) || 1;
		
	my $objects = $self->get_objects(%{$args{get}});

	##Handle Submission
	my $reload_object;
	if ($query->param($param_list->{action}))
	{
		if ($query->param($param_list->{action}) eq 'create' && $args{create})
		{
			$args{create} = {} if $args{create} eq 1;
			$args{create}->{output} = 1;
			$args{create}->{no_head} ||= 1 if $args{no_head};
			$args{create}->{order} ||= $args{order} if $args{order};
			
			$args{create}->{template} ||= 1 if $args{template} && not exists $args{create}->{template};
			
			@{$args{create}->{queries}}{keys %{$args{queries}}} = values %{$args{queries}};			
			
			$args{create}->{queries}->{$param_list->{action}} = 'create';
			
			$args{create}->{queries}->{$param_list->{sort_by}} = $query->param($param_list->{sort_by}) if $query->param($param_list->{sort_by});
			$args{create}->{queries}->{$param_list->{page}} = $query->param($param_list->{page}) if $query->param($param_list->{page});	
			
			$args{create}->{prefix} ||= $table_id.'_form';
			my $form = $class->render_as_form(%{$args{create}});
			$output->{form}->{controller} = $form->{controller} if exists $form->{controller};
			$form->{validate}?$reload_object = 1:$output->{output} = $form->{output};
		}
		else
		{
			if ($query->param($param_list->{object}))
			{				
				my @action_object = $query->param($param_list->{object});
				my $object_counter = 0;
				foreach my $object (@{$objects})
				{
					foreach my $action_object (@action_object)
					{
						if ($object->$primary_key eq $action_object)
						{
							if ($query->param($param_list->{action}) eq 'delete' && $args{delete})
							{
								$object->delete_with_file;
								$reload_object = 1;					
							}
							elsif($query->param($param_list->{action}) eq 'edit' && $args{edit})
							{
								$args{edit} = {} if $args{edit} eq 1;
								$args{edit}->{output} = 1;
								$args{edit}->{no_head} ||= 1 if $args{no_head};								
								$args{edit}->{order} ||= $args{order} if $args{order};
								
								$args{edit}->{template} ||= 1 if $args{template} && not exists $args{edit}->{template};
																
								@{$args{edit}->{queries}}{keys %{$args{queries}}} = values %{$args{queries}};				
								$args{edit}->{queries}->{$param_list->{action}} = 'edit';
								
								$args{edit}->{queries}->{$param_list->{object}} = $action_object;
								
								$args{edit}->{queries}->{$param_list->{sort_by}} = $query->param($param_list->{sort_by}) if $query->param($param_list->{sort_by});
								$args{edit}->{queries}->{$param_list->{page}} = $query->param($param_list->{page}) if $query->param($param_list->{page});								
								
								$args{edit}->{prefix} ||= $table_id.'_form';

								my $form = $object->render_as_form(%{$args{edit}});
								$output->{form}->{controller} = $form->{controller} if exists $form->{controller};
								$form->{validate}?$reload_object = 1:$output->{output} = $form->{output};
							}
							elsif(exists $args{controllers} && exists $args{controllers}->{$query->param($param_list->{action})})
							{
								no strict 'refs';	
								if (ref $args{controllers}->{$query->param($param_list->{action})} eq 'HASH')
								{									
									$output->{controller} = $args{controllers}->{$query->param($param_list->{action})}->{callback}->($object) if ref $args{controllers}->{$query->param($param_list->{action})}->{callback} eq 'CODE';
									$args{hide_table} = 1 if exists $args{controllers}->{$query->param($param_list->{action})}->{hide_table};
								}
								else
								{
									$output->{controller} = $args{controllers}->{$query->param($param_list->{action})}->($object) if ref $args{controllers}->{$query->param($param_list->{action})} eq 'CODE';
								}
							}
						}
					}
					$object_counter++;
				}
			}
		}
		
		if(defined $output->{output})
		{
			return $output if $args{output};
			print $output->{output};
			return;
		}
	}
	
	($previous_page, $next_page, $last_page, $total) = _pagination($self, $class, $args{get});
	if($reload_object)
	{
		$args{get}->{page} = $last_page if $args{get}->{page} > $last_page;
		$objects = $self->get_objects(%{$args{get}}) if $reload_object;
	}
	
	##Render Table
	
	$args{hide_table} = 1 if $query->param($param_list->{'hide_table'});
	unless ($args{hide_table})
	{
		my ($html_table, $query_string);
		if ($args{controller_order})
		{
		 	@controllers = @{$args{controller_order}};
		}
		else
		{
		 	@controllers = keys %{$args{controllers}} if $args{controllers};
			push @controllers, 'edit' if $args{edit};
			push @controllers, 'delete' if $args{delete};
		}
	
		$args{queries}->{$param_list->{ajax}} = 1 if $args{ajax} && $args{template};
		
		if(exists $args{queries})
		{			
			$query_string->{base} = _create_query_string($args{queries});
			$query_string->{sort_by} = clone($query_string->{base});
			$query_string->{page} = clone($query_string->{base});	
		}
		
		if($query->param($param_list->{sort_by}))
		{
			$query_string->{page} .= $param_list->{sort_by}.'='.$query->param($param_list->{sort_by}).'&';
			$query_string->{exclusive} = $param_list->{sort_by}.'='.$query->param($param_list->{sort_by}).'&';
		}

		$query_string->{complete} = clone($query_string->{page});
		
		if ($query->param($param_list->{page}))
		{
			$query_string->{complete} .= $param_list->{page}.'='.$query->param($param_list->{page}).'&';
			$query_string->{exclusive} .= $param_list->{page}.'='.$query->param($param_list->{page}).'&';
		}
		
		##Define Table
				
		if ($args{create})
		{
			my $create_value = 'Create';
			$create_value = $args{create}->{title} if ref $args{create} eq 'HASH' && exists $args{create}->{title};
			$table->{create} = {value => $create_value, link => qq($url?$query_string->{complete}$param_list->{action}=create)} if $args{create};
		}
		
		$table->{total_columns} = scalar @{$column_order} + scalar @controllers;
		
		foreach my $column (@{$column_order})
		{
			my $head;
			$head->{name} = $column;
			
			my $column_definition_method = $column . '_definition';
			my $column_definition;
			$column_definition = $class->$column_definition_method if $class->can($column_definition_method);
					
			if (exists $args{columns} && exists $args{columns}->{$column} && exists $args{columns}->{$column}->{label})
			{
				$head->{value} = $args{columns}->{$column}->{label};				
			}
			else
			{
				$head->{value} = $column_definition->{label} || _label($column);				
			}
					
			unless (exists $relationships->{$column} || $column_definition->{unsortable} || (exists $args{columns} && exists $args{columns}->{$column} && exists $args{columns}->{$column}->{value}))
			{
				if ($query->param($param_list->{'sort_by'}) eq $column)
				{
					$head->{link} = qq($url?$query_string->{sort_by}$param_list->{sort_by}=$column desc);
				}
				else
				{
					$head->{link} = qq($url?$query_string->{sort_by}$param_list->{sort_by}=$column);
				}				
			}
			
			push @{$table->{head}}, $head;
		}
		
		foreach my $controller (@controllers)
		{
			my $label;
			if (ref $args{controllers}->{$controller} eq 'HASH' && exists $args{controllers}->{$controller}->{label}) 
			{
				$label = $args{controllers}->{$controller}->{label};
			}
			else
			{
				$label = _label($controller);
			}
			push @{$table->{head}}, {name => $controller, value => $label};
		}
		
		foreach my $object (@{$objects})
		{
			my $row;
			$row->{object} = $object;
			my $object_id = $object->$primary_key;
			foreach my $column (@{$column_order})
			{
				my $value;
				if(exists $args{columns} && exists $args{columns}->{$column} && exists $args{columns}->{$column}->{value}) #custom column value
				{
					$value = $args{columns}->{$column}->{value}->{$object_id} if exists $args{columns}->{$column}->{value}->{$object_id};
				}
				elsif (exists $relationships->{$column})
				{					
					$value = join $table_config->{delimiter}, map {$_->stringify_me} $object->$column;					
				}
				else
				{
					my $view_method;
					if ($class->can($column . '_for_view'))
					{
						$view_method = $column . '_for_view';	
					}
					elsif ($class->can($column))
					{
						$view_method = $column;
					}
					
					if ($view_method)
					{
						if (ref $class->meta->{columns}->{$column} eq 'Rose::DB::Object::Metadata::Column::Set')
						{
							$value = join $table_config->{delimiter}, $object->$view_method;
						}
						else
						{
							$value = $object->$view_method;
						}
					}
									
				}
				 
				push @{$row->{columns}}, {name => $column, value => $value};
			}
			
			foreach my $controller (@controllers)
			{
				my $label;
				if (ref $args{controllers}->{$controller} eq 'HASH' && exists $args{controllers}->{$controller}->{label}) 
				{
					$label = $args{controllers}->{$controller}->{label};
				}
				else
				{
					$label = _label($controller);
				}
				my $controller_query_string;
				if (ref $args{controllers}->{$controller} eq 'HASH' && exists $args{controllers}->{$controller}->{queries})
				{
					$controller_query_string = clone($query_string->{exclusive});
					$controller_query_string .= _create_query_string($args{controllers}->{$controller}->{queries});
				}
				else
				{
					$controller_query_string = $query_string->{complete};
				}
				push @{$row->{columns}}, {name => $controller, value => $label, link => qq($url?$controller_query_string$param_list->{action}=$controller&$param_list->{object}=$object_id)};
			}
			push @{$table->{rows}}, $row;
		}
		
		$table->{pager}->{first_page} = {value => 1, link => qq($url?$query_string->{page}$param_list->{page}=1)};
		$table->{pager}->{previous_page} = {value => $previous_page, link => qq($url?$query_string->{page}$param_list->{page}=$previous_page)};
		$table->{pager}->{next_page} = {value => $next_page, link => qq($url?$query_string->{page}$param_list->{page}=$next_page)};
		$table->{pager}->{last_page} = {value => $last_page, link => qq($url?$query_string->{page}$param_list->{page}=$last_page)};
		$table->{pager}->{current_page} = {value => $args{get}->{page}, link => qq($url?$query_string->{page}$param_list->{page}=$args{get}->{page})};
		$table->{pager}->{total} = $total;				
		
		if ($args{template})
		{
			my ($template, $ajax);
			if($args{ajax})
			{
				$template = $args{ajax_template} || $ui_type . '_ajax.tt';
				$ajax = 1 if $query->param($param_list->{ajax});
			}
			elsif($args{template} eq 1)
			{
				$template = $ui_type . '.tt';
			}
			else
			{
				$template = $args{template};
			}

			$html_table = _render_template(options => $args{template_options}, template_path => $template_path, file => $template, output => 1, data => {
				template_url => $template_url,
				javascript_code => $args{javascript_code},
				ajax => $ajax,
				url => $url,
				query_string => $query_string,
				query_hidden_fields => $query_hidden_fields,
				q => $q,
				param_list => $param_list,
				sort_by_column => $sort_by_column,
				searchable => $args{searchable},
				table => $table,
				objects => $objects,
				column_order => $column_order,
				table_id => $table_id,
				title => $table_title,
				description => $args{description},
				class_label => _label($class->meta->table),
				html_head => $html_head,
				no_head => $args{no_head},
				no_pagination => $table_config->{no_pagination},
				extra => $args{extra}
			});
		}
		else
		{			
			$html_table = $html_head;
			$html_table .= '<div class="light_container">';
			$html_table .= qq(<div class="light_table_searchable_container"><div class="light_table_searchable"><form action="$url" method="get" id="$table_id\_search_form"><label for="$table_id\_search"><span class="light_table_searchable_span">Search</span><input type="search" name="$param_list->{q}" id="$table_id\_search" accesskey="s" value="$q"></label>$query_hidden_fields</form></div></div>) if $args{searchable};			
			$html_table .= qq(<div class="light_title_container"><h2>$table_title</h2><p>$args{description}</p></div>);
			$html_table .= qq(<div class="light_table_actions_container"><div class="light_table_actions">);
			$html_table .= qq(<a href="$table->{create}->{link}">$table->{create}->{value}</a>) if exists $table->{create};
			$html_table .= '</div></div>';			
			
			$html_table .= '<table id="'.$table_id.'" class="light_table">';

			$html_table .= '<tr>';
			foreach my $head (@{$table->{head}})
			{
				if (exists $head->{link})
				{
					$html_table .= qq(<th><a href="$head->{link}">$head->{value}</a></th>);
				}
				else
				{
					$html_table .= qq(<th>$head->{value}</th>);
				}
			}
			$html_table .= '</tr>';
			
			if($table->{rows})
			{
				foreach my $row (@{$table->{rows}})
				{
					$html_table .= '<tr>';
					foreach my $column (@{$row->{columns}})
					{
						if (exists $column->{link})
						{
							$html_table .= qq(<td><a href="$column->{link}">$column->{value}</a></td>);
						}
						else
						{
							$html_table .= qq(<td>$column->{value}</td>);
						}
						
					}
					$html_table .= '</tr>';
				}
			}
			else
			{
				$html_table .= qq(<tr><td colspan="$table->{total_columns}"><p>$table_config->{empty_message}</p></td></tr>);
			}
			
			$html_table .= '</table>';
			
			unless ($table_config->{no_pagination})
			{
				$html_table .= '<div class="light_container">';
				if ($table->{pager}->{current_page}->{value} eq $table->{pager}->{first_page}->{value})
				{
					$html_table .= qq( <<  < );
				}
				else
				{
					$html_table .= qq(<a href="$table->{pager}->{first_page}->{link}"> << </a>);
					$html_table .= qq(<a href="$table->{pager}->{previous_page}->{link}"> < </a>);
				}
			
				$html_table .= qq( Page $table->{pager}->{current_page}->{value} of $table->{pager}->{last_page}->{value} );
			
				if ($table->{pager}->{current_page}->{value} eq $table->{pager}->{last_page}->{value})
				{
					$html_table .= qq( >  >> );
				}
				else
				{
					$html_table .= qq(<a href="$table->{pager}->{next_page}->{link}"> > </a>);
					$html_table .= qq(<a href="$table->{pager}->{last_page}->{link}"> >> </a>);
				}
				$html_table .= '</div>';
			}
			
			$html_table .=qq(</div><script type="text/javascript">$args{javascript_code}</script>);
		}
		
		$args{output}?$output->{output} = $html_table:print $html_table;
	}

	return $output;
}

sub render_as_menu
{
	my ($self, %args) = (@_);
	my($menu, $hide_menu_param, $current_param, $output, $content, $item_order, $items, $hide_menu, $current, $template);
	my $class = $self->object_class();

	my $menu_title = $args{title};
	
	my $renderer_config = _get_renderer_config($class);
	
	my $template_url = $args{template_url} || $renderer_config->{template}->{url};
	my $template_path = $args{template_path} || $renderer_config->{template}->{path};
	my $html_head = $args{html_head} || $renderer_config->{misc}->{html_head};
	$html_head =~ s/\[%\s*title\s*%\]/$menu_title/;
	
	my $ui_type = (caller(0))[3];
	($ui_type) = $ui_type =~ /^.*_(\w+)$/;
	my $menu_id = _identify($class, $args{prefix}, $ui_type);
	
	
	if ($args{prefix})
	{
		$hide_menu_param = $menu_id.'_hide_menu';
		$current_param = $menu_id.'_current';
	}
	else
	{
		$hide_menu_param='hide_menu';
		$current_param = 'current';
	}
	
	my $query = $args{cgi} || CGI->new;
	my $url = $args{url} || $query->url(-absolute => 1);
	my $query_string = join ('&', map {"$_=$args{queries}->{$_}"} keys %{$args{queries}});
	$query_string .= '&' if $query_string;
	
	if ($args{template} eq 1)
	{
		$template = $ui_type . '.tt';
	}
	else
	{
		$template = $args{template};
	}
	
	
	$current = $query->param($current_param) || $class->meta->table;	
	$item_order = $args{order} || [$class];
	
	foreach my $item (@{$item_order})
	{
		my $table = $item->meta->table;
		$items->{$item}->{table} = $table;
		
		if (defined $args{items} && defined $args{items}->{$item} && defined $args{items}->{$item}->{title})
		{
			$items->{$item}->{label} = $args{items}->{$item}->{title};
		}
		else
		{
			$items->{$item}->{label} = _label($table);
		}
		
		$items->{$item}->{link} = qq($url?$query_string$current_param=$table);
		if ($table eq $current)
		{
			my $options;
			$options = $args{items}->{$item} if exists $args{items} && exists $args{items}->{$item};
			$options->{output} = 1;
			
			@{$options->{queries}}{keys %{$args{queries}}} = values %{$args{queries}};
			$options->{queries}->{$current_param} = $table;	
			$options->{prefix} ||= $menu_id.'_table';
			$options->{url} ||= $url;
			
			$options->{template} = 1 if $args{template} && not defined $options->{template};
			
			if ($args{ajax})
			{
				$hide_menu = 1 if $query->param($options->{prefix}.'_ajax') && $query->param($options->{prefix}.'_action') ne 'create' && $query->param($options->{prefix}.'_action') ne 'edit';
				$options->{ajax} = $args{ajax} unless defined $options->{ajax};
			}
			
			$options->{create} = 1 if $args{create} eq 1 && not exists $options->{create};
			$options->{edit} ||= 1 if $args{edit} eq 1 && not exists $options->{edit};
			$options->{delete} ||= 1 if $args{delete} eq 1 && not exists $options->{delete};
			
			$options->{no_head} = 1;
			$output->{table} = "$item\::Manager"->render_as_table(%{$options});
			$menu_title ||= $items->{$item}->{label};
		}
	}
	
	$hide_menu = 1 if $query->param($hide_menu_param);
	
	if ($args{template})
	{
	 	$menu = _render_template(
			options => $args{template_options},
			template_path => $template_path,
			file => $template, 
			output => 1, 
			data => {
				menu_id => $menu_id,
				no_head => $args{no_head},
				html_head => $html_head,
				template_url => $template_url, 
				items => $items,
				item_order => $item_order, 
				current => $current,
				title => $menu_title,
				description => $args{'description'},
				extra => $args{extra},
				content => $output->{table}->{output},
				hide => $hide_menu,
			}
		);
	}
	else
	{	
		unless ($hide_menu)
		{
			$menu = $html_head.'<div class="light_container"><div class="light_menu"><ul>';
			foreach my $item (@{$item_order})
			{
				$menu .= '<li><a ';
				$menu .= 'class="light_menu_current" ' if $items->{$item}->{table} eq $current;
				$menu .= 'href="'.$items->{$item}->{link}.'">'.$items->{$item}->{label}.'</a></li>';
			}
			$menu .= '</ul></div><p>'.$args{'description'}.'</p></div>';
		}
		$menu .= $output->{table}->{output};
	}
		
	$args{output}?$output->{output} = $menu:print $menu;
	return $output;
}

sub render_as_chart
{
	my ($self, %args) = (@_);
	my $class = $self->object_class();
	
	my $title = $args{title} || _label($class->meta->table);
	
	my $renderer_config = _get_renderer_config($class);
	my $template_url = $args{template_url} || $renderer_config->{template}->{url};
	my $template_path = $args{template_path} || $renderer_config->{template}->{path};
	my $html_head = $args{html_head} || $renderer_config->{misc}->{html_head};
	$html_head =~ s/\[%\s*title\s*%\]/$title/;
	
	my $ui_type = (caller(0))[3];
	($ui_type) = $ui_type =~ /^.*_(\w+)$/;
	my $chart_id = _identify($class, $args{prefix}, $ui_type);
	
	my $hide_chart;
	if ($args{prefix})
	{
		$hide_chart = $chart_id . '_hide_chart';
	}
	else
	{
		$hide_chart = 'hide_chart';
	}
	
	my $query = $args{cgi} || CGI->new;
	return if $query->param($hide_chart);
	
	my ($chart, $output, $template);
	if (ref $args{engine} eq 'CODE')
	{
		no strict 'refs';
		$chart = $args{engine}->($self, %args);
	}
	else
	{		
		$args{options}->{chs} ||= $args{size} || '600x300';
		$args{options}->{chco} ||= 'ff6600';
				
		if (exists $args{type})
		{
			my $type = {
				pie => 'p',
				bar => 'bvg',
				line => 'ls'
			};
			
			if (exists $type->{$args{type}})
			{
				$args{options}->{cht} ||= $type->{$args{type}};
				
				unless (exists $args{options}->{chd})
				{
					my (@values, @labels);
					if ($args{type} eq 'pie' && $args{column} && $args{values})
					{
						my $foreign_keys = _get_foreign_keys($class);
						foreach my $value (@{$args{values}})
						{
							push @values, $self->get_objects_count(query => [ $args{column} => $value ]);
														
							if (exists $foreign_keys->{$args{column}})
							{
								my $foreign_class = $foreign_keys->{$args{column}}->{class};
								my $foreign_class_primary_key = $foreign_class->meta->primary_key_column_names->[0];
								my $foreign_object = $foreign_class->new($foreign_class_primary_key => $value);

								if($foreign_object->load(speculative => 1))
								{
									push @labels, $foreign_object->stringify_me;
								}
							}
							else
							{
								push @labels, $value; 
							}
						}
						
						$args{options}->{chd} = 't:' . join (',', @values);
					}
					elsif ($args{objects} && $args{columns})
					{
						my $min = 0;
						my $max = 0;
						
						$args{options}->{chxt} ||= 'x,y';
						$args{options}->{chdl} ||= join ('|', @{$args{columns}});						
						
						my $objects = $self->get_objects(query => [id => $args{objects}]);
						@labels = map {$_->stringify_me} @{$objects};
						
						foreach my $column (@{$args{columns}})
						{
							my @object_values;
							foreach my $object (@{$objects})
							{
								if ($object->$column)
								{
									push (@object_values, $object->$column);
									
									if ($object->$column > $max)
									{
										$max = $object->$column;
									}
									elsif($object->$column < $min)
									{
										$min = $object->$column;
									}
								}
								else
								{
									push (@object_values, 0);
								}
							}
							push (@values, join (',', @object_values));
						}
						
						$args{options}->{chd} = 't:' . join ('|', @values);
						
						$args{options}->{chds} ||= $min . ',' . $max;
						unless (exists $args{options}->{chxl} || ($max <= 100 && $min >= 0))
						{
							my $avg = ($max - abs($min)) / 2;
							my $max_avg = ($max - abs($avg)) / 2 + $avg;
							my $min_avg = ($avg - abs($min)) / 2;
							
							$args{options}->{chxl} = '1:|' . join ('|', ($min, $min_avg, $avg, $max_avg, $max));
						}
					}
									
					$args{options}->{chl} = join ('|', @labels);
				}
			}
		}
		
		my $chart_url = 'http://chart.apis.google.com/chart?' . _create_query_string($args{options});

		if ($args{template})
		{
			if($args{template} eq 1)
			{
				$template = $ui_type . '.tt';
			}
			else
			{
				$template = $args{template};
			}
			
			$chart = _render_template(
				options => $args{template_options},
				template_path => $template_path,
				file => $template,
				output => 1,
				data => {
					template_url => $template_url,
					chart => $chart_url,
					options => $args{'options'},
					chart_id => $chart_id,
					title => $title ,
					description => $args{'description'},
					no_head => $args{no_head},
					html_head => $html_head,
					extra => $args{'extra'}
				}
			);		
		}
		else
		{
			$chart = qq($html_head <div class="light_container"><div class="light_title_container"><h2>$title</h2><p>$args{description}</p></div><img src="$chart_url"/></div>);
		}
	}
	
	$args{output}?$output->{output} = $chart:print $chart;
	return $output;
}

sub _render_template
{
	my %args = (@_);
	if ($args{file} && $args{data} && $args{template_path})
	{
		my $options = $args{options};
		$options->{INCLUDE_PATH} ||= $args{template_path};
		my $template = Template->new(%{$options});
		if($args{output})
		{
			my $output = '';
			$template->process($args{file},$args{data}, \$output) || die $template->error(), "\n";
			return $output;
		}
		else
		{
			$template->process($args{file},$args{data});
		}
	}
}

#rdbo util

sub _get_renderer_config
{
	my $self = shift;
	return $self->renderer_config if $self->can('renderer_config');
	return $CONFIG;
}

sub _pagination
{
	my ($self, $class, $get) = @_;	
	my $total = $self->get_objects_count(%{$get});
	my ($last_page, $next_page, $previous_page);		
	if ($total < $get->{per_page})
	{
		$last_page = 1;
	}
	else
	{
		my $pages = $total / $get->{per_page};
		if ($pages == int $pages)
		{
			$last_page = $pages;
		}
		else
		{
			$last_page = 1 + int($pages);
		}
	}
	
	if ($get->{page} eq $last_page)
	{
		$next_page = $last_page;
	}
	else
	{
		$next_page = $get->{page} + 1;
	}
	
	if ($get->{page} eq 1)
	{
		$previous_page = 1;
	}
	else
	{
		$previous_page = $get->{page} - 1;
	}

	return ($previous_page, $next_page, $last_page, $total);
}

sub _update_object
{
	my ($self, $class, $table, $field_order, $form, $form_id, $prefix, $relationships, $relationship_object) = @_;
	
	my $primary_key = $self->meta->primary_key_column_names->[0];
	
	foreach my $field (@{$field_order})
	{
		my $column = $field;
		$column =~ s/$form_id\_// if $prefix;
		my $field_value;
		my @values = $form->field($field);
		my $values_size = scalar @values;
		
		if($values_size > 1)
		{
			$field_value = join ',', @values;	
		}
		else
		{
			$field_value = $form->field($field); #if this line is removed, $form->field function will still think it should return an array, which will fail for file upload
		}
		
		if (exists $relationships->{$column}) #one to many or many to many
		{
			my $foreign_class = $relationships->{$column}->{class};
			my $foreign_class_foreign_keys = _get_foreign_keys($foreign_class);
			my $foreign_key;
			
			foreach my $fk (keys %{$foreign_class_foreign_keys})
			{
				if ($foreign_class_foreign_keys->{$fk}->{class} eq $class)
				{
					$foreign_key = $fk;
					last;
				}
			}

			my $default = undef;
			$default = $relationships->{$column}->{class}->meta->{columns}->{$table.'_id'}->{default} if defined $relationships->{$column}->{class}->meta->{columns}->{$table.'_id'}->{default};
			if($form->cgi_param($field)) #check if field submitted. Empty value fields are not submited by browser, $form->field($field) won't work
			{ 
				my ($new_foreign_object_id, $old_foreign_object_id, $value_hash, $new_foreign_object_id_hash);
			
				my $foreign_class_primary_key = $relationships->{$column}->{class}->meta->primary_key_column_names->[0];
			
				foreach my $id (@values)
				{
					push @{$new_foreign_object_id}, $foreign_class_primary_key => $id;
					$value_hash->{$id} = undef;
					push @{$new_foreign_object_id_hash}, {$foreign_class_primary_key => $id};
				}
		
				foreach my $id (keys %{$relationship_object->{$column}})
				{
					push @{$old_foreign_object_id}, $foreign_class_primary_key => $id unless exists $value_hash->{$id};
				}
									
				if ($relationships->{$column}->{type} eq 'one to many')
				{
					Rose::DB::Object::Manager->update_objects(object_class => $foreign_class, set => {$foreign_key => $default}, where => [or => $old_foreign_object_id]) if $old_foreign_object_id;
					
					Rose::DB::Object::Manager->update_objects(object_class => $foreign_class, set => {$foreign_key => $self->$primary_key}, where => [or => $new_foreign_object_id]) if $new_foreign_object_id;						
				}
				else #many to many
				{
					$self->$column(@{$new_foreign_object_id_hash});
				}
			}
			else
			{
				if ($relationships->{$column}->{type} eq 'one to many')
				{					
					Rose::DB::Object::Manager->update_objects(object_class => $foreign_class, set => {$foreign_key => $default}, where => [$foreign_key => $self->$primary_key]);	
				}
				else #many to many
				{
					$self->$column([]); # cascade deletes foreign objects
				}
			}
		}
		else
		{
			my $update_method;
			if ($class->can($column . '_for_update'))
			{
				$update_method = $column . '_for_update';	
			}
			elsif ($class->can($column))
			{
				$update_method = $column;
			}
			
			if ($update_method)
			{
				if (defined $field_value)
				{
					$self->$update_method($field_value);
				}
				else
				{
					$self->$update_method(undef);
				}
			}
		}	
	}
	$self->save;
	return $self;
}

sub _create_object
{
	my ($self, $class, $table, $field_order, $form, $form_id, $prefix, $relationships, $relationship_object) = @_;	
	my $custom_field_value;
	
	$self = $self->new();
	
	foreach my $field (@{$field_order})
	{
		my $column = $field;
		$column =~ s/$form_id\_// if $prefix;
		
		my @values = $form->field($field);	
		
		if (exists $relationships->{$column}) #one to many or many to many
		{	
			if($form->cgi_param($field)) #check if field submitted. Empty value fields are not submited by browser, $form->field($field) won't work
			{ 
				my $new_foreign_object_id_hash;
				my $foreign_class_primary_key = $relationships->{$column}->{class}->meta->primary_key_column_names->[0];
				
				foreach my $id (@values)
				{
					push @{$new_foreign_object_id_hash}, {$foreign_class_primary_key => $id};
				}
			
				$self->$column(@{$new_foreign_object_id_hash});
			}
		}
		else
		{
			my $field_value;
			my $values_size = scalar @values;
			if($values_size > 1)
			{
				$field_value = join ',', @values;	
			}
			else
			{
				$field_value = $form->field($field); #if this line is removed, $form->field function will still think it should return an array, which will fail for file upload
			}
			
			if ($class->can($column . '_for_update'))
			{
				$custom_field_value->{$column . '_for_update'} = $field_value; #save it for later
				$self->$column('0') if $self->meta->{columns}->{$column}->{not_null}; # zero fill not null columns
			}
			elsif ($class->can($column))
			{
				$self->$column($field_value) if defined $field_value;
			}
		}
	}
	
	$self->save;

	#after save, run formatting methods, which may require an id, such as file upload
	if ($custom_field_value)
	{
		foreach my $update_method (keys %{$custom_field_value})
		{
			$self->$update_method($custom_field_value->{$update_method});
		}
		$self->save;
	}
	
	return $self;
}

sub _get_column_order
{	
	my ($class, $relationships) = @_;
	my $order;
	foreach my $column (sort {$a->ordinal_position <=> $b->ordinal_position} @{$class->meta->columns})
	{
		push @{$order}, "$column" unless exists $column->{is_primary_key_member};
	}
	
	foreach my $relationship (keys %{$relationships})
	{
		push @{$order}, $relationship;
	}
	return $order;
}

sub _get_foreign_keys
{
	my $class = shift;
	my $foreign_keys;
	foreach my $foreign_key (@{$class->meta->foreign_keys})
	{
		(my $key, my $value) = $foreign_key->_key_columns;
		$foreign_keys->{$key} = {name => $foreign_key->name, table => $foreign_key->class->meta->table, column => $value, is_required => $foreign_key->is_required, class => $foreign_key->class};
	}
	return $foreign_keys;
}

sub _get_relationships
{
	my $class = shift;
	my $relationships;
	
	foreach my $relationship (@{$class->meta->relationships})
	{
		if ($relationship->type eq 'one to many')
		{
			$relationships->{$relationship->name}->{type} = $relationship->type;
			$relationships->{$relationship->name}->{class} = $relationship->class;
		}
		elsif($relationship->type eq 'many to many')
		{
			$relationships->{$relationship->name}->{type} = $relationship->type;
			$relationships->{$relationship->name}->{class} = $relationship->foreign_class;	
		}
	}
	return $relationships;
}

sub delete_with_file
{
	my $self = shift;
	return unless ref $self;
	my $renderer_config = _get_renderer_config($self);
	my $primary_key = $self->meta->primary_key_column_names->[0];
	my $directory = join '/', ($renderer_config->{upload}->{url}, $self->stringify_class, $self->$primary_key);
	rmtree($directory) || die ("Could not remove $directory") if -d $directory;
	return $self->delete();
}

sub stringify_me
{
	my $self = shift;
	my @values;
	foreach my $column (sort {$a->ordinal_position <=> $b->ordinal_position} @{$self->meta->columns})
	{
		my $column_definition_method = $column.'_definition';
		if ($self->can($column_definition_method)) # filter primary keys and custom coded columns
		{
			my $column_definition = $self->$column_definition_method;
			push @values, $self->$column if $column_definition->{stringify};
		}
	}
	
	if (@values)
	{
		my $renderer_config = _get_renderer_config($self);
		return join $renderer_config->{misc}->{stringify_delimiter}, @values;
	}
	my $primary_key = $self->meta->primary_key_column_names->[0];
	return $self->$primary_key;	
}

sub stringify_class
{
	my $self = shift;
	my $package_name = lc ref $self || lc $self;
	$package_name =~ s/::/_/g;
	return $package_name;
}

# file util

sub _get_file_path
{
	my ($self, $column) = @_;
	my $value = $self->$column;
	return unless $value;
	my $renderer_config = _get_renderer_config($self);
	my $primary_key = $self->meta->primary_key_column_names->[0];
	return join '/', ($renderer_config->{upload}->{path}, $self->stringify_class, $self->$primary_key, $column, $value);
}

sub _get_file_url
{
	my ($self, $column) = @_;
	my $value = $self->$column;
	return unless $value;
	my $renderer_config = _get_renderer_config($self);
	my $primary_key = $self->meta->primary_key_column_names->[0];
	return join '/', ($renderer_config->{upload}->{url}, $self->stringify_class, $self->$primary_key, $column, $value);
}

sub _upload_file
{	
	my ($upload_path, $file_name, $file) = @_;	
	return unless $file_name && $upload_path && $file && not CGI::cgi_error();
	
	open FILE_HANDLER, ">$upload_path/$file_name" or die ("Could not open file handler for $upload_path/$file_name");
	while (<$file>)
	{
	   print FILE_HANDLER;
	}
	close FILE_HANDLER;
	return 1;
}

# formatting methods

sub _create_timestamp
{
	my $dt = DateTime->now->set_time_zone( 'Australia/Sydney');
	return $dt->dmy('/').' '.$dt->hms;
}

sub _edit_date
{
	my ($self, $column) = @_;
	return $self->$column unless ref $self->$column eq 'DateTime';
	$self->$column->set_time_zone('Australia/Sydney');
	return $self->$column->dmy('/') if $self->$column;
}

sub _edit_time
{
	my ($self, $column) = @_;
	return $self->$column unless ref $self->$column eq 'Time::Clock';
	return $self->$column->format('%H:%M');
}

sub _update_date
{
	my ($self, $column, $value) = @_;
	return unless $value;
	my ($d, $m, $y) = split '/', $value;
	my $dt;
	eval {$dt = DateTime->new(year => $y, month => $m, day => $d, time_zone => 'Australia/Sydney')};
	return if $@;
	return $self->$column($dt->ymd);
}

sub _udpate_time
{
	my ($self, $column, $value) = @_;
	return unless $value;
	my ($h, $m) = split ':', $value;
	my $t;
	eval {$t = Time::Clock->new(hour => $h, minute => $m)};
	return if $@;
	return $self->$column($t);
}

sub _update_file
{
	my ($self, $column, $value) = @_;
	return unless $value && $value ne '';
	my $renderer_config = _get_renderer_config($self);
	my $primary_key = $self->meta->primary_key_column_names->[0]; 
	my $upload_path = join '/', ($renderer_config->{upload}->{path}, $self->stringify_class, $self->$primary_key, $column);	
	mkpath($upload_path) unless -d $upload_path;
	
	my $file_name = "$value";
	$file_name =~ s/.*[\/\\](.*)/$1/;
	
	my ($actual_name, $extension) = ($file_name =~ /(.*)\.(.*)$/);
	$actual_name ||= $file_name;
	
	my $current_file = $self->$column;
	
	my $old_file;
	$old_file = $upload_path.'/'.$current_file if $current_file;
	my $new_file = $upload_path.'/'.$file_name;
	
	if ($old_file eq $new_file && -e $old_file) # same file name
	{
		my $counter = 1;
		my $backup_file = $upload_path.'/'.$actual_name.'-'.$counter.'.'.$extension;
		while (-e $backup_file)
		{			
			$counter++;
			$backup_file = $upload_path.'/'.$actual_name.'-'.$counter.'.'.$extension;
		}
		rename ($old_file, $backup_file);
		$old_file = $backup_file;
	}
		
	if (_upload_file($upload_path,$file_name, $value))
	{
		unlink($old_file) unless not $old_file || $renderer_config->{upload}->{keep_old_files};
		return $self->$column($file_name);
	}
	else
	{
		rename ($old_file, $upload_path.'/'.$current_file) if $old_file;
		return;
	}	
}

sub _update_timestamp
{
	my ($self, $column) = @_;
	return $self->$column(DateTime->now->set_time_zone('Australia/Sydney'));
}

sub _update_datetime
{
	my ($self, $column, $value) = @_;
	return $self->$column(undef) if $value eq '';
	my ($date, $time) = split /\s+/, $value;
	
	my ($d, $m, $y) = split '/', $date;
	my ($hour, $minute) = split ':', $time;
	
	my $dt;
	eval {$dt = DateTime->new(year => $y, month => $m, day => $d, hour => $hour, minute => $minute, time_zone => 'Australia/Sydney')};
	return if $@;
	return $self->$column($dt);
}

sub _view_file
{
	my ($self, $column) = @_;
	my $value = $self->$column;
	return unless $value;
	my $file_url = _get_file_url($self, $column);
	return qq(<a href="$file_url">$value</a>);
}

sub _view_image
{
	my ($self, $column) = @_;
	my $value = $self->$column;
	return unless $value;
	my $file_url = _get_file_url($self, $column);
	return qq(<img src="$file_url" alt="$value"/>);
}

sub _view_media
{
	my ($self, $column) = @_;
	my $value = $self->$column;
	return unless $value;
	my $location = _get_file_url($self, $column);
	return unless $location;
	my $info = ImageInfo($location);
	my $dimension;
	$dimension = " :: width: $info->{ImageWidth}, height: $info->{ImageHeight}" if $info->{ImageWidth} && $info->{ImageHeight};
	return qq(<a href="$location" title="$value :: Media$dimension" class="lightview"><img src="data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAABYAAAAWCAYAAADEtGw7AAAABGdBTUEAAK/INwWK6QAAABl0RVh0U29mdHdhcmUAQWRvYmUgSW1hZ2VSZWFkeXHJZTwAAASlSURBVHjaYmxpaZlhYmLixcjI+Ovf//8MMPAfic3wH42PJv+fAcJmYmRk+vHjx/+mpqZWgABi3LVr10tXV1exb58/Mfz99Y2BgZERroERgwG2A8H9DzMSaCgzEwMTKw8DKzs7Q4C//zaAAGL58+fvz+9fPjIUt05jePiDl4GDjZXh/7//YBf9/wd1zz+EC8Hi/5Fc/R/kFhaGj2+fM6R5azBEhAUx/P37lwkggFhAEv/+/GJ49ZubwTU+h4GXhYHh+w8Ght+/GRj+/AHi3/8Zfv+BsP/+/Q+k/0PZEP5foKWsbCwMZ88cY3jx9hIDCzPYP/8BArA8RikAwzAItdTRFXb/y7bUvYV9iISQF3V0qs49rKcHNWpxTGqYWvhOQ5/zoHaqGW7JsKa7fPlvFL0CiAXkG0ZQqAEVA8MdKMkIpP+BXfkbaBLY5b//gV0J4oNcCvYJlA1yNfNfVoafP/+Dwx5kKDAhMAAEEAsokGDx9QekkPE/mP7zB2EAxFCQBQxQuf+IoAHyWf5Dggw5kgECiAXOA3kLpAFoC0wjDP+GWvAbySJw2COFM8hSRrhZ/xkAAogFkR4ZwZK/GZBcC9QMNuA31ODfSD74DbUAaCjTX0hkM0K9DjITIIBYGGApkfE/xHYmaDhCvQlLESCN8OBACZr/wMiG8CHmgtMfA0AAsYDNBImAYh7kNSaI4n9/ERGE4n0QG2rJb6g4IzSIgDkP7EyQiwECiOU/Uj779w8SXv+gkff3DyTcYbGPHO5/fv+HpxRwxP9GyfEMAAEECWNGsLMhhkIN/wulwb74C7Xk3394hoG59s8voO8Y/0NdzAAPWYAAYkGUAEzAHMTKwMoKTD5/mBn+gXLkf2jkgLI2MBwZ/0Johr/gkIOoAcK/oGD8xwZKuPACCSCAWEDlAjMzK8PXD28Ydu3ew8DHwQLOKH/hSQuUk5gg4Q1y6a+/UNf+hwfT///MDG+eXAXayQ9OcqBQAAggFhYWZub/zOwMxTH2DE9fvQPmdVDWZAZ6iwnqmX8MHz6+A5Ynf8FZloebC5p1GcGGgCLsFyjJ/FNh0FRXYfgJzKXMQDMAAojl/fv3P0HBbGNlwcDIxAQ26A8w8H7//gU2l5mZheHVq9fAsP8HDn9hYUEGNjY2sANAReXzN88ZxIUkGJhZWIE+/cHw7t07hi9fvjADBBCjvLy8j7q6epaMjIySmpqaiJKSEi8nJycryFZBQUFGISEhYLizMgC9BnTlP6Dmn6BiEZhy/jG8//D+/7U71xj+/fj36+7du1+A+M39+/cfX7t2bT1AADGCNABdyA10nCgQiwGxJNAgqaysrHI3Nzd5kCtABn///h3sRXZgQQ5ig9I+sPY5f/3a9aW/fv96AtT3AohfAfE7EAYIIBaowV+BHBB+APK+uLi4jIuLS52pqSncQFBQgAxjBJclfxi4ubkZtm7dynDx4sWFQC1vGNAAQAAxoQvo6ekxBAYGOigoKEiADAG5lgkY9iAaZAFMDOQgc3NzfSDfmAELAAggFmQOSMPPnz8Ztm3bdvLEiRPzgAZJ/gM5FZY3GRnhVRTQMiZgxH+D+hQDAAQYAFDky9BqyKhOAAAAAElFTkSuQmCC"/></a>);
}

sub _view_address
{
	my ($self, $column) = @_;
	my $value = $self->$column;
	return unless $value;
	my $a = $value; 
	$a =~ s/([^A-Za-z0-9])/sprintf("%%%02X", ord($1))/seg;
	#add output=js for inline map
	return qq(<a href="http://gmodules.com/ig/ifr?url=http://ralph.feedback.googlepages.com/googlemap.xml&amp;up_locname=%20&amp;up_loc=$a\&amp;up_zoom=Street&amp;up_view=Map&amp;synd=open&amp;w=600&amp;h=340&amp;title=+&amp;border=%23ffffff%7C3px%2C1px+solid+%23999999&amp;" rel='iframe' title='$value :: Google Map :: width: 600, height: 340' class='lightview'>$value</a>);
}

sub _view_timestamp
{
	my ($self, $column) = @_;
	return unless $self->$column && ref $self->$column eq 'DateTime';
	$self->$column->set_time_zone('Australia/Sydney');
	return $self->$column->dmy('/').' '.$self->$column->hms;
}

sub _view_datetime
{
	my ($self, $column) = @_;
	return unless $self->$column && ref $self->$column eq 'DateTime';
	$self->$column->set_time_zone('Australia/Sydney');
	my $t = $self->$column->hms; 
	return $self->$column->dmy('/').' '.$self->$column->hour.':'.$self->$column->minute;
}

sub _search_boolean
{
	my ($self, $column, $value) = @_;
	my $mapping = {'Yes' => 1, 'No' => 0, 'yes' => 1, 'no' => 0};
	return $mapping->{$value};
}

sub _search_date
{
	my ($self, $column, $value) = @_;
	my ($d, $m, $y) = ($value =~ /(\d+)\/(\d+)\/(\d+)/);
	return unless $d && $m && $y;
	$d =~ s/^(\d{1})$/0$1/;
	$m =~ s/^(\d{1})$/0$1/;
	$y =~ s/^(0\d{1})$/20$1/;
	$y =~ s/^(9\d{1})$/19$1/;
	return join '-', ($y, $m, $d);
}

sub _search_time
{
	my ($self, $column, $value) = @_;
	my ($time) = ($value =~ /(\d{2}:\d{2}(:\d{2})?)/);
	my ($h, $m, $s) = split ':', $time;
	return unless $h && $m;
	$s ||= '00';
	return join ':', ($h, $m, $s);
}

sub _search_percentage
{
	my ($self, $column, $value) = @_;
	return unless $value;
	return $value/100;
}

sub _search_timestamp
{
	my ($self, $column, $value) = @_;
	my $date = _search_date($self, $column, $value);
	my $time = _search_time($self, $column, $value);
	return unless $date && $time;
	return $date.' '.$time;
}

sub _search_ipv4
{
	my ($self, $column, $value) = @_;
	return unless $value && $value =~ /^([0-1]??\d{1,2}|2[0-4]\d|25[0-5])\.([0-1]??\d{1,2}|2[0-4]\d|25[0-5])\.([0-1]??\d{1,2}|2[0-4]\d|25[0-5])\.([0-1]??\d{1,2}|2[0-4]\d|25[0-5])$/;
	return $value;
}

#misc util

sub _identify
{
	my ($class, $prefix, $ui_type) = @_;
	unless ($prefix)
	{
		$prefix = lc $class;
		$prefix =~ s/::/_/g;
		$prefix .= '_'. $ui_type;
	}
	return $prefix;	
}

sub _label
{
	my $string = shift;
	$string =~ s/_/ /g;
	$string =~ s/\b(\w)/\u$1/g;
	return $string;
}

sub _round_float
{
	my $value = shift;
	return unless $value ne '';
	(my $sign, $value) = ($value =~ /^(-)?(.*)/);
	my $nearest_value = nearest(.01, $value);
	if($nearest_value =~ /^\d+$/)
	{
		return $sign.$nearest_value.'.00';
	}
	elsif ($nearest_value =~ /^\d+\.[0-9]$/)
	{
		return $sign.$nearest_value.'0';
	}
	else
	{
		return $sign.$nearest_value;
	}
}

sub _create_hidden_field
{
	my $queries = shift;
	my $hidden_field;
	foreach my $query_key (keys %{$queries})
	{
		if (ref $queries->{$query_key} eq 'ARRAY')
		{
			foreach my $value (@{$queries->{$query_key}})
			{
				$hidden_field .= '<input name="'.$query_key.'" type="hidden" value="'.CGI::escapeHTML($value).'"/>';
			}
		}
		else
		{
			$hidden_field .= '<input name="'.$query_key.'" type="hidden" value="'.CGI::escapeHTML($queries->{$query_key}).'"/>';
		}
	}
	return $hidden_field;
}

sub _create_query_string
{
	my $queries = shift;
	my $query_string;
	foreach my $query_key (keys %{$queries})
	{
		if (ref $queries->{$query_key} eq 'ARRAY')
		{
			foreach my $value (@{$queries->{$query_key}})
			{
				$query_string .= $query_key.'='.CGI::escapeHTML($value).'&';
			}
		}
		else
		{
			$query_string .= $query_key.'='.CGI::escapeHTML($queries->{$query_key}).'&';
		}
	}
	return $query_string;
}

1;

__END__

=head1 NAME

Rose::DBx::Object::Renderer - Web UI Rendering for Rose::DB::Object

=head1 SYNOPSIS

  use Rose::DBx::Object::Renderer;

  use CGI;
  my $query = new CGI;
  print $query->header();

  # Load a MySQL database named 'company', which has two tables: 'employee' and 'position', where employee has a position
  my $renderer = Rose::DBx::Object::Renderer->new(config => {db => {name => 'company', username => 'root', password => 'root', tables_are_singular => 1}}, load => 1);
  
  
  # Render a form to add new employee
  Company::Employee->render_as_form();

  # Render an object as a form
  my $e = Company::Employee->new(id => 1);
  $e->load;
  $e->render_as_form();
  
  
  # Render a link to a google map for the 'address' column
  print $e->address_for_view();


  # Render a table
  Company::Employee::Manager->render_as_table();

  # Render a table for all the employees who love 'Coding' with create, edit, and delete access
  Company::Employee::Manager->render_as_table(
    get => {query => [hobby => 'Coding']}
    order => ['first_name', 'email', 'address', 'phone'],
    create => 1, 
    edit => 1,
    delete => 1,
    searchable => ['first_name', 'address']
  );

  # Render a menu
  my $menu = Company::Employee::Manager->render_as_menu(
    order => ['Company::Employee', 'Company::Position'],
    edit => 1,
    delete => 1,
  );


  # Render a pie chart via Google Chart API
  Company::Employee::Manager->render_as_chart(
    type => 'pie',
    values => ['Coding', 'Cooking'],
    column => 'hobby',
  );

  # Render a bar chart
  Company::Employee::Manager->render_as_chart(
    type => 'bar',
    title => 'The Employee Bar Chart',
    description => 'A useful bar chart.',
    columns => ['salary', 'tax'],
    objects => [1, 2, 3],
	options => {chco => 'ff6600,ffcc00'}  # the color for each bar
  );


=head1 DESCRIPTION

Rose::DBx::Object::Renderer generates web UIs for L<Rose::DB::Object>. It encapsulates many web conventions in the generated UIs as default behaviours. For example, email addresses are by default rendered as C<mailto> links in tables and appropiate validation is enforced automatically in forms. These behaviours are highly extensible. 

Renderer uses L<CGI::FormBuilder> to generate forms and the Google Chart API to render charts. L<Template::Toolkit> is used for template processing, however, Renderer can dynamically generate a full set of UIs without any templates.

=head1 RESTRICTIONS

=over 4

=item * Must follow the default conventions in L<Rose::DB::Object>.

=item * Limited support for database tables with multiple primary keys.

=back

=head1 METHODS

=head2 C<new>

To instantiate a new Renderer object:

  my $renderer = Rose::DBx::Object::Renderer->new(config => {db => {name => 'company', username => 'root', password => 'root'}}, load => 1);

Since Renderer inherits from L<Rose::Object>, the above line is equivalent to:

  my $renderer = Rose::DBx::Object::Renderer->new();
  $renderer->config({db => {name => 'company', username => 'root', password => 'root'}});
  $renderer->load();

=head2 C<config>

A Renderer instance inherits the default configurations in Renderer, which is accessible by:

  my $config = $renderer->config();

C<config> accepts a hashref for configuring the Renderer object.

=head3 C<db>

The C<db> option is for configuring database related settings, for instance:

  $renderer->config({
    db => {
      name => 'product',
      type => 'Pg', # defaulted to 'mysql'
      host => '10.0.0.1',
      port => '5432',
      username => 'admin',
      password => 'password',
      tables_are_singular => 1,  # defines the database table name conventions
      like_operator => 'ilike',  # to perform case-insensitive LIKE pattern matching
    }
  });

=head3 C<template>

The C<template> option specifies the template toolkit C<INCLUDE_PATH> and the base URL for static contents, such as javascript libraries or images:

  $renderer->config({
    ...
    template => {
      path => '../templates:../alternative',  # TT INCLUDE_PATH, defaulted to 'template'
      url => '../images',  # defaulted to 'template'
    },
  });

=head3 C<upload>

Renderer needs a directory with write access to upload files. The C<upload> option defines file upload related settings:

  $renderer->config({
    ...
    upload => {
      path => '../uploads',  # the upload directory path, defaulted to 'upload'
      url => '../uploads',  # the corresponding URL path, defaulted to 'upload'
      keep_old_files => 1,  # defaulted to undef
    },
  });

=head3 C<form>

The C<form> option defines the default behaviours of C<render_as_form>:

  $renderer->config({
    ...
    form => {
      download_message => 'Get Current File',  # the name of the link for uploaded files
      cancel => 'Back'  # the name of the built-in 'Cancel' controller
    },
  });

=head3 C<table>

The C<table> option defines the default behaviours of C<render_as_table>:

  $renderer->config({
    ...
    table => {
      search_result_title => 'Looking for "[% q %]"?',
      empty_message => 'No matching records.', 
      per_page => 25,  # number of records per table, defaulted to 15
      or_filter => 1,  # column filtering is joined by 'OR', defaulted to undef
      no_pagination => 1,  # do not display pagination
      delimiter => '/',  # the delimiter for joining foreign objects in relationship columns, defaulted to ', '
      keyword_delimiter => '\s+',  # the delimiter for search keywords, defaulted to ','
    },
  });

=head3 C<columns>

Renderer has a built-in list of column definitions that encapsulate web-oriented conventions and behaviours. A column definition is a collection of column options. Column definitions are used by the rendering methods to generate web UIs. The built-in column definitions are store inside C<columns>:

  my $config = $renderer->config();
  print join (', ', keys %{$config->{columns}});

For example, the column definition for 'email' would be:

  ...
  'email' => {
    required => 1,
    validate => 'EMAIL',
    sortopts => 'LABELNAME',
    comment => 'e.g. your.name@work.com',
    format => {
      for_view => sub {
        my ($self, $column) = @_;
        my $value = $self->$column;
        return unless $value;
        return qq(<a href="mailto:$value">$value</a>);}
    }
  },
  ...

We can also define new column definitions:

  $renderer->config({
    ...
    columns => {
      hobby => {
        label => 'Your Favourite Hobby',
        sortopts => 'LABELNAME',
        required => 1,
        options => ['Reading', 'Coding', 'Shopping']
     }
    },
  });

The options in each column definition are C<CGI::FormBuilder> field definitions, with the following additions:

=over

=item C<format>

The C<format> option is a hash of coderefs which get injected as object methods by C<load>. For instance, based on the 'email' column definition, we can print a 'mailto' link for the email address by calling:

  print $object->email_for_view;

Similarly, based on other column definitions, we can:

  # Print the date in 'DD/MM/YYYY' format
  print $object->date_for_view;

  # Store a password in MD5 hash
  $object->password_for_update('p@$$W0rD');
  $object->save();

  # Display an image formatted in HTML <img> tags
  print $object->image_for_view;

  # Print the url of the image
  print $object->image_url;

  # Prints the file path of the image
  print $object->image_path;

We can overwrite the existing formatting methods or define new ones. For instance, we can use the L<HTML::Strip> module to strip out HTML tags for the 'description' column type:

  use HTML::Strip;
  ...
  
  $renderer->config({
    ...
    columns => {
      description => {
        format => {
          for_update => sub {
            my ($self, $column, $value) = @_;
            return unless $value;
            my $hs = HTML::Strip->new(emit_spaces => 0);
            my $clean_text = $hs->parse($value);
            return $self->$column($clean_text);
          }
        }
      } 
    },
  });
  
  $renderer->load();
  ...
  $object->description_for_update('<html>The Lightweight UI Generator.</html>');
  $p->save();
  print $p->description;
  # prints 'The Lightweight UI Generator.'

Formatting methods are utilised by rendering methods. They take preference over the default CRUD methods. The C<for_create>, C<for_edit>, and C<for_update> methods are used by C<render_as_form>. When creating new objects, C<render_as_form> triggers the C<for_create> method to format the default value of a column. When rendering an existing object as a form, however, the C<for_edit> methods are triggered to format column values. During form submissions, the C<for_update> methods are triggered to format the submitted form field values. The C<for_view>, C<for_search>, and C<for_filter> methods are used by C<render_as_table>. The C<for_view> methods are triggered to format column values, the C<for_filter> methods are triggered for data filtering, and the C<for_search> methods are triggered for keyword searches.

=item C<unsortable>

This option defines whether a column is sortable. For instance, the 'password' column definition has the C<unsortable> option set to 1. This option is used by C<render_as_table>. Custom columns are always unsortable.

=item C<stringify>

This option specifies whether a column will be stringified by the C<stringify_me> object method.

=back

=head3 C<misc>

Other miscellaneous options are defined in C<misc>:

  my $custom_config = $renderer->config();

  # Print the built-in doctype and CSS
  print $custom_config->{misc}->{html_head};

  # Change the object stringify delimiter
  $custom_config->{misc}->{stringify_delimiter} = ', '; # defaulted to space

  $renderer->config($custom_config);
  $renderer->load();

=head2 C<load>

C<load> uses L<Rose::DB::Object::Loader> to load L<Rose::DB::Object> classes dynamically. In order to take advantages of the built-in column definitions, C<load> employs the following logic to auto-assign column definitions to database columns:

  Column name exists in the Renderer object's config?
    Yes: Use that column definition.
    No: Is the column a foreign key?
      Yes: Apply the column options designed for foreign keys.
      No: Column name matches (regex) a column definition name?
        Yes: Use the first matching column definition.
        No: Column's metadata object type exists as column definition name?
          Yes: Use that column definition.
          No: Create a custom column definition by aggregating database column information.


C<load> accepts a hashref to pass parameters to the C<new> and C<make_classes> methods in L<Rose::DB::Object::Loader>. 

=over

=item C<loader>

The C<loader> option is a hashref that gets to passed to the C<new> method in L<Rose::DB::Object::Loader>.

  $renderer->load({
    loader => {
      class_prefix => 'MyCompany',
    }
  });

=item C<make_classes>

Similarly, the C<make_classes> option is passed to the C<make_classes> method.

  $renderer->load({
    make_classes => {
      include_tables => ['customer', 'product'],
    }
  });

=back

C<load> returns an array of the loaded classes via the C<make_classes> method in L<Rose::DB::Object::Loader>. However, if the L<Rose::DB::Object> C<base_class> for the particular database already exists, which most likely happens in a persistent environment, C<load> will simply skip the loading process and return undef.

=head1 RENDERING METHODS

Rendering methods are exported for L<Rose::DB::Object> subclasses to generate web UIs. L<Rose::DB::Object> subclasses generated by calling C<load> will import the rendering methods automatically. However, we can also import the rendering methods into custom L<Rose::DB::Object> subclasses:

  # For object classes
  package Company::Employee
  use Rose::DBx::Object::Renderer qw(:object);
  ...
   
  # For manager classes 
  package Company::Employee::Manager
  use Rose::DBx::Object::Renderer qw(:manager);
  ...

Obviously, the rendering methods in the custom subclasses does not take advantages of the built-in column definitions and formatting methods. However, you can still replicate those behaviours by using the C<fields> option in C<render_as_form>, or the C<columns> option in C<render_as_table>, as well as hand crafting the formatting methods.

The following is a list of common parameters for the rendering methods:

=over 

=item C<template>

The template file name. When it is set to 1, rendering methods will try to find the default template based on the rendering method name. For example:

  Company::Employee->render_as_form(template => 1);
  # tries to use the template 'form.tt'

  Company::Employee::Manager->render_as_table(template => 1);
  # tries to use the template 'table.tt'

=item C<template_url>

The L<Template Toolkit>'s C<INCLUDE_PATH>.

=item C<template_path>

An URL path variable that is passed to templates.

=item C<template_options>

Optional parameters to be passed to L<Template Toolkit>. This is not applicable to C<render_as_form>.

=item C<html_head>

This is specifying custom DOCTYPE, CSS, or Javascript for the particular rendering method.

=item C<prefix> 

Define a prefix for the UI, e.g.:

  Company::Employee::Manager->render_as_table(prefix => 'employee_admin');

A prefix should be URL friendly. Adding a C<prefix> can prevent CGI param conflicts when rendering multiple UIs of the same class on the same web page.

=item C<title>

Define a title for the UI, e.g.:
  
  Company::Employee::Manager->render_as_table(title => 'Employee Directory');

=item C<description> 

Define a short description for the UI, e.g.:

  Company::Employee::Manager->render_as_table(description => 'Here you can view, search, and manage your employee details.');

=item C<no_head>

When set to 1, rendering methods will not include the default DOCTYPE and CSS. This is useful when rendering multiple UIs in the same page.

=item C<output>

When set to 1, the rendering methods will return the rendered UI instead of printing it directly. For example:
  
  my $form = Company::Employee->render_as_form(output => 1);
  print $form->{output};

=item C<extra>

A hashref of additional template variables. For example:

  Company::Employee->render_as_form(extra => {hobby => 'basketball'});

  # to access it within a template:
  [% extra.hobby %]

=back

Additionally, C<render_as_form> and C<render_as_table> also respectively accepts the all the options available inside the Renderer config's C<form> and C<table> hash.

=head2 C<render_as_form>

C<render_as_form> renders forms and handles its submission.

  # Render a form for creating a new object
  Company::Employee->render_as_form();
  
  # Render a form for updating an existing object
  my $e = Company::Employee->new(id => 1);
  $e->load;
  $e->render_as_form();

=over

=item C<order>

C<order> is an arrayref for the order of the form fields.

=item C<fields>

A hashref to specify the L<CGI::FormBuilder> field definitions for this particular C<render_as_form> call. Any custom fields must be included to the C<order> arrayref in order to be shown.

  Company::Employee->render_as_form(
    order => ['username', 'favourite_cuisine'],
    fields => {
    favourite_cuisine => {required => 1, options},
  });

Please note that Renderer has a built-in column type called 'confirm_password', where its default validation tries to match a field named 'password' in the form.

=item C<queries>

An arrayref of query parameters to be converted as hidden fields.

  Company::Employee->render_as_form(
    queries => {
    'rm' => 'edit',
    'favourite_cuisine' => ['French', 'Japanese']
  });

Please note that when a prefix is used, all fields are renamed to 'C<prefix_fieldname>'. 

=item C<controllers> and C<controller_order>

Controllers are essentially callbacks. We can add multiple custom controllers to a form. They are rendered as submit buttons. C<controller_order> defines the order of the controllers, in other words, the order of the submit buttons. 

  my $form = Employee::Company->render_as_form(
    output => 1,
    controller_order => ['Hello', 'Good Bye'],
    controllers => {
      'Hello' => {
        create => sub {
          return if DateTime->now->day_name eq 'Sunday';
          return 1;
        },
        callback => sub {
          my $self = shift;
          if (ref $self)
          {
            return 'Hello ' . $self->first_name;
          }
          else
          {
            return 'No employee has been created'.
          }
      },
      'Good Bye' => \&say_goodbye
    });

  if (exists $form->{controller})
  {
    print $form->{controller};
  }
  else
  {
    print $form->{output};
  }

  sub say_goodbye
  {
    return 'Good Bye';
  }

Within the C<controllers> hashref, we can set the C<create> parameter to 1 so that the object is always inserted into the database before running the custom callback. We can also point C<create> to a coderef, in which case, the object is inserted into the database only if the coderef returns true. 

Similarly, when rendering an object instance as a form, we can update the object before running the custom callback:

  ...
  $e->render_as_form(
    controllers => {
      'Hello' => {
        update => 1,
        callback => sub{...};
      }
  );

Another parameter within the C<controllers> hashref is C<hide_form>, which informs C<render_as_form> not to render the form after executing the controller.

=item C<form> 

A hashref that gets passed to the L<CGI::FormBuilder> constructor.

=item C<validate> 

Parameters for the L<CGI::FormBuilder>'s C<validate> method.

=item C<jserror>

When a template is used, C<render_as_form> sets L<CGI::FormBuilder>'s C<jserror> function name to 'C<notify_error>' so that we can always customise the error alert mechanism within the template (see the included 'form.tt' template).

=item C<javascript_code>

A string with javascript code to be added to the template

=back

C<render_as_form> passes the following list of variables to a template:
  
  [% self %] - the calling object instance or class
  [% form %] - CGI::FormBuilder's form object
  [% field_order %] - The order of the form fields
  [% form_id %] - the form id
  [% title %] - the form title
  [% description %] - the form description
  [% html_head %] - the html doctype and css defined in $Rose::DBx::Object::Renderer::CONFIG->{misc}->{html_head}
  [% no_head %] - the 'no_head' option
  [% extra %] - custom variables
  [% cancel %] - the name of the 'Cancel' controller
  [% javascript_code %] - javascript code 
  [% template_url %] - The template url defined in $Rose::DBx::Object::Renderer::CONFIG->{template}->{url}

=head2 C<render_as_table>

C<render_as_table> renders tables for CRUD operations. 

=over

=item C<or_filter>

C<render_as_table> allows columns to be filtered via URL. For example:

  http://www.yoursite.com/yourscript.pl?first_name=Danny&last_name=Liang

returns the records where 'first_name' is 'Danny' and 'Last_name' is 'liang'. By default, column queries are joined by "AND", unless C<or_filter> is set to 1.

=item C<columns>

The C<columns> parameter can be used to define custom columns, which do not exist in the underlying database table

  Company::Employee::Manager->render_as_table(
    columns => {'custom_column' => 
      label => 'Total',
      value => {
        1 => '100', # the 'Total' is 100 for object ID 1
        2 => '50'
      },
  });

=item C<order>

C<order> accepts an arrayref to define the order of the columns to be shown. The C<order> parameter also determines which columns are allowed to be filtered via url.

=item C<searchable>

The C<searchable> option enables keyword search in multiple columns, including the columns of foreign objects:

  Company::Employee::Manager->render_as_table(
    get => {with_objects => [ 'position' ]},
    searchable => ['first_name', 'last_name', 'position.title'],
  );

A search box will be shown in rendered table. The CGI param of the search box is called 'q', for example:
  
  http://www.yoursite.com/yourscript.pl?q=danny

We can also use multiple keywords seperated by commas. The default keyword delimiter is defined in:

  $Rose::DBx::Object::Renderer::CONFIG->{table}->{keyword_delimiter}

=item C<searchable>

=item C<get>

C<get> accepts a hashref to construct database queries. C<get> is directly passed to the C<get> method of the manager class.

  Company::Employee::Manager->render_as_table(
    get => {
	  per_page = 5,
      require_objects => [ 'position' ],
      query => ['position.title' => 'Manager'],
    });

=item C<controllers> and C<controller_order>

The C<controllers> parameter works very similar to C<render_as_form>. C<controller_order> defines the order of the controllers.

  Company::Employee::Manager->render_as_table(
	controller_order => ['edit', 'Review', 'approve'],
    controllers => {
      'Review' => sub{my $self = shift; do_something_with($self);}
      'approve' => {
	    label => 'Approve',
        hide_table => 1,
        queries => {approve => '1'}, 
        callback => sub {my $self = shift; do_something_else_with($self);
      }
    }
  );

Within the C<controllers> hashref, the C<queries> parameter allows us to define custom query strings for the controller. The C<hide_table> parameter informs C<render_as_table> not to render the table after executing the controller.

=item C<create> 

This enables the built-in 'create' controller when set to 1. 

  Company::Employee::Manager->render_as_table(create => 1);

Since C<render_as_form> is used to render the form, we can also pass a hashref to manipulate the generated form.

  Company::Employee::Manager->render_as_table(
    create => {title => 'Add New Employee', fields => {...}}
  );

=item C<edit>

Similar to C<create>, C<edit> enables the built-in 'edit' controller for updating objects.

=item C<delete>

When set to 1, C<delete> enables the built-in 'delete' controller for removing objects.

=item C<queries>

Similar to the C<queries> parameter in C<render_as_form>, C<queries> is an arrayref of query parameters, which will be converted to query strings. Please note that when a prefix is used, all query strings are renamed to 'C<prefix_querystring>'.

=item C<url>

Unless a url is specified in C<url>, C<render_as_table> will resolve the self url using CGI.

=item C<javascript_code>

A string with javascript code to be added to the template

=item C<ajax> and C<ajax_template>

These two parameters are designed for rendering Ajax-enabled tables. When C<ajax> is set to 1, C<render_as_table> tries to use the template 'table_ajax.tt' for rendering, unless the name of the template is defined in C<ajax_template>. C<render_as_table> also passes a variable called 'ajax' to the template and sets it to 1 when a CGI param named 'ajax' is set. We can use this variable in the template to differentiate whether the current CGI request is an ajax request or not.

=item C<no_pagination>

The pagination will not be rendered if this option is set to 1.

=back

Within a template, we can loop through objects using the C<[% table %]> variable. Alternatively, we can use the C<[% objects %]> variable.

C<render_as_table> passes the following list of variables to a template:
  
  [% table %] - the hash for the formatted table, see the sample template 'table.tt' 
  [% objects %] - the raw objects returned by the 'get_object' method
  [% column_order %] - the order of the columns
  [% template_url %] - The template URL defined in $Rose::DBx::Object::Renderer::CONFIG->{template}->{url}
  [% table_id %] - the table id
  [% title %] - the table title
  [% description %] - the table description
  [% class_label %] - title case of the calling package name
  [% no_pagination %] - the 'no_pagination' option
  [% q %] - the keyword query for search
  [% query_string %] - a hash of URL encoded query strings
  [% query_hidden_fields %] - CGI queries converted into hidden fields; it is used by the keyword search form
  [% param_list %] - a list of CGI param names with the table prefix, e.g. the name of the keyword search box is [% param_list.q %]
  [% searchable %] - the 'searchable' option
  [% sort_by_column %] - the column to be sorted 
  [% html_head %] - the html doctype and css defined in $Rose::DBx::Object::Renderer::CONFIG->{misc}->{html_head}
  [% no_head %] - the 'no_head' option
  [% extra %] - custom variables
  [% javascript_code %] - javascript code
  [% ajax %] - the ajax variable for checking whether the current CGI request is a ajax request
  [% url %] - the base url

=head2 C<render_as_menu>

C<render_as_menu> generates a menu with the given list of classes and renders a table for the current class. We can have fine-grained control over each table within the menu. For example, we can alter the 'date_of_birth' field inside the 'create' form of the 'Company::Employee' table inside the menu:

  Company::Employee::Manager->render_as_menu (
    order => ['Company::Employee', 'Company::Position'],
    items => {
    'Company::Employee' => {
      create => {
	    fields => {date_of_birth => {required => 1}}
	  }
    }
    'Company::Position' => {
	  title => 'Current Positions',
      description => 'important positions in the company'
    }},
    create => 1,
    edit => 1,
    delete => 1,
  );

=over

=item C<order>

The C<order> parameter defines the list of classes to be shown in the menu as well as their order. The current item of the menu is always the calling class, i.e. C<Company::Employee::Manager> in the example.

=item C<items>

The C<items> parameter is a hashref of parameters to control each table within the menu.

=item C<create>, C<edit>, C<delete>, and C<ajax>

These parameters are shortcuts which get passed to all the underlying tables rendered by the menu.

=back

C<render_as_menu> passes the following list of variables to a template:

  [% template_url %] - The template URL defined in $Rose::DBx::Object::Renderer::CONFIG->{template}->{url}
  [% menu_id %] - the menu id
  [% title %] - the menu title
  [% description %] - the menu description
  [% items %] - the hash for the menu items
  [% item_order %] - the order of the menu items
  [% current %] - the current menu item
  [% content %] - the output of the table
  [% extra %] - custom variables
  [% hide %] - whether the menu should be hidden
  [% html_head %] - the html doctype and css defined in $Rose::DBx::Object::Renderer::CONFIG->{misc}->{html_head}
  [% no_head %] - the 'no_head' option

=head2 C<render_as_chart>

C<render_as_chart> renders pie, line, and vertical bar charts via the Google Chart API.

=over

=item C<type>

This can be 'pie', 'bar', or 'line', which maps to the Google chart type (cht) 'p', 'bvg', and 'ls' respectively.

=item C<column> and C<values>

These two parameters are only applicable to pie charts. C<column> defines the column of the table in which the values are compared. The C<values> parameter is a list of values to be compared in that column, i.e. the slices.

=item C<columns> and C<objects>

These two parameters are only applicable to bar and line charts. C<columns> defines the columns of the object to be compared. The C<objects> parameter is a list of object IDs representing the objects to be compared.

=item C<options>

A hashref for specifying Google Chart API options, such as the chart type, size, labels, or data. This hashref is serialised into a query string.

=item C<engine>

Accepts a coderef to plug in your own charting engine.

=back

C<render_as_chart> passes the following list of variables to a template:

  [% template_url %] - The template URL defined in $Rose::DBx::Object::Renderer::CONFIG->{template}->{url}
  [% chart_id %] - the chart id
  [% title %] - the chart title
  [% description %] - the chart description
  [% chart %] - the chart
  [% options %] - the 'options' hash
  [% extra %] - custom variables
  [% html_head %] - the html doctype and css defined in $Rose::DBx::Object::Renderer::CONFIG->{misc}->{html_head}
  [% no_head %] - the 'no_head' option

=head1 OBJECT METHODS

Apart from the formatting methods injected by C<load>, there are several lesser-used object methods:

=head2 C<delete_with_file>

This is a wrapper of the object's C<delete> method to remove any uploaded files associated:

  $object->delete_with_file();

=head2 C<stringify_me>

Stringifies the object instance, e.g.:

  $object->first_name('John');
  $object->last_name('Smith');

  print $object->stringify_me;
  # prints 'John Smith';

=head2 C<stringify_class>

Stringifies the class name: 

  print Company::Employee->stringify_class;
  # prints 'company_employee'

=head1 SAMPLE TEMPLATES

There are four sample templates: 'form.tt', 'table.tt', 'menu.tt', and 'chart.tt' in the 'templates' folder of the TAR archive.

=head1 SEE ALSO

L<Rose::DB::Object>, L<CGI::FormBuilder>, L<Template::Toolkit>, L<http://code.google.com/apis/chart/>

=head1 AUTHOR

Xufeng (Danny) Liang (danny.glue@gmail.com)

=head1 COPYRIGHT & LICENSE

Copyright 2008 Xufeng (Danny) Liang, All Rights Reserved.

This program is free software; you can redistribute it and/or modify it under the same terms as Perl itself.

=cut
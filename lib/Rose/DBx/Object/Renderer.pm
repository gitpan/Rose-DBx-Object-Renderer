package Rose::DBx::Object::Renderer;

use strict;
use Carp;
use Exporter;

use vars qw(@ISA @EXPORT $VERSION $CONFIG);
@ISA = qw(Exporter);
@EXPORT = qw(load_database render_as_form render_as_table render_as_menu render_as_chart stringify_package_name stringify_me delete_with_file);

use Lingua::EN::Inflect qw (PL);
use Data::Dumper;
use DateTime;
use Rose::DB::Object::Loader;
use CGI::FormBuilder;
use Template;
use File::Path;
use Digest::MD5 qw(md5_hex);
use Math::Round qw(nearest);
use File::Copy::Recursive;
use Image::ExifTool qw(:Public);
use JSON::XS;
use Tie::Hash::Indexed;

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

our $VERSION = 0.15;
# build: 58.14

$CGI::FormBuilder::Field::VALIDATE{TEXT} = '/^\w+/';
$CGI::FormBuilder::Field::VALIDATE{PASSWORD} = '/^[\w.!?@#$%&*]{5,12}$/';
$CGI::FormBuilder::Field::VALIDATE{AUPHONE} = '/^((\()?(\+)?\d{2,3}(\))?)?\ ?\d{4}\ ?\d{4}$/';
$CGI::FormBuilder::Field::VALIDATE{MOBILE} = '/^((\()?(\+)?\d{2}(\))?)? ?(\d{3}|\d{4})\ ?\d{3}\ ?\d{3}\ ?$/';
$CGI::FormBuilder::Field::VALIDATE{EUDATE} = '/^(0?[1-9]|[1-2][0-9]|3[0-1])\/?(0?[1-9]|1[0-2])\/?[0-9]{4}$/';
$CGI::FormBuilder::Field::VALIDATE{URL} = '/^(\w+)://([^/:]+)(:\d+)?/?(.*)$/';

$CGI::FormBuilder::Field::VALIDATE{MONEY} = '/^\-?\d{0,11}(?:\.\d{2})?$/';
$CGI::FormBuilder::Field::VALIDATE{JPY} = '/^\-?\d{0,11}(?:\.\d{2})?$/'; 
$CGI::FormBuilder::Field::VALIDATE{EUR} = '/^\-?\d{0,11}(?:\.\d{2})?$/'; 

$CGI::FormBuilder::Field::VALIDATE{FILENAME} = '/^\S+[\w\s.!?@#$\(\)\'\_\-:%&*\/\\\\\[\]]{1,200}$/';

$CONFIG = 
{
	db => {
			type => 'mysql', 
			host => '127.0.0.1',
			port => undef,
			username => 'root', 
			password => 'root',
			tables_are_singular => 0
		},
	template => {path => 'templates', url => 'templates'},
	upload => {path => 'uploads', url => 'uploads'},
	table => {
				template => 'table.tt',
				ajax_template => 'table_ajax.tt',
				wait_message => 'Processing...',
				empty_message => 'No Record Found.',
				per_page => 15,
				js => {niftycube => 1, lightview => 1},
				search_operator => 'like', #e.g. use 'ilike' for case-insensitive search in Postgresql 
				or_filter => 0,
				no_pagination => 0,
			},
	form => {
				template => 'form.tt',
				wait_message => 'Processing...',
				download_message => 'Download File',
				keep_old_file => 0,
				js => {tooltip => 1, niftycube => 1, lightview => 1, tiny_mce => 1, datepicker => 1},
				cancel => 'Cancel'
			},
	menu => {template => 'menu.tt', js => {tooltip => 1, niftycube => 1, lightview => 1, tiny_mce => 1, datepicker => 1, plotr=>1}},
	chart => {template => 'chart.tt', js => {plotr=>1}},
	misc => {
				stringify_delimiter => ', ',
				join_delimiter => ', ',
				title_background_color => '#ABB6C4', #e.g. 91508E C292B8 1FBFDF CAF73A 
				content_background_color => '#ffffff',
				currency_symbol => {'AUD' => '$', 'JPY' => '&yen;', 'EUR' => '&#8364;', 'GBP' => '&#163;'},
				unit_of_length => 'cm',
				unit_of_weight => 'kg',
				unit_of_volume => 'cm<sup>3</sup>',
				html_head => '<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Transitional//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd"><head><title>[%title%]</title><style type="text/css">*{margin:0px;padding:0px;}body{font-family: "trebuchet ms", helvetica, sans-serif;font-size:small;color:#666666;}a{color:#ea440a;text-decoration: none;}a:hover{color:#F7710C;text-decoration: none;}p{margin:10px 20px;line-height: 180%;}form table{width:100%;}form td{border:0px;text-align:left;padding: 5px 20px;}form input, form textarea, form select{color: #666666;border: 1px solid #dddddd;background-color:#fff;margin-right: 10px;}form input[type="submit"]{padding:2px 7px;font-size:100%;}form input[type="text"]{padding-top:4px;}h2{font-size:300%;color:#aaa;font-weight:normal;}img{border:0px;}.light_container{padding:10px 10px 0px 10px;}.light_title_container{padding:30px 10px 0px 10px;}.light_table_searchable_container{width:100%;}.light_table_searchable{float:right;padding-top:6px;}.light_table_searchable_span{padding-right:3px;}.light_table_actions_container{position:relative;height:20px;}.light_table_actions{float:right;font-size:110%;padding-right:6px;}.light_table{width: 100%; border: 0px;padding:5px 10px; border-collapse:collapse;border-spacing:0px;}.light_table th, .light_table td{text-align: center;padding: 6px 2px;border-bottom: 1px solid #dddddd;}.light_table th{color:#666666;font-size:110%;font-weight:normal;background-color: #eee; padding:6px;}.light_menu{float:left;width:100%;background-color:#ddd;line-height:normal;}.light_menu ul{margin:0px;padding:10px 20px 0px 20px;list-style-type:none;}.light_menu ul li{display:inline;padding:0px;margin:0px;}.light_menu ul li a{float:left;display:block;color:#666;background:#d0d0d0;text-decoration:none;margin:0px 10px;padding:6px 20px;height:15px;}.light_menu ul li a:hover{background-color:#eee;color:#F7710C;}.light_menu ul li a.light_menu_current,.light_menu ul li a.light_menu_current:hover{cursor:pointer;background-color:#fff;}</style></head>'
			},
	validation => 
			{
				'Rose::DB::Object::Metadata::Column::Date' => 'EUDATE',
				'Rose::DB::Object::Metadata::Column::Integer' => 'INT',
				'Rose::DB::Object::Metadata::Column::BigInt' => 'INT',
				'Rose::DB::Object::Metadata::Column::Float' => 'FLOAT',
				'Rose::DB::Object::Metadata::Column::Decimal' => 'NUM',
				'Rose::DB::Object::Metadata::Column::DoublePrecision' => 'NUM',
				'Rose::DB::Object::Metadata::Column::Numeric' => 'NUM',
				'Rose::DB::Object::Metadata::Column::Time' => 'TIME'
			},
	columns => {
				'integer' => {validate => 'INT', sortopts => 'NUM', maxlength => 11},
				'decimal' => {validate => 'NUM', sortopts => 'NUM', maxlength => 14},
				'float' => {validate => 'FLOAT', sortopts => 'NUM', comment => 'e.g.: 109700.00', maxlength => 14},
				'varchar' => {sortopts => 'LABELNAME', maxlength => 255},
				'text' => {sortopts => 'LABELNAME', type => 'textarea', cols => '55', rows => '10', class=>'disable_editor'},
				'address' => {sortopts => 'LABELNAME', type => 'textarea', cols => '55', rows => '3', class=>'disable_editor', format => {for_view => sub {_view_address(@_);}}},
				'date' => {validate => 'EUDATE', sortopts => 'NUM', maxlength => 255, format => {for_edit => sub {my ($self, $column, $value) = @_;return $self->$column->dmy('/') if $self->$column;}, for_update => sub {my ($self, $column, $value) = @_;return $self->$column(undef) if $value eq ''; my ($d, $m, $y) = split '/', $value; my $dt = DateTime->new(year => $y, month => $m, day => $d, time_zone => 'Australia/Sydney'); return $self->$column($dt->ymd);}, for_search => sub {_search_date(@_);}, for_filter => sub {_search_date(@_);}, for_view => sub {my ($self, $column, $value) = @_;return unless ref $self->$column eq 'DateTime'; $self->$column->set_time_zone('Australia/Sydney'); return $self->$column->dmy('/') if $self->$column;}}},
				'timestamp' => {readonly => 1, disabled => 1, sortopts => 'NUM', maxlength => 255, format => {for_view => sub {_view_timestamp(@_);}, for_create => sub {_create_timestamp(@_);}, for_edit => sub {_view_timestamp(@_);}, for_update => sub {my ($self, $column, $value) = @_;return $self->$column(DateTime->now->set_time_zone( 'Australia/Sydney'));}, for_search => sub{_search_timestamp(@_);}, for_filter => sub{_search_timestamp(@_);}}},
				'description' => {sortopts => 'LABELNAME', type => 'textarea', cols => '55', rows => '10'},
				'time' => {validate => 'TIME', format => {for_update => sub {my ($self, $column, $value) = @_;return unless $value;my ($h, $m, $s) = split ':', $value; $s ||= '00';my $t = Time::Clock->new(hour => $h, minute => $m, second => $s);return $self->$column($t);}, for_search => sub {_search_time(@_);}, for_filter => sub {_search_time(@_);}, for_edit => sub{my ($self, $column, $value) = @_;return unless $self->$column;$value = $self->$column->as_string;my ($h, $m, $s) = split ':', $value;return "$h:$m";}, for_view => sub{my ($self, $column, $value) = @_;return unless $self->$column;$value = $self->$column->as_string;my ($h, $m, $s) = split ':', $value;return "$h:$m";}}},
				'length' => {validate => 'NUM', sortopts => 'NUM', maxlength => 14, format => {for_view => sub {my ($self, $column, $value) = @_;$value = $self->$column;return $value.' '.$CONFIG->{misc}->{unit_of_length};}}},
				'weight' => {validate => 'NUM', sortopts => 'NUM', maxlength => 14, format => {for_view => sub {my ($self, $column, $value) = @_;$value = $self->$column;return $value.' '.$CONFIG->{misc}->{unit_of_weight};}}},
				'volume' => {validate => 'NUM', sortopts => 'NUM', maxlength => 14, format => {for_view => sub {my ($self, $column, $value) = @_;$value = $self->$column;return $value.' '.$CONFIG->{misc}->{unit_of_volume};}}},
				'gender' => {options => ['Male', 'Female']},
				'title' => {sortopts => 'LABELNAME', required => 1, maxlength => 255, stringify => 1},
				'name' => {sortopts => 'LABELNAME', required => 1, maxlength => 255, stringify => 1},
				'first_name' => {validate => 'FNAME', sortopts => 'LABELNAME', required => 1, maxlength => 255, stringify => 1},
				'last_name' => {validate => 'LNAME', sortopts => 'LABELNAME', required => 1, maxlength => 255},
				'email' => {required => 1, validate => 'EMAIL', sortopts => 'LABELNAME', format => {for_view => sub {my ($self, $column, $value) = @_;$value = $self->$column;return qq(<a href="mailto:$value">$value</a>);}}, comment => 'e.g. your.name@work.com', maxlength => 255},
				'url' => {required => 0, validate => 'URL', sortopts => 'LABELNAME', format => {for_view => sub {my ($self, $column, $value) = @_;$value = $self->$column;return qq(<a href="$value" target = "_blank">$value</a>);}}, comment => 'e.g. http://www.google.com/', maxlength => 255},
				'mobile' => {validate => 'MOBILE', sortopts => 'NUM', maxlength => 15, comment => 'e.g. 0433 123 456'},
				'phone' => {validate => 'AUPHONE', sortopts => 'NUM', comment => 'e.g. 02 9988 1288', maxlength => 16},
				'username' => {validate => '/^[a-zA-Z0-9]{4,20}$/', sortopts => 'LABELNAME', required => 1, maxlength => 20},
				'password' => {validate => 'PASSWORD', sortopts => 'NUM', type => 'password', format => {for_view => sub {return '****';}, for_edit => sub {return;}, for_update => sub {my ($self, $column, $value) = @_;return $self->$column(md5_hex($value)) if $value;}}, comment => '5-12 characters', maxlength => 12, unsortable => 1},
				'confirm_password' => {required => 1, type => 'password', validate => {javascript => "!= form.elements['password'].value"}, maxlength => 12},
				'abn' => {label => 'ABN', validate => '/^(\d{2} \d{3} \d{3} \d{3})$/', sortopts => 'NUM', maxlength => 14, comment => 'e.g.: 12 234 456 678'},
				'money' => {validate => 'MONEY', sortopts => 'NUM', format => {for_view => sub {my ($self, $column, $value) = @_;$value = $self->$column;return unless $value ne '';my $rf = _round_float($value);return $CONFIG->{misc}->{currency_symbol}->{AUD}.$rf;}}, maxlength => 14},
				'percentage' => {validate => 'NUM', sortopts => 'NUM', comment => 'e.g.: 99.8', maxlength => 14, format => {for_view => sub {my ($self, $column, $value) = @_;$value = $self->$column;return unless $value;my $p = $value*100;return "$p%";}, for_edit => sub {my ($self, $column, $value) = @_;$value = $self->$column;return unless $value;return $value*100;}, for_update => sub {my ($self, $column, $value) = @_;return $self->$column($value/100) if $value;},  for_search => sub {_search_percentage(@_);}, for_filter => sub {_search_percentage(@_);}}},
				'foreign_key' => {validate => 'INT', sortopts => 'LABELNAME', format => {for_view => sub {my ($self, $column, $value) = @_;return unless $self->$column;my $fk = _get_foreign_keys(ref $self || $self);my $fk_name = $fk->{$column}->{name};return $self->$fk_name->stringify_me;}}},
				'document' => {validate => 'FILENAME', format => {path => sub {_get_file_path(@_);}, url => sub {_get_file_url(@_);}, for_update => sub {_update_file(@_);}, for_view => sub {_view_file(@_)}}, type => 'file'},
				'image' => {validate => 'FILENAME', format => {path => sub {_get_file_path(@_);}, url => sub {_get_file_url(@_);}, for_view => sub {_view_image(@_);}, for_update => sub {_update_file(@_);}}, type => 'file'},
				'media' => {validate => 'FILENAME', format => {path => sub {_get_file_path(@_);}, url => sub {_get_file_url(@_);}, for_view => sub {_view_media(@_);}, for_update => sub {_update_file(@_);}}, type => 'file'}
	}
};

$CONFIG->{columns}->{'label'} = clone($CONFIG->{columns}->{'varchar'});					
$CONFIG->{columns}->{'quantity'} = clone($CONFIG->{columns}->{'integer'});
$CONFIG->{columns}->{'height'} = clone($CONFIG->{columns}->{'length'});
$CONFIG->{columns}->{'width'} = clone($CONFIG->{columns}->{'length'});
$CONFIG->{columns}->{'depth'} = clone($CONFIG->{columns}->{'length'});
$CONFIG->{columns}->{'comment'} = clone($CONFIG->{columns}->{'text'});
$CONFIG->{columns}->{'note'} = clone($CONFIG->{columns}->{'text'});
$CONFIG->{columns}->{'birth'} = clone($CONFIG->{columns}->{'date'});
$CONFIG->{columns}->{'expire'} = clone($CONFIG->{columns}->{'date'});
$CONFIG->{columns}->{'fax'} = clone($CONFIG->{columns}->{'phone'});
$CONFIG->{columns}->{'cost'} = clone($CONFIG->{columns}->{'money'});
$CONFIG->{columns}->{'price'} = clone($CONFIG->{columns}->{'money'});
$CONFIG->{columns}->{'salary'} = clone($CONFIG->{columns}->{'money'});
$CONFIG->{columns}->{'balance'} = clone($CONFIG->{columns}->{'money'});
$CONFIG->{columns}->{'file'} = clone($CONFIG->{columns}->{'document'});
$CONFIG->{columns}->{'report'} = clone($CONFIG->{columns}->{'document'});
$CONFIG->{columns}->{'photo'} = clone($CONFIG->{columns}->{'image'});
$CONFIG->{columns}->{'sound'} = clone($CONFIG->{columns}->{'media'});
$CONFIG->{columns}->{'voice'} = clone($CONFIG->{columns}->{'media'});
$CONFIG->{columns}->{'video'} = clone($CONFIG->{columns}->{'media'});
$CONFIG->{columns}->{'movie'} = clone($CONFIG->{columns}->{'media'});
$CONFIG->{columns}->{'embed'} = clone($CONFIG->{columns}->{'text'});
$CONFIG->{columns}->{'markup'} = clone($CONFIG->{columns}->{'percentage'});
$CONFIG->{columns}->{'margin'} = clone($CONFIG->{columns}->{'percentage'});

sub load_database
{
	my ($db_name, $args, $args_for_make_classes) = (@_);
	return unless $db_name;

	unless ($args->{class_prefix})
	{
		$args->{class_prefix} = $db_name;
		$args->{class_prefix} =~ s/_(.)/\U$1/g;
		$args->{class_prefix} =~ s/[^\w:]/_/g;
		$args->{class_prefix} =~ s/\b(\w)/\u$1/g;		
	}

	return if "$args->{class_prefix}::DB::Object::AutoBase1"->isa('Rose::DB::Object');
	
	my $host;
 	$host = 'host='.$CONFIG->{db}->{host} if $CONFIG->{db}->{host};
	$host .= ';port='.$CONFIG->{db}->{port} if $CONFIG->{db}->{port};
	$args->{db_dsn} ||=  qq(dbi:$CONFIG->{db}->{type}:dbname=$db_name;$host);
	$args->{db_options} ||= { AutoCommit => 1, ChopBlanks => 1};
	$args->{db_username} ||= $CONFIG->{db}->{username} if $CONFIG->{db}->{username};
	$args->{db_password} ||= $CONFIG->{db}->{password} if $CONFIG->{db}->{password};

	my $loader = Rose::DB::Object::Loader->new(%{$args});
	$loader->convention_manager->tables_are_singular(1) if $CONFIG->{db}->{tables_are_singular};
	# $loader->base_class;
	
	my @loaded;
	foreach my $class ($loader->make_classes(%{$args_for_make_classes}))
	{
		my $package = qq(package $class;use Rose::DBx::Object::Renderer;use Rose::DB::Object::Util qw(:columns););
			
		if (($class)->isa('Rose::DB::Object'))
		{	
			my $relationships = _get_relationships($class);	
			my $column_order = _get_column_order($class, $relationships);
			my $foreign_keys = _get_foreign_keys($class);
			my $column_types = _match_column_types($class, $foreign_keys, $column_order);
			foreach my $column (keys %{$column_types})
			{
				foreach my $custom_method_key (keys %{$CONFIG->{columns}->{$column_types->{$column}}->{format}})
				{
					$package .= 'sub '.$column.'_'.$custom_method_key.'{my ($self, $value) = @_;return $Rose::DBx::Object::Renderer::CONFIG->{columns}->{'.$column_types->{$column}.'}->{format}->{'.$custom_method_key.'}->($self, \''.$column.'\', $value);'.'}';
				}
			}
		
			$package .= '__PACKAGE__->meta->initialize;';
		}
		else
		{
		
		}
		$package .= '1;';
		eval $package;
		die "Can't load $class." if $@;
		push @loaded, $class;
	}
	return @loaded;
}

sub render_as_form
{
	my ($self, %args) = (@_);
	return unless ($self)->isa('Rose::DB::Object');
	my ($object_id, $form_action, $field_order, $output);
	my $class = ref $self || $self;
	
	if (ref $self)
    {
		my $primary_key = $self->meta->{primary_key_column_accessor_names}->[0];
		$object_id = $self->$primary_key;		
		$form_action = 'update';
    }
    else
    {
		$object_id = 'new';
    	$form_action = 'create';
    }

	my $cancel = $args{cancel} || $CONFIG->{form}->{cancel};

	my $database = $self->meta->db->database;
	my $table = $self->meta->table;
	my $form_id = $args{prefix};
	unless ($form_id and $form_id ne 1)
	{
		$form_id = lc $class;
		$form_id =~ s/::/_/g;
		$form_id .= '_form';
	}
	
	my $form_template;
	
	if ($args{template} eq 1)
	{
		$form_template = $CONFIG->{form}->{template};
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

	my $relationships = _get_relationships($class);
	my $foreign_keys = _get_foreign_keys($class);
	my $relationship_object;
	
	my $column_order = $args{order} || _get_column_order(ref $self || $self, $relationships, $args{show_id});
	my $column_types = _match_column_types($class, $foreign_keys, $column_order);

	foreach my $column (@{$column_order})
	{		
		my $field_def;
		$field_def = _clean_column_info(clone($column_types->{$column})) if exists $column_types->{$column};

		if (exists $relationships->{$column}) #one to many or many to many relationships
		{
			delete $field_def->{type} if exists $field_def->{type} and $field_def->{type} eq 'file'; #relationships should not have a 'file' field type, in case $column_types thinks it's an image, etc.
			$field_def->{validate} = 'INT';
			
			my $foreign_primary_key = $relationships->{$column}->{class}->meta->{primary_key_column_accessor_names}->[0];
			
			if (ref $self)
			{
				my $foreign_object_value;
				
			 	foreach my $foreign_object ($self->$column)
				{
					$foreign_object_value->{$foreign_object->$foreign_primary_key} = $foreign_object->stringify_me;
					$relationship_object->{$column}->{$foreign_object->$foreign_primary_key} = undef; #keep it for update
				}
				$field_def->{value} = clone ($foreign_object_value);
			}
			
			my $object_options;
			my $foreign_package = $relationships->{$column}->{class}.'::Manager';
			my $objects = $foreign_package->get_objects;
			foreach my $object (@{$objects})
			{
				$object_options->{$object->$foreign_primary_key} = $object->stringify_me;
			}
			
			if ($object_options)
			{
				$field_def->{options} ||= $object_options;
				$field_def->{sortopts} ||= 'LABELNAME';
				$field_def->{multiple} ||= 1;
			}
			else
			{
				$field_def->{type} = 'select';
				$field_def->{disabled} = 1;
			}
			
		}
		elsif (map {$_ =~ /^$column$/} @{$class->meta->columns}) #normal column
		{	
			$field_def->{required} = 1 if $self->meta->{columns}->{$column}->{not_null};
			$field_def->{validate} = $CONFIG->{validation}->{ref $self->meta->{columns}->{$column}} if exists $CONFIG->{validation}->{ref $self->meta->{columns}->{$column}};
			$field_def->{maxlength} ||= $self->meta->{columns}->{$column}->{length} if $self->meta->{columns}->{$column}->{length};
			if (ref $self->meta->{columns}->{$column} eq 'Rose::DB::Object::Metadata::Column::Text')
			{
				$field_def->{type} ||= 'textarea';
				$field_def->{cols} ||= '55';
				$field_def->{rows} ||= '10';
			}
												
			if (exists $foreign_keys->{$column}) #create or edit
			{				
				my $options;
				my $foreign_manager = $foreign_keys->{$column}->{class}.'::Manager';
						
				my $foreign_primary_key = $foreign_keys->{$column}->{class}->meta->{primary_key_column_accessor_names}->[0];
					
				$field_def->{label} ||= _to_label($foreign_keys->{$column}->{name});
				$field_def->{required} ||= 1; #by default
				
				foreach my $foreign_object (@{$foreign_manager->get_objects})
				{
					$options->{$foreign_object->$foreign_primary_key} = $foreign_object->stringify_me;
				}
				 
				if ($options)
				{
					$field_def->{options} ||= $options;
					$field_def->{sortopts} ||= 'LABELNAME';
				}
				else
				{
					$field_def->{type} = 'select';
					$field_def->{disabled} = 1;
				}
			}
			
			$field_def->{options} ||= clone ($class->meta->{columns}->{$column}->{check_in}) if $class->meta->{columns}->{$column}->{check_in};
						
			$field_def->{multiple} = 1 if ref $self->meta->{columns}->{$column} eq 'Rose::DB::Object::Metadata::Column::Set';
			
			if (ref $self) #edit
			{
				my $current_value;
				if (defined &{"$class\::$column\_for_edit"})
				{
					my $edit_method = $column.'_for_edit';
					$current_value = $self->$edit_method;
					$field_def->{value} ||= "$current_value";
				}
				else
				{
					if (ref $self->meta->{columns}->{$column} eq 'Rose::DB::Object::Metadata::Column::Set')
					{
						$field_def->{value} ||= $self->$column;
					}
					else
					{
						$current_value = $self->$column;
						$field_def->{value} ||= "$current_value"; #double quote to make it literal to stringify object refs such as DateTime
					}
					
				}
									
				if (defined $field_def->{type} and $field_def->{type} eq 'file') #file: if value exist in db, or in cgi param when the same form reloads
				{							
					my $value = $form->cgi_param($form_id.'_'.$column) || $form->cgi_param($column) || $self->$column;
					$field_def->{comment} .= '<br/>' if $field_def->{comment};
					my $file_location = _get_file_url($self, $column, $value);
					$field_def->{comment} .= '<a href="'.$file_location.'" target = "_blank">'.$CONFIG->{form}->{download_message}.'</a>' if $file_location;
				}
			}
			else
			{
				if (defined $self->meta->{columns}->{$column}->{default})
				{
					if (defined &{"$class\::$column\_for_create"})
					{
						my $create_method = $column.'_for_create';
						my $create_result = $self->$create_method($self->meta->{columns}->{$column}->{default});
						$field_def->{value} ||= $create_result if $create_result;
					}
					else
					{
						$field_def->{value} ||= $self->meta->{columns}->{$column}->{default};
					}
				}
			}							
		}
		
		if (exists $args{fields} and exists $args{fields}->{$column})
		{	
			foreach my $property (keys %{$args{fields}->{$column}})
			{
				$field_def->{$property} = clone($args{fields}->{$column}->{$property});
			}
		}		
		
		delete $field_def->{value} if exists $field_def->{multiple} and $field_def->{multiple} and $form->submitted and not $form->cgi_param($column) and not $form->cgi_param($form_id.'_'.$column);
		
		$field_def->{label} ||= _to_label($column);
		
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
		
		push @{$args{controller_order}}, ucfirst ($form_action) unless exists $args{controllers} and exists $args{controllers}->{ucfirst ($form_action)};
		push @{$args{controller_order}}, $cancel unless exists $args{controllers} and exists $args{controllers}->{$cancel};
	}
	
	$form->{submit} = $args{controller_order};
		
	my $form_title = $args{title};
	ref $self?$form_title ||= _to_label($form_action.' '.$self->stringify_me()):$form_title ||= _to_label($form_action.' '.stringify_package_name($table));
	
	my $html_head;
	unless ($args{no_head})
	{
		$html_head = $CONFIG->{misc}->{html_head};
		$html_head =~ s/\[%title%\]/$form_title/;
	}
	
	$form->template({
						variable => 'form', 
						data => {
									template_url => $CONFIG->{template}->{url},
									js => $CONFIG->{form}->{js},
									javascript_code => $args{javascript_code},
									field_order => $field_order,
									actions => $args{actions},
									form_id => $form_id,
									title => $form_title,
									description => $args{description},
									html_head => $html_head,
									no_head => $args{no_head},
									title_background_color => $CONFIG->{misc}->{title_background_color},
									content_background_color => $CONFIG->{misc}->{content_background_color},
									self => $self,
									wait_message => $CONFIG->{form}->{wait_message},
									extra => $args{extra},
									cancel => $cancel,
								 },
						template => $form_template, 
						engine => {INCLUDE_PATH => $CONFIG->{template}->{path}}, 
						type => 'TT2'
					}) if $args{template};
	
	if ($form->submitted and $form->validate(%{$args{validate}}))
	{
		no strict 'refs';
		my $form_action_callback = '_'.$form_action.'_object';
		if (exists $args{controllers}->{$form->submitted} and $form->submitted ne $cancel) #method buttons
		{	
				
			if (ref $args{controllers}->{$form->submitted} eq 'HASH')
			{				
				if ($args{controllers}->{$form->submitted}->{$form_action})
				{
					unless (ref $args{controllers}->{$form->submitted}->{$form_action} eq 'CODE' and not $args{controllers}->{$form->submitted}->{$form_action}->($self))
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
	return unless ($self)->isa('Rose::DB::Object::Manager');
	my ($table, @controllers, $output, $previous_page, $next_page, $last_page, $total, $query_hidden_fields);
	my $class = ref $self || $self;
	$class =~ s/::Manager$//;
	
	my $query = $args{cgi} || CGI->new;
	my $url = $args{url} || $query->url(-absolute => 1);

	my $table_id = $args{prefix};
	unless ($table_id and $table_id ne 1)
	{
		$table_id = lc $class;
		$table_id =~ s/::/_/g;
		$table_id .= '_table';
	}
	
	my $table_title = $args{title} || _to_label(stringify_package_name($class->meta->table));
	
	my $relationships = _get_relationships($class);	
	my $column_order = $args{order} || _get_column_order($class, $relationships, $args{show_id});
	
	my $column_order_hash = {map {$_ => undef} @{$column_order}};
	my $foreign_keys = _get_foreign_keys($class);
	my $column_types = _match_column_types($class, $foreign_keys, $column_order);
	
	my $primary_key = $class->meta->{primary_key_column_accessor_names}->[0];
	
	my $param_list = {'sort_by' => 'sort_by', 'per_page' => 'per_page', 'page' => 'page', 'q' => 'q', 'ajax' => 'ajax', 'action' => 'action', 'object' => 'object', 'hide_table'};
	
	if ($args{prefix})
	{
		foreach my $param (keys %{$param_list})
		{
			$param_list->{$param} = $table_id.'_'.$param;
		}
	}	
	
	my $sort_by = $query->param($param_list->{'sort_by'});
	$sort_by =~ s/ desc//;
	
	#ignore nonexisting columns, relationship columns, and unsortable columns
	unless (not exists $column_order_hash->{$sort_by} or exists $relationships->{$sort_by} or (exists $column_types->{$sort_by} and exists $CONFIG->{columns}->{$column_types->{$sort_by}}->{unsortable} and $CONFIG->{columns}->{$column_types->{$sort_by}}->{unsortable}) or (exists $args{columns} and exists $args{columns}->{$sort_by}))
	{
		$args{get}->{sort_by} = $query->param($param_list->{'sort_by'});
	}	
	
	if ($args{searchable} and $query->param($param_list->{'q'})) 
	{
		my $or;
		foreach my $searchable_column (@{$args{searchable}})
		{
			my $search_value;
			if (defined &{"$class\::$searchable_column\_for_search"})
			{
				my $search_method = $searchable_column.'_for_search';
				my $search_result = $class->$search_method($query->param($param_list->{'q'}));
			 	$search_value = $search_result if $search_result;
			}
			else
			{
				$search_value = '%'.$query->param($param_list->{'q'}).'%';
			}			
			push @{$or}, $searchable_column => { $CONFIG->{table}->{search_operator} => $search_value} if $search_value;
		}
		
		# return {output => Dumper $or};
		push @{$args{get}->{query}}, 'or' => $or;
		
		$query_hidden_fields = _create_hidden_field($args{queries}); # this has to be done before appending 'q' to $args{queries} (next line), which get serialised later as query stings
		
		$args{queries}->{$param_list->{q}} = $query->param($param_list->{'q'});
		
		$table_title = 'Search Results for "'.$query->param($param_list->{'q'}).'"' unless $args{title};
	}
	
	if($args{or_filter} or $CONFIG->{table}->{or_filter})
	{
		my $or_filter;
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
					
					if (defined &{"$class\::$column\_for_filter"})
					{
						my $filter_method = $column.'_for_filter';
						my $formatted_values;
						foreach my $cgi_column_value (@cgi_column_values)
						{
							my $filter_result = $class->$filter_method($cgi_column_value);
							push @{$formatted_values}, $filter_result if $filter_result;
						}
						
						push @{$or_filter}, $column => $formatted_values;
					}
					else
					{
						push @{$or_filter}, $column => \@cgi_column_values;
					}
				}
			}
		}
		push @{$args{get}->{query}}, 'or' => $or_filter;
	}
	else
	{
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
					
					if (defined &{"$class\::$column\_for_search"})
					{
						my $search_method = $column.'_for_search';
						my $formatted_values;
						foreach my $cgi_column_value (@cgi_column_values)
						{
							push @{$formatted_values}, $class->$search_method($cgi_column_value);
						}						
						push @{$args{get}->{query}}, $column => $formatted_values;
					}
					else
					{
						push @{$args{get}->{query}}, $column => \@cgi_column_values; 
					}
				}
			}
		}
	}
		
	$args{get}->{per_page} ||= $query->param($param_list->{'per_page'}) || $CONFIG->{table}->{per_page};
	$args{get}->{page} ||= $query->param($param_list->{'page'}) || 1;	
	my $objects = $self->get_objects(%{$args{get}});

	##Handle Submission
	my $reload_object;
	if ($query->param($param_list->{action}))
	{
		if ($query->param($param_list->{action}) eq 'create' and $args{create})
		{
			$args{create} = {} if $args{create} eq 1;
			$args{create}->{output} = 1;
			$args{create}->{no_head} ||= 1 if $args{no_head};
			$args{create}->{order} ||= $args{order} if $args{order};
			
			$args{create}->{template} ||= 1 if $args{template} and not exists $args{create}->{template};
			
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
							if ($query->param($param_list->{action}) eq 'delete' and $args{delete})
							{
								$object->delete_with_file;
								$reload_object = 1;					
							}
							elsif($query->param($param_list->{action}) eq 'edit' and $args{edit})
							{
								$args{edit} = {} if $args{edit} eq 1;
								$args{edit}->{output} = 1;
								$args{edit}->{no_head} ||= 1 if $args{no_head};								
								$args{edit}->{order} ||= $args{order} if $args{order};
								
								$args{edit}->{template} ||= 1 if $args{template} and not exists $args{edit}->{template};
																
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
							elsif(exists $args{controllers} and exists $args{controllers}->{$query->param($param_list->{action})})
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
	
		$args{queries}->{$param_list->{ajax}} = 1 if $args{ajax} and $args{template};
		
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
		my $html_head;
		unless($args{no_head})
		{
			$html_head = $CONFIG->{misc}->{html_head};
			$html_head =~ s/\[%title%\]/$table_title/;
		}
		
		if ($args{create})
		{
			my $create_value = 'Create';
			$create_value = $args{create}->{title} if ref $args{create} eq 'HASH' and exists $args{create}->{title};
			$table->{create} = {value => $create_value, link => qq($url?$query_string->{complete}$param_list->{action}=create)} if $args{create};
		}
				
		$table->{actions} = $args{actions} if $args{actions};
		
		$table->{total_columns} = scalar @{$column_order} + scalar @controllers;
		
		foreach my $column (@{$column_order})
		{
			my $head;
			$head->{name} = $column;
						
			if (exists $args{columns} and exists $args{columns}->{$column} and exists $args{columns}->{$column}->{label})
			{
				$head->{value} = $args{columns}->{$column}->{label};				
			}
			elsif (exists $column_types->{$column} and exists $CONFIG->{columns}->{$column_types->{$column}}->{label})
			{
				$head->{value} = $CONFIG->{columns}->{$column_types->{$column}}->{label};
			}
			elsif(exists $foreign_keys->{$column})
			{
				$head->{value} = _to_label($foreign_keys->{$column}->{name});
			}
			else
			{
				$head->{value} = _to_label($column);
			}
		
			unless (not exists $column_order_hash->{$column} or exists $relationships->{$column} or (exists $column_types->{$column} and exists $CONFIG->{columns}->{$column_types->{$column}}->{unsortable} and $CONFIG->{columns}->{$column_types->{$column}}->{unsortable}) or (exists $args{columns} and exists $args{columns}->{$column}))
			
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
			if (ref $args{controllers}->{$controller} eq 'HASH' and exists $args{controllers}->{$controller}->{label}) 
			{
				$label = $args{controllers}->{$controller}->{label};
			}
			else
			{
				$label = _to_label($controller);
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
				if(exists $args{columns} and exists $args{columns}->{$column}) #custom column value
				{
					$value = $args{columns}->{$column}->{value}->{$object_id} if exists $args{columns}->{$column}->{value} and exists $args{columns}->{$column}->{value}->{$object_id};
				}
				elsif (exists $relationships->{$column})
				{
					$value = join $CONFIG->{misc}->{join_delimiter}, map {$_->stringify_me} $object->$column;
				}
				else
				{
					my $view_method;
					if (defined &{"$class\::$column\_for_view"})
					{
						$view_method = $column.'_for_view';
					}
					else
					{
						$view_method = $column;
					}
					
					if (ref $class->meta->{columns}->{$column} eq 'Rose::DB::Object::Metadata::Column::Set')
					{
						$value = join $CONFIG->{misc}->{join_delimiter}, $object->$view_method;
					}
					else
					{
						$value = $object->$view_method;
					}				
				}
				 
				push @{$row->{columns}}, {name => $column, value => $value};
			}
			
			foreach my $controller (@controllers)
			{
				my $label;
				if (ref $args{controllers}->{$controller} eq 'HASH' and exists $args{controllers}->{$controller}->{label}) 
				{
					$label = $args{controllers}->{$controller}->{label};
				}
				else
				{
					$label = _to_label($controller);
				}
				my $controller_query_string;
				if (ref $args{controllers}->{$controller} eq 'HASH' and exists $args{controllers}->{$controller}->{queries})
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
		    	$template = $args{ajax_template} || $CONFIG->{table}->{ajax_template};
		 		$ajax = 1 if $query->param($param_list->{ajax});
		    }
			elsif($args{template} eq 1)
			{
				$template = $CONFIG->{table}->{template};
			}
			else
			{
				$template = $args{template};
			}
		
	    		
			my $sort_by_column = $query->param($param_list->{'sort_by'});			
			$html_table = _render_template(options => $args{template_options}, file => $template, output => 1, data => 
			{
				template_url => $CONFIG->{template}->{url},
				js => $CONFIG->{table}->{js},
				javascript_code => $args{javascript_code},
				ajax => $ajax,
				url => $url,
				query_string => $query_string,
				query_hidden_fields => $query_hidden_fields,
				param_list => $param_list,
				sort_by_column => $sort_by_column,
				searchable => $args{searchable},
				table => $table,
				objects => $objects,
				column_order => $column_order,
				controllers => $args{controllers},
				controller_order => $args{controller_order},
				table_id => $table_id,
				title => $table_title,
				description => $args{description},
				class_label => _to_label(stringify_package_name($class->meta->table)),
				wait_message => $CONFIG->{table}->{wait_message},
				html_head => $html_head,
				no_head => $args{no_head},
				no_pagination => $args{no_pagination} || $CONFIG->{table}->{no_pagination},
				title_background_color => $CONFIG->{misc}->{title_background_color},
				content_background_color => $CONFIG->{misc}->{content_background_color},
				extra => $args{extra}
			});

		}
		else
		{			
			$html_table = $html_head;
			$html_table .= '<div class="light_container">';
			
			$html_table .= qq(<div class="light_table_searchable_container"><div class="light_table_searchable"><form action="$url" method="get" id="$table_id\_search_form"><label for="$table_id\_search"><span class="light_table_searchable_span">Search</span><input type="search" name="$param_list->{q}" id="$table_id\_search" accesskey="s"></label>$query_hidden_fields</form></div></div>) if $args{searchable};			
						
			$html_table .= qq(<div class="light_title_container"><h2>$table_title</h2><p>$args{description}</p></div>);
			$html_table .= qq(<div class="light_table_actions_container"><div class="light_table_actions">);
			$html_table .= qq(<a href="$table->{create}->{link}">$table->{create}->{value}</a>) if exists $table->{create};
			$html_table .= qq($table->{actions}) if exists $table->{actions};
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
				$html_table .= qq(<tr><td colspan="$table->{total_columns}"><p>$CONFIG->{table}->{empty_message}</p></td></tr>);
			}
			
			$html_table .= '</table>';
			
			unless ($args{no_pagination} || $CONFIG->{table}->{no_pagination})
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
	return unless  ($self)->isa('Rose::DB::Object::Manager');
	
	my $class = ref $self || $self;
	$class =~ s/::Manager$//;
	
	my $menu_id = $args{prefix};
	unless ($menu_id and $menu_id ne 1)
	{
		$menu_id = lc $class;
		$menu_id =~ s/::/_/g;
		$menu_id .= '_menu';
	}
	
	my ($hide_menu_param, $current_param);
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
	
	my $template;
	if ($args{template} eq 1)
	{
		$template = $CONFIG->{menu}->{template};
	}
	else
	{
		$template = $args{template};
	}
	
	my ($output, $content, $item_order, $items, $hide_menu, $menu_title, $current);
	
	$current = $query->param($current_param) || $class->meta->table;	
	
	$item_order = $args{order} || [$class];
	
	foreach my $item (@{$item_order})
	{
		my $table = $item->meta->table;
		$items->{$item}->{table} = $table;
		
		if (exists $args{items} and exists $args{items}->{$item} and exists $args{items}->{$item}->{title})
		{
			$items->{$item}->{label} = $args{items}->{$item}->{title};
		}
		else
		{
			$items->{$item}->{label} = _to_label($table);
		}
		
		$items->{$item}->{link} = qq($url?$query_string$current_param=$table);
		if ($table eq $current)
		{
			my $options;
			$options = $args{items}->{$item} if exists $args{items} and exists $args{items}->{$item};
			$options->{output} = 1;
			
			@{$options->{queries}}{keys %{$args{queries}}} = values %{$args{queries}};
			$options->{queries}->{$current_param} = $table;	
			$options->{prefix} ||= $menu_id.'_table';
			$options->{url} ||= $url;
			
			$options->{template} = 1 if $args{template} and not exists $options->{template};
			
			if ($args{ajax})
			{
				$hide_menu = 1 if $query->param($options->{prefix}.'_ajax') and $query->param($options->{prefix}.'_action') ne 'create' and $query->param($options->{prefix}.'_action') ne 'edit';
				$options->{ajax} = $args{ajax} unless defined $options->{ajax};
			}
			
			$options->{create} = 1 if $args{create} eq 1 and not exists $options->{create};
			$options->{edit} ||= 1 if $args{edit} eq 1 and not exists $options->{edit};
			$options->{delete} ||= 1 if $args{delete} eq 1 and not exists $options->{delete};
			
			$options->{no_head} = 1;
			$output->{table} = "$item\::Manager"->render_as_table(%{$options});
			$menu_title = $args{title} || $items->{$item}->{label};
		}
	}
	
	$hide_menu = 1 if $query->param($hide_menu_param);
	
	my($menu, $html_head);
	
	unless($args{no_head})
	{
		$html_head = $CONFIG->{misc}->{html_head};
		$html_head =~ s/\[%title%\]/$menu_title/;
	}
	
	if ($args{template})
	{
	 	$menu = _render_template(
			options => $args{template_options},
			file => $template, 
			output => 1, 
			data => {
				no_head => $args{no_head},
				html_head => $html_head,
				template_url => $CONFIG->{template}->{url}, 
				js => $CONFIG->{menu}->{js},
				items => $items,
				item_order => $item_order, 
				current => $current,
				title => $menu_title,
				description => $args{'description'},
				extra => $args{extra},
				content => $output->{table}->{output},
				hide => $hide_menu,
				});
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
			$menu .= '</ul></div></div><p>'.$args{'description'}.'</p>';
		}
		$menu .= $output->{table}->{output};
	}
		
	$args{output}?$output->{output} = $menu:print $menu;
	return $output;
}

sub render_as_chart
{
	my ($self, %args) = (@_);
	return unless  ($self)->isa('Rose::DB::Object::Manager') and $args{'type'};
	
	my $class = ref $self || $self;
	$class =~ s/::Manager$//;
	
	$args{title} ||= _to_label(stringify_package_name($class->meta->table));
	
	$args{'chart_id'} = $args{prefix};
	unless ($args{'chart_id'} and $args{'chart_id'} ne 1)
	{
		$args{'chart_id'} = lc $class;
		$args{'chart_id'} =~ s/::/_/g;
		$args{'chart_id'} .= '_chart';
	}
	
	my $hide_chart;
	if ($args{prefix})
	{
		$hide_chart = $args{'chart_id'}.'_hide_chart';
	}
	else
	{
		$hide_chart='hide_chart';
	}
	my $query = $args{cgi} || CGI->new;
	return if $query->param($hide_chart);
	
	$args{'chart_title'} ||= _to_label(stringify_package_name($class->meta->table));
	my $dataset_name = $args{'chart_title'};
	
	$args{'type'} = ucfirst($args{'type'});
	
	if($args{'type'} eq 'Pie')
	{
		$args{'size'} ||= 300;
		$args{'height'} = $args{'size'};
		$args{'width'} = $args{'size'};
		$args{'options'}->{'background'}->{'color'} ||= $CONFIG->{misc}->{content_background_color};
		$args{'options'}->{'legend'}->{'position'}->{'left'} ||= ($args{'size'} - 50).'px';
	}
	else #'Line' or 'Bar'
	{
		$args{'type'} ||= 'Bar';
		$args{'height'} ||= 300;	
		$args{'width'} ||= 600;
		$args{'options'}->{'padding'} ||= {left => 30, right => 0, top => 10, bottom => 30};
		$args{'options'}->{'barOrientation'} = 'horizontal' if $args{'type'} eq 'Bar' and $args{'horizontal'};
		$args{'options'}->{'shouldFill'} = 'false' if $args{'type'} eq 'Line' and not $args{'fill'};
	}
	
	if($args{'dataset'})
	{
		$args{'dataset'} = {$dataset_name => $args{'dataset'}} if ref $args{'dataset'} eq 'ARRAY';		
	}
	else
	{
		tie %{$args{'dataset'}}, 'Tie::Hash::Indexed';
		if($args{'type'} eq 'Pie')
		{
			my $foreign_keys = _get_foreign_keys($class);
			my $value_counter = 0;
			foreach my $value (@{$args{'values'}})
			{
				my $number = $self->get_objects_count(query => [ $args{column} => $value ]);
				next if $number == 0;
				my $label = $value;
				if (exists $foreign_keys->{$args{column}})
				{
					my $foreign_class = $foreign_keys->{$args{column}}->{class};
					my $foreign_primary_key = $foreign_class->meta->{primary_key_column_accessor_names}->[0]; 					
					my $foreign_object = $foreign_class->new($foreign_primary_key => $value);
			
					if($foreign_object->load(speculative => 1))
					{
						$label = $foreign_object->stringify_me;
					}
				}

				$args{'dataset'}->{$label} = [[0, $number]];
				push @{$args{'options'}->{'axis'}->{'x'}->{'ticks'}}, {v => $value_counter, label => $label};
							
				$value_counter++;
			}
		}
		else
		{
			my $column_counter = 0;
			my $primary_key = $class->meta->{primary_key_column_accessor_names}->[0]; 
			
			foreach my $column (@{$args{'columns'}})
			{
				my $object_counter = 0;
				foreach my $object_id (@{$args{'objects'}})
				{
					my $object = $class->new($primary_key => $object_id);
					if($object->load(speculative => $object_id))
					{
						my $value = $object->$column;
						push @{$args{'dataset'}->{_to_label($column)}}, [$object_counter, $value];
					}
					push @{$args{'options'}->{'axis'}->{'x'}->{'ticks'}}, {v => $object_counter, label => $object->stringify_me}; 
					$object_counter++;
				}
				
			}
		}
	}
	return unless %{$args{dataset}};
	_render_chart(%args); 
}

#rendering util

sub _render_chart
{
	my %args = (@_);

	$args{'options'}->{'strokeWidth'} = 1 unless exists $args{'options'}->{'strokeWidth'};
	$args{'options'}->{'colorScheme'} ||= 'blue';
	$args{'options'}->{'axis'}->{'labelColor'} 	||= '#ea440a';
	$args{'options'}->{'axis'}->{'labelFont'} 	||= 'trebuchet ms';
	$args{'options'}->{'background'}->{'color'} ||= '#E5ECF3';
	
	my $label_counter = 0;
	foreach my $label (@{$args{'label'}})
	{
		push @{$args{'options'}->{'axis'}->{'x'}->{'ticks'}}, {v => $label_counter, label => $label};
		$label_counter++;
	}
	
	$args{'options'} = encode_json($args{'options'});
	$args{'options'} =~ s/"(false)"/$1/g;
	$args{'options'} =~ s/"v":"(\d+)"/"v":$1/g;
	
	my $dataset;
	foreach my $key (keys %{$args{'dataset'}})
	{
		my $array = $args{'dataset'}->{$key};	
		push @{$dataset}, qq("$key":).encode_json($array);
	}
	
	$args{'dataset'} = join ',', @{$dataset};
	$args{'dataset'} = '{'.$args{'dataset'}.'}';
	
	$args{'dataset'} =~ s/"([.\d]+)"/$1/g;
	
	my ($output, $html_head);
	unless ($args{no_head})
	{
		$html_head = $CONFIG->{misc}->{html_head};
		$html_head =~ s/\[%title%\]/$args{title}/;
		$html_head .= qq(<script type="text/javascript" src="$CONFIG->{template}->{url}/js/prototype.js"></script><script type="text/javascript" src="$CONFIG->{template}->{url}/js/plotr/excanvas.js"/></script><script type="text/javascript" src="$CONFIG->{template}->{url}/js/plotr/plotr.js"/></script>);
	}
		
	my ($template, $chart);
	if ($args{template})
	{
		if($args{template} eq 1)
		{
			$template = $CONFIG->{chart}->{template};
		}
		else
		{
			$template = $args{template};
		}

		$chart = _render_template(
			options => $args{template_options},
			file => $template,
			output => 1,
			data => 
				{
					template_url => $CONFIG->{template}->{url},
					js => $CONFIG->{chart}->{js},
					dataset => $args{'dataset'},
					options => $args{'options'},
					height => $args{'height'},
					width => $args{'width'},
					chart_id => $args{'chart_id'},
					type => $args{'type'},
					title => $args{'title'},
					description => $args{'description'},
					no_head => $args{no_head},
					html_head => $html_head,
					extra => $args{'extra'}
				});		
	}
	else
	{
		$chart = $html_head.qq(<body><div class="light_container"><div class="light_title_container"><h2>$args{title}</h2><p>$args{description}</p></div><div><canvas id="$args{chart_id}_canvas" height="$args{height}" width="$args{width}"></canvas></div></div><script type="text/javascript">var $args{chart_id}_dataset = $args{dataset};var $args{chart_id}_options = $args{options};var $args{chart_id} = new Plotr.$args{type}Chart('$args{chart_id}_canvas',$args{chart_id}_options);$args{chart_id}.addDataset($args{chart_id}_dataset);$args{chart_id}.render();</script></body>);
	}

	$args{output}?$output->{output} = $chart:print $chart;
	return $output;
}

sub _render_template
{
	#never pass cgi param value as data, otherwise cause obscure behaviour
	my %args = (@_);
	if ($args{file} and $args{data})
	{
		my $options = $args{options};
		$options->{INCLUDE_PATH} ||= $CONFIG->{template}->{path};
		my $template = Template->new(%{$options});
		if($args{output})
		{
			my $output = '';
			$template->process($args{file},$args{data}, \$output) || die $template->error(), "\n";;
			return $output;
		}
		else
		{
			$template->process($args{file},$args{data});
		}
	}
}

#rdbo util

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
	
	my $primary_key = $self->meta->{primary_key_column_accessor_names}->[0];
	
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

			my $foreign_manager = $foreign_class.'::Manager';
			my $default = undef;
			$default = $relationships->{$column}->{class}->meta->{columns}->{$table.'_id'}->{default} if defined $relationships->{$column}->{class}->meta->{columns}->{$table.'_id'}->{default};
			
			if($form->cgi_param($field)) #check if field submitted. Empty value fields are not submited by browser, $form->field($field) won't work
			{ 
				my ($new_foreign_object_id, $old_foreign_object_id, $value_hash, $new_foreign_object_id_hash);
				
				my $foreign_primary_key = $relationships->{$column}->{class}->meta->{primary_key_column_accessor_names}->[0];
				
				foreach my $id (@values)
				{
					push @{$new_foreign_object_id}, $foreign_primary_key => $id;
					$value_hash->{$id} = undef;
					push @{$new_foreign_object_id_hash}, {$foreign_primary_key => $id};
				}
			
				foreach my $id (keys %{$relationship_object->{$column}})
				{
					push @{$old_foreign_object_id}, $foreign_primary_key => $id unless exists $value_hash->{$id};
				}
										
				if ($relationships->{$column}->{type} eq 'one to many')
				{					
					$foreign_manager->update_objects(set => { $foreign_key => $default}, where => [or => $old_foreign_object_id]) if $old_foreign_object_id;
					$foreign_manager->update_objects(set => { $foreign_key => $self->$primary_key}, where => [or => $new_foreign_object_id]) if $new_foreign_object_id;
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
					$foreign_manager->update_objects(set => { $foreign_key => $default}, where => [$foreign_key => $self->$primary_key]); # $self->$column([]) cascade deletes foreign objects
				}
				else #many to many
				{
					$self->$column([]);
				}
			
			}	
		}		
		elsif (defined &{"$class\::$column\_for_update"})
		{
			my $update_method = $column.'_for_update';
			if ($field_value ne '')
			{
				$self->$update_method($field_value);
			}
			else
			{
				$self->$update_method(undef);
			}
		
		}
		elsif (defined &{"$class\::$column"})
		{
			if ($field_value ne '')
			{
				$self->$column($field_value);
			}
			else
			{
				$self->$column(undef);
			}
		}
	}
	$self->save;
	return $self;
}

sub _create_object
{
	my ($self, $class, $table, $field_order, $form, $form_id, $prefix, $relationships, $relationship_object) = @_;	
	$self = $self->new();

	my $custom_field_value;
	
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
				my $foreign_primary_key = $relationships->{$column}->{class}->meta->{primary_key_column_accessor_names}->[0];
				
				foreach my $id (@values)
				{
					push @{$new_foreign_object_id_hash}, {$foreign_primary_key => $id};
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
			
			next if $field_value eq '';
			
			if (defined &{"$class\::$column\_for_update"})
			{
				my $update_method = $column.'_for_update';
				$custom_field_value->{$update_method} = $field_value; #save it for later
				$self->$column('0'); # zero fill for now
			}
			elsif (defined &{"$class\::$column"})
			{
				$self->$column($field_value);
			}
			
		}
	}
	
	$self->save; 

	#after save, run formatting methods, which may require an id, such as file upload
	foreach my $update_method (keys %{$custom_field_value})
	{
		$self->$update_method($custom_field_value->{$update_method});
	}
	$self->save;
	
	return $self;
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

sub _match_column_types
{
	my $class = shift;
	my $foreign_keys = shift;
	my $column_order = shift;
	my $type;
	
	foreach my $column (@{$column_order})
	{
		if (exists $CONFIG->{columns}->{$column})
		{
			$type->{$column} = "$column";
		}
		elsif (exists $foreign_keys->{$column})
		{
			$type->{$column} = 'foreign_key';
		}
		else
		{
			DEF: foreach my $column_key (keys %{$CONFIG->{columns}})
			{
				if ($column =~ /$column_key/) #random first match
				{
					$type->{$column} = $column_key;
					last DEF;
				}
			}
		}		
	}
	
	return $type;
}

sub delete_with_file
{
	my $self = shift;
	return unless ref $self;
	my $primary_key = $self->meta->{primary_key_column_accessor_names}->[0];
	my $directory = join '/', ($CONFIG->{upload}->{url}, $self->stringify_package_name, $self->$primary_key);
	rmtree($directory) || die ("Could not remove $directory") if -d $directory;
	return $self->delete();
}

sub stringify_me
{
	my $self = shift;
	my $primary_key = $self->meta->{primary_key_column_accessor_names}->[0];
	my $foreign_keys = _get_foreign_keys(ref $self);
	my $relationships = _get_relationships(ref $self);	
	my $column_order = _get_column_order(ref $self, $relationships);	
	my $column_types = _match_column_types(ref $self, $foreign_keys, $column_order);
	my @value;
	foreach my $column (@{$column_order})
	{
		push @value, $self->$column if exists $column_types->{$column} and $CONFIG->{columns}->{$column_types->{$column}}->{stringify};
	}
	
	my $string = join $CONFIG->{misc}->{stringify_delimiter}, @value;
	return $self->$primary_key unless $string;
	return $string;
}

sub stringify_package_name
{
	my $self = shift;
	my $package_name = lc ref $self || lc $self;
	$package_name =~ s/::/_/g;
	return $package_name;
}

sub _get_column_order
{	
	my ($class, $relationships, $show_id) = @_;
	my $order;
	foreach my $column (sort {$a->ordinal_position <=> $b->ordinal_position} @{$class->meta->columns})
	{
		push @{$order}, "$column" unless exists $column->{is_primary_key_member} and not $show_id;
	}
	
	foreach my $relationship (keys %{$relationships})
	{
		push @{$order}, $relationship;
	}
	return $order;
}

#file util

sub _get_file_path
{
	my ($self, $column, $value) = @_;
	$value ||= $self->$column;
	return unless $value;
	my $primary_key = $self->meta->{primary_key_column_accessor_names}->[0];
	return join '/', ($CONFIG->{upload}->{path}, $self->stringify_package_name, $self->$primary_key, $column, $value);
}

sub _get_file_url
{
	my ($self, $column, $value) = @_;
	$value ||= $self->$column;
	return unless $value;
	my $primary_key = $self->meta->{primary_key_column_accessor_names}->[0];
	return join '/', ($CONFIG->{upload}->{url}, $self->stringify_package_name, $self->$primary_key, $column, $value);
}

sub _view_file
{
	my ($self, $column, $value) = @_;
	$value ||= $self->$column;
	return unless $value and $value ne '' and ref $self;
	my $file_url = _get_file_url($self, $column);
	return qq(<a href="$file_url" target="_blank">$value</a>);
}

sub _view_image
{
	my ($self, $column, $value) = @_;
	$value ||= $self->$column;
	return unless $value and $value ne '' and ref $self;
	my $file_url = _get_file_url($self, $column);
	return qq(<img src="$file_url" alt = "$value"/>);
}

sub _view_media
{
	my ($self, $column, $value) = @_;
	$value = $self->$column;
	my $location = _get_file_url($self, $column);
	return unless $location;
	my $info = ImageInfo($location);
	my $dimension;
	$dimension = " :: width: $info->{ImageWidth}, height: $info->{ImageHeight}" if $info->{ImageWidth} and $info->{ImageHeight};
	return qq(<a href="$location" title="$value :: Media$dimension" class="lightview"><img src="data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAABYAAAAWCAYAAADEtGw7AAAABGdBTUEAAK/INwWK6QAAABl0RVh0U29mdHdhcmUAQWRvYmUgSW1hZ2VSZWFkeXHJZTwAAASlSURBVHjaYmxpaZlhYmLixcjI+Ovf//8MMPAfic3wH42PJv+fAcJmYmRk+vHjx/+mpqZWgABi3LVr10tXV1exb58/Mfz99Y2BgZERroERgwG2A8H9DzMSaCgzEwMTKw8DKzs7Q4C//zaAAGL58+fvz+9fPjIUt05jePiDl4GDjZXh/7//YBf9/wd1zz+EC8Hi/5Fc/R/kFhaGj2+fM6R5azBEhAUx/P37lwkggFhAEv/+/GJ49ZubwTU+h4GXhYHh+w8Ght+/GRj+/AHi3/8Zfv+BsP/+/Q+k/0PZEP5foKWsbCwMZ88cY3jx9hIDCzPYP/8BArA8RikAwzAItdTRFXb/y7bUvYV9iISQF3V0qs49rKcHNWpxTGqYWvhOQ5/zoHaqGW7JsKa7fPlvFL0CiAXkG0ZQqAEVA8MdKMkIpP+BXfkbaBLY5b//gV0J4oNcCvYJlA1yNfNfVoafP/+Dwx5kKDAhMAAEEAsokGDx9QekkPE/mP7zB2EAxFCQBQxQuf+IoAHyWf5Dggw5kgECiAXOA3kLpAFoC0wjDP+GWvAbySJw2COFM8hSRrhZ/xkAAogFkR4ZwZK/GZBcC9QMNuA31ODfSD74DbUAaCjTX0hkM0K9DjITIIBYGGApkfE/xHYmaDhCvQlLESCN8OBACZr/wMiG8CHmgtMfA0AAsYDNBImAYh7kNSaI4n9/ERGE4n0QG2rJb6g4IzSIgDkP7EyQiwECiOU/Uj779w8SXv+gkff3DyTcYbGPHO5/fv+HpxRwxP9GyfEMAAEECWNGsLMhhkIN/wulwb74C7Xk3394hoG59s8voO8Y/0NdzAAPWYAAYkGUAEzAHMTKwMoKTD5/mBn+gXLkf2jkgLI2MBwZ/0Johr/gkIOoAcK/oGD8xwZKuPACCSCAWEDlAjMzK8PXD28Ydu3ew8DHwQLOKH/hSQuUk5gg4Q1y6a+/UNf+hwfT///MDG+eXAXayQ9OcqBQAAggFhYWZub/zOwMxTH2DE9fvQPmdVDWZAZ6iwnqmX8MHz6+A5Ynf8FZloebC5p1GcGGgCLsFyjJ/FNh0FRXYfgJzKXMQDMAAojl/fv3P0HBbGNlwcDIxAQ26A8w8H7//gU2l5mZheHVq9fAsP8HDn9hYUEGNjY2sANAReXzN88ZxIUkGJhZWIE+/cHw7t07hi9fvjADBBCjvLy8j7q6epaMjIySmpqaiJKSEi8nJycryFZBQUFGISEhYLizMgC9BnTlP6Dmn6BiEZhy/jG8//D+/7U71xj+/fj36+7du1+A+M39+/cfX7t2bT1AADGCNABdyA10nCgQiwGxJNAgqaysrHI3Nzd5kCtABn///h3sRXZgQQ5ig9I+sPY5f/3a9aW/fv96AtT3AohfAfE7EAYIIBaowV+BHBB+APK+uLi4jIuLS52pqSncQFBQgAxjBJclfxi4ubkZtm7dynDx4sWFQC1vGNAAQAAxoQvo6ekxBAYGOigoKEiADAG5lgkY9iAaZAFMDOQgc3NzfSDfmAELAAggFmQOSMPPnz8Ztm3bdvLEiRPzgAZJ/gM5FZY3GRnhVRTQMiZgxH+D+hQDAAQYAFDky9BqyKhOAAAAAElFTkSuQmCC"/></a>);
}

sub _view_address
{
	my ($self, $column, $value) = @_;
	$value = $self->$column;
	my $a = $value; 
	$a =~ s/([^A-Za-z0-9])/sprintf("%%%02X", ord($1))/seg;
	my $primary_key = $self->meta->{primary_key_column_accessor_names}->[0];
	my $id = $self->stringify_package_name . $self->$primary_key .'modal';
	#add output=js for inline map
	return qq(<a id="$id" href="http://gmodules.com/ig/ifr?url=http://ralph.feedback.googlepages.com/googlemap.xml&amp;up_locname=%20&amp;up_loc=$a\&amp;up_zoom=Street&amp;up_view=Map&amp;synd=open&amp;w=600&amp;h=340&amp;title=+&amp;border=%23ffffff%7C3px%2C1px+solid+%23999999&amp;" rel='iframe' title='$value :: Google Map :: width: 600, height: 340' class='lightview'>$value</a>);
}

sub _update_file
{
	my ($self, $column, $value) = @_;
	return unless $value and $value ne '' and ref $self;
	my $primary_key = $self->meta->{primary_key_column_accessor_names}->[0]; 
	my $upload_path = join '/', ($CONFIG->{upload}->{path}, $self->stringify_package_name, $self->$primary_key, $column);	
	mkpath($upload_path) unless -d $upload_path;
	
	my $file_name = "$value";
	$file_name =~ s/.*[\/\\](.*)/$1/;
	
	my ($actual_name, $extension) = ($file_name =~ /(.*)\.(.*)$/);
	$actual_name ||= $file_name;
	
	my $current_file = $self->$column;
	
	my $old_file;
	$old_file = $upload_path.'/'.$current_file if $current_file;
	my $new_file = $upload_path.'/'.$file_name;
	
	if ($old_file eq $new_file and -e $old_file) # same file name
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
		unlink($old_file) unless not $old_file or $CONFIG->{form}->{keep_old_file};
		return $self->$column($file_name);
	}
	else
	{
		rename ($old_file, $upload_path.'/'.$current_file) if $old_file;
		return;
	}	
}

sub _upload_file
{
	my $upload_path = shift;
	my $file_name = shift;
	my $file = shift;
	return if not $file_name or $file_name =~ /^\s*$/ or not $upload_path;
	
	if (CGI::cgi_error() or !$file)
	{
		warn "Failed to upload file $file_name. Your file may reach the maximum file size.";
		return;
	}
	
	open FILE_HANDLER, ">$upload_path/$file_name" or die ("Could not open file handler for $upload_path/$file_name");
	while (<$file>)
	{
	   print FILE_HANDLER;
	}
	close FILE_HANDLER;
	return 1;
}

sub _search_date
{
	my ($self, $column, $value) = @_;
	my ($d, $m, $y) = ($value =~ /(\d+)\/(\d+)\/(\d+)/);
	return unless $d and $m and $y;
	$d =~ s/^(\d{1})$/0$1/;
	$m =~ s/^(\d{1})$/0$1/;
	$y =~ s/^(0\d{1})$/20$1/;
	$y =~ s/^(9\d{1})$/19$1/;
	return join '-', ($y, $m, $d);
}

sub _search_timestamp
{
	my ($self, $column, $value) = @_;
	my $date = _search_date($self, $column, $value);
	my $time = _search_time($self, $column, $value);
	return unless $date and $time;
	return $date.' '.$time;
}

sub _search_time
{
	my ($self, $column, $value) = @_;
	my ($time) = ($value =~ /(\d{2}:\d{2}(:\d{2})?)/);
	my ($h, $m, $s) = split ':', $time;
	$s ||= '00';
	return join ':', ($h, $m, $s);
}

sub _search_percentage
{
	my ($self, $column, $value) = @_;
	return unless $value;
	return $value/100;
}

sub _create_timestamp
{
	my ($self, $column, $value) = @_;
	my $dt = DateTime->now->set_time_zone( 'Australia/Sydney');
	my $t = $dt->hms; 
	$t =~ s/:\d{2}$//;
	return $dt->dmy('/').' '.$t;
}

sub _view_timestamp
{
	my ($self, $column, $value) = @_;
	return unless $self->$column and ref $self->$column eq 'DateTime';
	$self->$column->set_time_zone('Australia/Sydney');
	my $t = $self->$column->hms; 
	# $t =~ s/:\d{2}$//;
	return $self->$column->dmy('/').' '.$t;
}

#misc util

sub _clean_column_info
{
	my $column_type = shift;
	my $cloned_column_info = clone ($CONFIG->{columns}->{$column_type});
	delete $cloned_column_info->{format};
	delete $cloned_column_info->{stringify};
	delete $cloned_column_info->{unsortable};	
	return $cloned_column_info;
}

sub _to_label
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
	my $queries = clone(shift);
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
	my $queries = clone(shift);
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

  use CGI;
  my $query = new CGI;
  print $query->header();

  use Rose::DBx::Object::Renderer;

  # Load a database called 'company', which has two tables 'employee' and 'position' where employee has a position
  load_database('company', {db_username => 'root', db_password => 'root'});

  # Render a form to add employees
  Company::Employee->render_as_form();

  # Load an object
  my $e = Company::Employee->new(id => 1);
  $e->load;

  # Render a google map for the address column
  print $e->address_for_view();

  # Render a form with using the default template with custom fields
  $e->render_as_form(
    template => 1,
    fields => {'hobby' => {required => 1, options => ['Coding', 'Reading', 'Cooking']}},
  );


  # Render a table
  Company::Employee::Manager->render_as_table();

  # Render a table for all the employees who love to code with create, edit, and delete access
  Company::Employee::Manager->render_as_table(
    get => {query => [hobby => 'Coding']}
    order => ['first_name', 'email', 'address', 'phone'], # specify the column order
    create => 1, 
    edit => 1,
    delete => 1,
  );

  # Render a table with search and use a custom template
  Company::Employee::Manager->render_as_table(
    get => {require_objects => [ 'position' ]},
    searchable => ['first_name', 'last_name', 'position.title'],
    template => 'custom_template.tt'
  );


  # Render a menu
  my $menu = Company::Employee::Manager->render_as_menu (
    order => ['Company::Employee', 'Company::Position'], # the classes
    output => 1 # store the rendered menu
  );

  print $menu->{output};


  # Render a pie chart
  Company::Employee::Manager->render_as_chart(
    type => 'pie', # type of the chart
    values => ['Coding', 'Cooking'], # the values to compare
    column => 'hobby', # in which column
  );

  # Render a bar chart
  Company::Employee::Manager->render_as_chart(
    type => 'bar',
    title => 'The Employee Bar Chart', # set the title
    description => 'A useful bar chart.', # add some description
    columns => ['salary', 'tax'], # the columns to compare
    objects => [1, 2, 3] # for which objects
  );
	
=head1 DESCRIPTION

Rose::DBx::Object::Renderer generates web UIs for Rose::DB::Object. It encapsulates many web conventions in the generated UIs as default behaviours. For example, email addresses are by default rendered as C<mailto> links in tables and appropiate validation is enforced automatically in forms. These behaviours are highly configurable and extensible. 

Renderer integrates L<CGI::FormBuilder> to generate forms and Plotr to render charts. L<Template::Toolkit> is used for template processing, however, Renderer can generate a default set of UIs without any templates. Moreover, UIs are generated dynamically, in other words, no physical files are created.

=head1 RESTRICTIONS

=over 4

=item * The database table must follow the conventions in C<Rose::DB::Object>.

=item * Support for tables with multiple primary keys is limited.

=back

=head1 CONFIGURATION

C<$Rose::DBx::Object::Renderer::CONFIG> is an exported hash which defines many settings in Renderer. 

=head2 Database Connection

The C<load_database> method by default uses the settings defined in C<$Rose::DBx::Object::Renderer::CONFIG> to connect a database. 

  # Use the DBD for PostgreSQL (defaulted to 'mysql')
  $Rose::DBx::Object::Renderer::CONFIG->{db}->{type} = 'Pg'; 

  $Rose::DBx::Object::Renderer::CONFIG->{db}->{port} = '5543';
  $Rose::DBx::Object::Renderer::CONFIG->{db}->{username} = 'admin';
  $Rose::DBx::Object::Renderer::CONFIG->{db}->{password} = 'password';

  # Change the Rose::DB::Object convention such that database table names are singular 
  $Rose::DBx::Object::Renderer::CONFIG->{db}->{tables_are_singular} = 1;

=head2 Paths

The default TT INCLUDE_PATH is './template', which can be changed in: 

  $Rose::DBx::Object::Renderer::CONFIG->{template}->{path} = '../templates:../alternative';

Renderer also needs a directory with write access to upload files. The default upload path is './upload'.

  # Change the upload directory
  $Rose::DBx::Object::Renderer::CONFIG->{upload}->{path} = '../uploads';

  # Change the url for the upload directory
  $Rose::DBx::Object::Renderer::CONFIG->{upload}->{url} = '../uploads';

=head2 Default Settings for Rendering Methods

We can modify the default settings of the rendering methods, for example:

  # Change the default form template
  $Rose::DBx::Object::Renderer::CONFIG->{form}->{template} = 'custom_form.tt';

  # Change the default number of rows per page to 25 in tables
  $Rose::DBx::Object::Renderer::CONFIG->{table}->{per_page} = '25';

  # Use 'ilike' to perform case-insensitive searches in PostgreSQL
  $Rose::DBx::Object::Renderer::CONFIG->{table}->{search_operator} = 'ilike'; # defaulted to 'like'

  # Keep old upload files
  $Rose::DBx::Object::Renderer::CONFIG->{form}->{keep_old_file} = 1;

=head2 Column Definitions

Renderer embraces a built-in list of commonly-used column types in web applications, such as email, address, photo, document, and media. This list is defined in C<$Rose::DBx::Object::Renderer::CONFIG-E<gt>{columns}>. For those who are familiar with L<CGI::FormBuilder>, it is obvious that most of the values inside C<$Rose::DBx::Object::Renderer::CONFIG-E<gt>{columns}-E<gt>{column_name}> are in fact L<CGI::FormBuilder> field definitions, except for C<format>, C<unsortable>, and C<stringify>. We can create new column definitions simply by extending C<$CONFIG-E<gt>{columns}>.

=over

=item C<format>

Renderer encapsulates web-oriented behaviours by injecting the coderefs defined inside the C<format> hashref as object methods, for example:

  # Prints the localised DateTime object in 'DD/MM/YYYY' format
  print $object->date_for_view;

  # Prints the image column in formatted HTML
  print $object->image_for_view;

  # Prints the url of the image
  print $object->image_url;

  # Prints the file path of the image
  print $object->image_path;

In order to generate web-ready UIs, these extended object methods take preference over the the default object methods. The C<for_edit> and C<for_update> methods are used by C<render_as_form>. The C<for_edit> methods are triggered to format column values during form rendering, while the C<for_update> methods are triggered to update column values during form submission. Similarly, the C<for_view>, C<for_search>, and C<for_filter> methods are used by C<render_as_table>. The C<for_view> methods are used to format column values during table rendering, while the C<for_filter> and C<for_search> methods are respectively triggered for column filtering and keyword searches. 

We can customise existing formatting methods or define new ones easily. Let's say we would like to use the L<HTML::Strip> module to strip out HTML for the 'description' column:

  use HTML::Strip;
  ...
  $Rose::DBx::Object::Renderer::CONFIG->{columns}->{description}->{format}->{for_update} = sub{
    my ($self, $column, $value) = @_;
    return unless $value;
    my $hs = HTML::Strip->new(emit_spaces => 0);
    my $clean_text = $hs->parse($value);
    return $self->$column($clean_text);  
  };

We can always use the modified method directly:

  load_namespace('company');
  my $p = Company::Product->new(id => 1);
  $p->load;
  
  $p->description_for_update('<html>The Lightweight UI Generator.</html>');
  print $p->description;
  # which prints 'The Lightweight UI Generator.'
  
  $p->save();

We can create a custom method for the 'first_name' column so that users can click on a link to search the first name in CPAN:

  $Rose::DBx::Object::Renderer::CONFIG->{columns}->{first_name}->{format}->{in_cpan} = sub{
  my ($self, $column) = @_; 
  my $value = $self->$column; 
  return qq(<a href="http://search.cpan.org/search?query=$value&mode=all">$value</a>) if $value;
};
...
load_namespace('company');
my $e = Company::Employee->new(id => 1);
$e->load;
print $e->first_name_in_cpan;

# or use it directly inside a template: [% e.first_name_in_cpan %]

=item C<unsortable>

This parameter defines whether a column is a sortable column in tables. For example, the 'password' column is by default unsortable, i.e.:

  $Rose::DBx::Object::Renderer::CONFIG->{columns}->{password}->{unsortable} = 1;

Custom columns are always unsortable.

=item C<stringify>

This parameter specifies which columns are stringified. This is used by the exported C<stringify_me> object method.

  $Rose::DBx::Object::Renderer::CONFIG->{columns}->{first_name}->{stringify} = 1;

=back


=head1 METHODS

=head2 C<load_database>

C<load_database> loads database tables into classes using L<Rose::DB::Object::Loader>. In order to eliminate the need for manually mapping column definitions to database table columns, C<load_database> also tries to automatically assign a column definition to each column of the loaded classes by matching the column definition name with the database table column name. 

C<load_database> accepts three parameters. The first parameter is the database name, the second parameter is a hashref that gets passed directly to the L<Rose::DB::Object::Loader> constructor, while the last parameter is passed to the C<make_classes> method. C<load_database> always use the title case of the database name as the C<class_prefix> unless it is specified. C<load_database> returns an array of the loaded classes via the C<make_classes> method in L<Rose::DB::Object::Loader>. However, if the L<Rose::DB::Object> C<base_class> for the database already exists, which most than likely happens in a persistent environment, C<load_database> will simply skip the loading process and return nothing.

  load_database(
    'company',
    {db_username => 'admin', db_password => 'password'},
    {include_tables => ['employee','position']}
  );

=head2 Common Parameters in Rendering Methods

=over 

=item C<template>

A string to define the name of the TT template for rendering the UI. When it is set to 1, it will use the default templates defined in C<$CONFIG>. For instance, the default template for C<render_as_form> is defined in C<$CONFIG-E<gt>{form}-E<gt>{template}>.

=item C<prefix> 

A string to set a prefix for a UI. C<prefix> is used to prevent CGI param conflicts between multiple generated UIs on the same page.

=item C<title>

A string to set the title of the UI.

=item C<description> 

A string to set the description of the UI.

=item C<no_head>

When set to 1, rendering methods will not include the default DOCTYPE and CSS styles defined in C<$CONFIG-E<gt>{misc}-E<gt>{html_head}>. This is useful when rendering multiple UIs in the same page.

=item C<output>

When set to 1, the rendering methods would return the rendered UI instead of printing it directly. For example:
  
  my $form = Company::Employee->render_as_form(output => 1);
  print $form->{output};

=item C<extra>

A hashref of additional variables passed to the template.

	Company::Employee->render_as_form(extra => {hobby => 'basketball'});

=item C<template_options>

Optional parameters to be passed to template toolkit. This is not applicable to C<render_as_form>.

=back

=head2 C<render_as_form>

C<render_as_form> renders forms and handles the submission.

  # Render a form for creating a new object instance
  Company::Employee->render_as_form();
  
  # Render a form for updating an existing object instance
  my $e = Company::Employee->new(id => 1);
  $e->load;
  $e->render_as_form();

=over

=item C<order>

C<render_as_form> by default sorts all fields based on the column order of the underlying database table. C<order> accepts an arrayref to define the order of the form fields to be shown.

=item C<fields>

Accepts a hashref to overwrite the L<CGI::FormBuilder> field definitions auto-initialised by C<render_as_form>. Any custom fields must be included to the C<order> arrayref in order to be shown. 

  Company::Employee->render_as_form(
    order => ['username', 'password', 'confirm_password', 'favourite_cuisine'],
    fields => {
    password => {required => 1, class=> 'password_css'},
  });

Please note that 'confirm_password' is also a built-in column inside Renderer. The default validation Javascript will work automatically, unless the password field is not called 'password' or when a prefix is used, in which case, the validation code should be updated accordingly.  

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

=item C<cancel> 

C<render_as_form> has a built-in controller called 'Cancel'. C<cancel> is a string for renaming the default 'Cancel' controller in case it clashes with custom C<controllers>. 

=item C<form> 

Parameters for the L<CGI::FormBuilder> constructor.

=item C<validate> 

Parameters for the L<CGI::FormBuilder>'s C<validate> method.

=item C<jserror>

When a template is used, C<render_as_form> sets L<CGI::FormBuilder>'s C<jserror> function name to 'C<notify_error>' so that we can always customise the error alert mechanism within the template (see the included 'form.tt' template).

=item C<show_id> 

Shows the ID column (primary key) of the table as a form field when it is set to 1. This is generally not a very good idea except for debugging purposes.

=item C<javascript_code>

A string with javascript code to be added to the template

=back

C<render_as_form> calls L<CGI::FormBuilder>'s C<$form-E<gt>template()> method to process template. Thus, we can access the form object via the C<[% form %]> variable. Additionally, The order of the form fields are defined by C<[% field_order %]>. We can also access the calling object (or class) using the C<[% self %]> variable. 

=head2 C<render_as_table>

C<render_as_table> renders tables for CRUD operations. 

=over

=item C<or_filter>

C<render_as_table> allows columns to be filtered via URL. For example:

  http://www.yoursite.com/yourscript.pl?first_name=Danny&last_name=Liang

returns the object where 'first_name' is 'Danny' and 'Last_name' is 'liang'. By default, column queries are joined by "AND", unless C<or_filter> is set to 1.

=item C<columns>

The C<columns> parameter can be used to define custom columns which do not physically exist in the database table

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

C<searchable> enables search for multiple columns.

  Company::Employee::Manager->render_as_table(
    searchable => ['first_name', 'hobby'], #search for those fields
  );
  
  # A search box will be shown in rendered table. In the web browser, we can now do http://www.yoursite.com/yourscript.pl?q=coding 

=item C<get>

C<get> accepts a hashref to construct database queries. C<get> is directly passed to the get method of the manager class.

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

=item C<show_id> 

Shows the id column (primary key) of the table when it is set to 1. This can be also achieved using the C<order> parameter.

=item C<javascript_code>

A string with javascript code to be added to the template

=item C<ajax> and C<ajax_template>

These two parameters are designed for rendering Ajax-enabled tables. When C<ajax> is set to 1, C<render_as_table> will use the template defined either via the C<ajax_template> parameter or in C<$CONFIG-E<gt>{table}-E<gt>{ajax_template}>. C<render_as_table> also passes a variable called 'ajax' to the template and sets it to 1 when a CGI param called 'ajax' is set. We can use this variable in the template to differentiate whether the current request is an ajax request or not.

=back

Within a template, we can loop through objects using the C<[% table %]> variable. Alternatively, we can use the C<[% objects %]> variable.

=head2 C<render_as_menu>

C<render_as_menu> generates a menu with the given list of classes and renders a table for the current class. We can have fine-grained control over each table within the menu. For example, we can make the 'date_of_birth' field to be mandatory inside the 'create' form of the 'Company::Employee' table within the menu:

  my $menu = Company::Employee::Manager->render_as_menu (
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

The [% items %] variable passed to a template defines the menu item, which order is determined by the [% item_order %] variable.


=head2 C<render_as_chart>

C<render_as_chart> renders pie, line, and bar charts using Plotr, a Prototype-based Javascript charting library. By default, C<render_as_chart> assumes that the Prototype and Plotr libraries are located in: 

  $Rose::DBx::Object::Renderer::CONFIG->{template}->{url}/js/prototype.js
  $Rose::DBx::Object::Renderer::CONFIG->{template}->{url}/js/plotr/excanvas.js
  $Rose::DBx::Object::Renderer::CONFIG->{template}->{url}/js/plotr/plotr.js
  
Therefore, please make sure those Javascript libraries are in place when no custom template is used. 

=over

=item C<type>

This can be either 'pie', 'bar', or 'line'.

=item C<column> and C<values>

These two parameters are only applicable to pie charts. C<column> defines the column of the table in which the values are compared. The C<values> parameter is a list of values to be compared in that column, i.e. the slices.

=item C<columns> and C<objects>

These two parameters are only applicable to bar and line charts. C<columns> defines the columns of the object to be compared. The C<objects> parameter is a list of object IDs representing the objects to be compared.

=item C<dataset>

We can use a pre-populated dataset. In this case, C<render_as_chart> would simply convert the pre-populated hash to a JSON string and pass it to the template directly.

=back

C<[% type %]>, C<[% options %]>, and C<[% dataset %]> are the three main variables passed to a template for rendering charts. 

=head1 OBJECT METHODS

Apart from the formatting methods injected by C<load_namespace>, there are several other less-used object methods.

=head2 C<delete_with_file>

This is a wrapper of the object's C<delete> method to remove any uploaded files associated:

  $object->delete_with_file();

=head2 C<stringify_me>

The default C<stringify_me> method return a string by joining all the matching columns with the stringify parameter set to true. The default stringify delimiter is comma. 

  # Change the stringify delimiter to a space
  $Rose::DBx::Object::Renderer::CONFIG->{misc}->{stringify_delimiter} = ' '; 
  ...
  $object->title('Mr');
  $object->first_name('Rose');
  ...
  print $object->stringify_me();
  # prints 'Mr Rose';

This method is used internally to stringify foreign objects as form field values.

=head2 C<stringify_package_name>

This method stringifies the package name:

  print Company::Employee->stringify_package_name(); # Prints 'company_employee'

=head1 OTHER CONFIGURATIONS

=head2 Javascript

We can also specify the path to contents such as javascript libraries or images used within templates: 
  
  $Rose::DBx::Object::Renderer::CONFIG->{template}->{url} = '../docs/';
  
as well as which js libraries to include to the default template of a particular type of UI:

  $Rose::DBx::Object::Renderer::CONFIG->{form}->{js}->{datepicker} = 1;
  
Such that, in the actual TT template, we can do

  [% IF js.datepicker %]
    <script type="text/javascript" src="[% template_url %]/js/prototype.js"></script>
    <script type="text/javascript" src="[% template_url %]/js/scriptaculous/scriptaculous.js"/></script>
    <style type="text/css">@import url([% template_url %]/js/datepicker/datepicker.css);</style>
    <script type="text/javascript" src="[% template_url %]/js/datepicker/datepicker.js"/></script>
  [% END %]

The C<address_for_view> and C<media_for_view> object methods are also designed to work seamlessly with Lightview (L<http://www.nickstakenburg.com/projects/lightview/>), a Prototype based lightbox effect library. Simply include the appropriate Javascript libraries into your custom templates to enable the lightbox effect.

The default CSS class for the 'address' column is 'disable_editor'. This is for excluding the TinyMCE editor with this setup: C<editor_deselector : "disable_editor">. 

=head2 Miscellaneous

Other miscellaneous configurations are defined in:
  
  $Rose::DBx::Object::Renderer::CONFIG->{misc}

By default, the 'date', 'phone', and 'mobile' columns are localised for Australia.

=head2 Sample Templates

There are four sample templates: form.tt, table.tt, menu.tt, and chart.tt in the 'templates' folder inside the TAR archive of the module.

=head1 SEE ALSO

L<Rose::DB::Object>, L<CGI::FormBuilder>, L<Template::Toolkit>, L<http://solutoire.com/plotr/>

=head1 AUTHOR

Xufeng (Danny) Liang (danny.glue@gmail.com)

=head1 COPYRIGHT & LICENSE

Copyright 2008 Xufeng (Danny) Liang, All Rights Reserved.

This program is free software; you can redistribute it and/or modify it under the same terms as Perl itself.

=cut
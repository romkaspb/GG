package GG::Admin::Subscribe;

use utf8;

use Mojo::Base 'GG::Admin::AdminController';

my $DB_USERS = 'data_subscribe_users';
my $DB_STATS = 'data_subscribe_stat';

sub _init{
	my $self = shift;

	$self->def_program('subscribe');

	$self->get_keys( type => ['lkey', 'button'], controller => $self->app->program->{key_razdel});

	my $config = {
		controller_name	=> $self->app->program->{name},
		#controller		=> 'keys',
	};

	$self->stash->{list_table} ||= 'data_subscribe';

	$self->stash($_, $config->{$_}) foreach (keys %$config);

	$self->stash->{index} ||= $self->send_params->{index};

	unless($self->send_params->{replaceme}){
		$self->send_params->{replaceme} = $self->stash->{controller};
		$self->send_params->{replaceme} .= '_'.$self->stash->{list_table} if $self->stash->{list_table};
	}
	#$self->send_params->{replaceme} .= $self->stash->{index} || '';

	foreach ( qw(list_table replaceme)){
		$self->param_default($_ => $self->send_params->{$_} ) if $self->send_params->{$_};
	}

	$self->stash->{replaceme} = $self->send_params->{replaceme};
	$self->stash->{lkey} = $self->stash->{controller};
	$self->stash->{lkey} .= '_'. $self->send_params->{list_table} if $self->send_params->{list_table};
	$self->stash->{script_link} = '/admin/'.$self->stash->{controller}.'/body';

	$self->app->program->{groupname} = $self->app->program->{settings}->{'groupname_'.$self->stash->{list_table}} if($self->stash->{list_table} && $self->app->program->{settings}->{'groupname_'.$self->stash->{list_table}});
}

sub body{
	my $self = shift;

	$self->_init;

	my $do = $self->param('do');

	given ($do){

		when('list_container') 			{ $self->list_container; }
		when('list') 					{ $self->list_container; }
		when('enter') 					{ $self->list_container( enter => 1); }
		when('list_items') 				{ $self->list_items; }

		when('delete_pict') 			{ $self->field_delete_pict( render => 1, fields => [qw(pict)]); }
		when('field_upload_swf') 		{ $self->field_upload_swf; }
		when('file_upload_tmp') 		{ $self->render( text => $self->file_upload_tmp ); }

		when('menu_button') 			{
			$self->def_menu_button(
				key 		=> $self->app->program->{menu_btn_key},
				controller	=> $self->app->program->{key_razdel},
			);
		}

		when('filter_take') 			{ $self->filter_take( render => 1); }
		when('quick_view') 				{ $self->quick_view; }

		when('set_qedit') 				{ $self->set_qedit; }
		when('set_qedit_i') 			{ $self->set_qedit(info => 1); }
		when('save_qedit') 				{ $self->save_qedit; }
		when('save_qedit_i') 			{ $self->save_qedit; }

		when('filter') 					{ $self->filter_form; }
		when('filter_save') 			{ $self->filter_save; }
		when('filter_clear') 			{ $self->filter_clear();  $self->list_container(); }

		when('add') 					{ $self->edit( add => 1); }
		when('edit') 					{ $self->edit; }
		when('info') 					{ $self->info; }
		when('save') 					{ $self->save; }
		when('delete') 					{ $self->delete; }
		when('restore') 				{ $self->save( restore => 1); }

		when('send') 					{ $self->send_letter(); }

		when('lists_select') 			{ $self->lists_select; }

		default							{ $self->render_text("действие не определенно"); }
	}
}

sub send_letter{
	my $self = shift;
	my $subscribe_group = $self->dbi->query("SELECT `id_group` FROM `data_subscribe` WHERE `ID`='".$self->stash->{index}."'")->list;
	if ($self->getArraySQL( from => $self->stash->{list_table}, where => $self->stash->{index}, stash => 'anketa')) {
		if (my $users = $self->dbi->query("SELECT `ID` FROM `$DB_USERS` WHERE `active`=1 AND `email`!='' AND `id_group`='$subscribe_group'")->flat){

			my $subscribe_id = $self->stash->{index};
			my $dbh = $self->dbi->dbh;
			foreach (@$users){
				$dbh->do("REPLACE INTO `$DB_STATS` (`id_data_subscribe`, `id_user`) VALUES ($subscribe_id, $_)");
			}
		}
		$self->admin_msg_success( "Процесс рассылки сообщений запущен" );
		$self->dbi->dbh->do("UPDATE `".$self->stash->{list_table}."` SET `send`=1 WHERE `ID`=?", undef, $self->stash->{index});

	} else {
		$self->admin_msg_errors("Выбирете рассылку, к которой относиться данное письмо");
	}

	$self->info;
}

sub lists_select{
	my $self = shift;

	my $lfield = $self->param('lfield');
	$lfield =~ s{^fromselect}{};
	my $keystring = $self->param('keystring');

	my $selected_vals = $self->send_params->{$lfield};
	$selected_vals =~ s{=}{,}gi;

	my $sch = 0;
	my $list_out = "";

	my $where  = "`ID` > 0";
	   $where .= " AND `name` LIKE '%$keystring%' ORDER BY `name`";

	my (@array_lang);
	foreach ($self->dbi->getTablesSQL()) { if ($_ =~ m/texts_main_([\w]+)/) {push(@array_lang, $1);} }

	# Смотрим в разделах:
	for my $item ($self->dbi->query("SELECT `ID`,`name`,`key_razdel` FROM `lst_texts` WHERE $where")->hashes){
		my $name  = &def_name_list_select("Раздел: ", $item->{name});
		my $index = "$$item{key_razdel}:0";
		$list_out .= "lstobj[out].options[lstobj[out].options.length] = new Option('$name', '$index');\n" if $name;

		$sch++;
	}

	foreach my $l (@array_lang) {
		for my $item ($self->dbi->query("SELECT `ID`,`name` FROM `texts_main_${l}` WHERE $where")->hashes){
			my $name  = &def_name_list_select("Страница ($l): ", $item->{name});

			my $index = "$l:main:$$item{ID}";
			$list_out .= "lstobj[out].options[lstobj[out].options.length] = new Option('$name', '$index');\n" if $name;

			$sch++;
		}
	}
	$list_out .= "document.getElementById('ok_' + out).innerHTML = \"<span style='background-color:lightgreen;width:45px;padding:3px'>найдено: ".$sch."</span>\";\n";
	$self->render_text($list_out);

	sub def_name_list_select {
		my ($title, $name) = @_;

		$name =~ s/&laquo;/"/;
		$name =~ s/&raquo;/"/;
		$name =~ s/["']+//g;

		return $title.$name;
	}

}


sub delete{
	my $self = shift;

	$self->backup_doptable;

	if ($self->getArraySQL( from => $self->stash->{list_table}, where => $self->stash->{index}, stash => 'anketa')) {

		if($self->stash->{dop_table}){
			if($self->delete_info( from => $self->stash->{list_table}, where => $self->stash->{index})){
				$self->restore_doptable;
				return $self->field_dop_table_reload;
			}
		}

		if($self->delete_info( from => $self->stash->{list_table}, where => $self->stash->{index} )){

			if($self->stash->{anketa}->{pict}){
				$self->file_delete_pict(lfield => 'pict', folder =>  $self->stash->{anketa}->{folder}, pict => $self->stash->{anketa}->{pict});
			}

			# Удаление статистика к банeру
			$self->dbi->query("DELETE FROM `dtbl_banner_stat` WHERE `id_banner`='".$self->stash->{index}."'");
			$self->dbi->query("OPTIMIZE TABLE `dtbl_banner_stat`");

			$self->stash->{tree_reload} = 1;

			$self->save_logs( 	name 	=> 'Удаление записи из таблицы '.$self->stash->{list_table},
								comment	=> "Удалена запись из таблицы [".$self->stash->{index}."]. Таблица ".$self->stash->{list_table});

			$self->define_anket_form( noget => 1, access => 'd', table => $self->stash->{list_table});

		}

	} else {

	$self->save_logs( 	name 	=> 'Попытка удаления записи из таблицы '.$self->stash->{list_table},
						comment	=> "Неудачная попытка удаления записи из таблицы [".$self->stash->{index}."]. Таблица ".$self->stash->{list_table}.". ".$self->msg_no_wrap);

	$self->block_null;
	}

}

sub save{
	my $self = shift;
	my %params = @_;

	my $table = $self->stash->{list_table};

	$self->backup_doptable;

	$self->stash->{index} = 0 if $params{restore};
	my $ok = $self->save_info( table => $self->stash->{list_table});

	if($ok){

		if($params{restore}){
			$self->stash->{tree_reload} = 1;
			$self->save_logs( 	name 	=> 'Восстановление записи в таблице '.$self->stash->{list_table},
								comment	=> "Восстановлена запись в таблице [".$self->stash->{index}."]. Таблица ".$self->stash->{list_table}.". ".$self->msg_no_wrap);
			return $self->info;
		}

		$self->file_save_pict( 	filename 	=> $self->send_params->{pict},
								lfield		=> 'pict',
								fields		=> {pict => 'pict'},
								) if $self->send_params->{pict};

		if($self->stash->{group} >= $#{$self->app->program->{groupname}} + 1){
			return $self->info;
		}
		$self->stash->{group}++;
	}

	if($self->stash->{dop_table}){
		$self->restore_doptable;
		return $self->render_json({
				content	=> $self->has_errors ? "ERROR" : "OK",
				items	=> $self->init_dop_tablelist_reload(),
		});
	}

	return $self->edit;

}

sub info{
	my $self = shift;
	my %params = @_;

	my $table = $self->stash->{list_table};

	if ($self->send_params->{flag_add}) {
		$self->def_context_menu( lkey => 'add_info');
	} else {
		$self->def_context_menu( lkey => 'print_info');
	}

	if($self->stash->{index}){
		$self->getArraySQL(	from 	=> $self->stash->{list_table},
							where	=> "`ID`='".$self->stash->{index}."'",
							stash	=> 'anketa');
	}

	$self->define_anket_form( access => 'r', table => $table, noget => 1);
}

sub edit{
	my $self = shift;
	my %params = @_;

	$self->def_context_menu( lkey => 'edit_info');

	if($self->stash->{dop_table}){
		$self->backup_doptable();
	}

	if($self->stash->{index}){
		$self->getArraySQL(	from 	=> $self->stash->{list_table},
							where	=> "`ID`='".$self->stash->{index}."'",
							stash	=> 'anketa');

	}


	$self->define_anket_form( access => 'w', noget => 1);
}

sub list_container{
	my $self = shift;
	my %params = @_;

	$self->delete_list_items if $self->stash->{delete};

	$self->stash->{enter} = 1 if ($params{enter});

	$self->def_context_menu( lkey => 'table_list');

	$self->stash->{win_name} = "Список правил";

	$self->stash->{listfield_groups_buttons} = {delete => "удалить"};

	return $self->list_items(%params, container => 1)
}

sub list_items{
	my $self = shift;
	my %params = @_;

	my $list_table = $self->stash->{list_table};
	$self->render_not_found unless $list_table;

	$params{table} = $list_table;

	$self->define_table_list(%params);
}

1;
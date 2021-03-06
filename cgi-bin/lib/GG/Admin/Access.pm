package GG::Admin::Access;

use utf8;

use Mojo::Base 'GG::Admin::AdminController';

sub _init {
  my $self = shift;

  $self->def_program('access');

  $self->get_keys(
    type       => ['lkey', 'button'],
    controller => $self->app->program->{key_razdel}
  );

  my $config = {
    controller_name => $self->app->program->{name},

    #controller		=> 'keys',
  };

  $self->stash->{list_table} = 'sys_access';

  $self->stash($_, $config->{$_}) foreach (keys %$config);

  $self->stash->{index} ||= $self->send_params->{index};
  unless ($self->send_params->{replaceme}) {
    $self->send_params->{replaceme} = $self->stash->{controller};
    $self->send_params->{replaceme} .= '_' . $self->stash->{list_table}
      if $self->stash->{list_table};
  }

  #$self->send_params->{replaceme} .= $self->stash->{index} || '';

  foreach (qw(list_table replaceme)) {
    $self->param_default($_ => $self->send_params->{$_})
      if $self->send_params->{$_};
  }

  $self->stash->{replaceme} = $self->send_params->{replaceme};
  $self->stash->{lkey}      = $self->stash->{controller};
  $self->stash->{lkey} .= '_' . $self->send_params->{list_table}
    if $self->send_params->{list_table};
  $self->stash->{script_link}
    = '/admin/' . $self->stash->{controller} . '/body';
}

sub body {
  my $self = shift;

  $self->_init;

  my $do = $self->param('do');

  given ($do) {

    when ('list_container') { $self->list_container; }
    when ('update_access')  { $self->update_access; }

    default {
      $self->default_actions($do);
    }
  }
}

sub update_access {
  my $self = shift;

  foreach my $a ($self->dbi->query("SELECT * FROM `sys_access`")->hashes) {
    my $s;
    foreach my $k (sort keys %$a) {
      $s .= $a->{$k}
        if (defined $a->{$k}
        and $k ne 'cck'
        and $k ne "objectname"
        and $k ne 'created_at'
        and $k ne 'updated_at');
    }
    my $cck = $self->sysuser->def_cck_access($s);
    $self->dbi->update_hash(
      'sys_access',
      {cck => $cck},
      "`ID`='" . $a->{ID} . "'"
    );
  }
  $self->dbi->dbh->do("UPDATE `sys_users` SET `cck`='' WHERE `sys`='0'");
  $self->admin_msg_success("Права успешно обновлены");
  return $self->list_container;
}

sub tree {
  my $self = shift;

  my $folders
    = $self->getHashSQL(from => 'lst_group_user', where => "`ID`>0") || [];

  $self->stash->{param_default} .= "&first_flag=1";

  my $controller = $self->stash->{controller};
  my $table      = $self->stash->{list_table};

  foreach my $i (0 .. $#$folders) {
    $folders->[$i]->{replaceme} = $table . $folders->[$i]->{ID};
  }

  $self->render(folders => $folders, template => 'admin/tree_block');
}

sub tree_block {
  my $self = shift;

  my $items      = [];
  my $index      = $self->stash->{index};
  my $controller = $self->stash->{controller};

  if ($self->stash->{first_flag}) {
    $self->stash->{param_default} .= "&id_group_user=$index";

    $items = $self->getHashSQL(
      select => "`ID`,`name`",
      from   => 'sys_program',
      where  => "`ID`>0",
      sys    => 1
    ) || [];


    foreach my $i (0 .. $#$items) {
      $items->[$i]->{noclick}   = 1;
      $items->[$i]->{icon}      = 'folder';
      $items->[$i]->{flag_plus} = $self->getArraySQL(
        select => "`ID`",
        from   => 'sys_access',
        where  => "`modul`='"
          . $items->[$i]->{ID}
          . "' AND `id_group_user`='$index'"
      ) ? 1 : 0;
    }

    push @$items,
      {
      ID        => 999999,
      noclick   => 1,
      icon      => 'folder',
      flag_plus => $self->getArraySQL(
        select => "`ID`",
        from   => 'sys_access',
        where  => "`modul`='0' AND `id_group_user`='$index'"
        ) ? 1 : 0,
      name => 'Общие правила',
      };

  }
  else {
    $index = 0 if ($index == 999999);

    $items = $self->getHashSQL(
      select =>
        "`sys_access`.`ID`,`sys_access`.`objecttype` AS `name`,`objecttype`,`sys_program`.`name` AS `program_name`",
      from =>
        '`sys_access` LEFT JOIN `sys_program` ON `sys_access`.`modul`=`sys_program`.`ID`',
      where => "`sys_access`.`id_group_user`='"
        . $self->stash->{id_group_user}
        . "' AND `modul`='$index'",
      sys => 1
    ) || [];

    my $table = $self->stash->{list_table};
    $self->param_default('replaceme' => '');

    $self->def_list(name => 'objecttype', controller => 'access')
      unless $self->lkey(name => 'objecttype')->{list};
    my $objecttypeKey
      = $self->lkey(name => 'objecttype', controller => 'access');

    foreach my $i (0 .. $#$items) {
      $items->[$i]->{icon} = $items->[$i]->{objecttype};
      $items->[$i]->{replaceme}
        = $controller . '_' . $table . $items->[$i]->{ID};
      $items->[$i]->{name} = $objecttypeKey->{list}->{$items->[$i]->{name}};
      $items->[$i]->{param_default} = '&replaceme=' . $items->[$i]->{replaceme};
    }

  }

#	my $items = $self->getHashSQL(	from 	=> $self->param('index'),
#									where 	=> "`ID`>0");
#
#	my $table = $self->stash->{list_table};
#	foreach my $i (0..$#$items){
#		$items->[$i]->{name} = "<b>".$items->[$i]->{lkey}."</b> ".$items->[$i]->{name};
#		$items->[$i]->{key_element} = $table;
#		$items->[$i]->{icon} = $items->[$i]->{object};
#		$items->[$i]->{click_type} = 'text';
#		$items->[$i]->{param_default} = '&list_table='.$table.'&replaceme='.$self->stash->{controller}.'_'.$table.$items->[$i]->{ID};
#	}


  $self->render(
    json => {
      content => $self->render_to_string(
        items    => $items,
        template => 'admin/tree_elements'
      ),
      items => [
        {
          type  => 'eval',
          value => "treeObj['" . $self->stash->{controller} . "'].initTree();"
        },
      ]
    }
  );

}


sub save {
  my $self   = shift;
  my %params = @_;


  if ($self->param('objectname')) {
    my $objectname = $self->param('objectname');
    $objectname = join("=", split(/,/, $objectname));
    $objectname =~ s/^=//;
    $self->send_params->{objectname} = $objectname;
  }


  $self->stash->{index} = 0 if $params{restore};

  if ($self->save_info(table => $self->stash->{list_table})) {
    my $hash
      = $self->dbi->query("SELECT * FROM `"
        . $self->stash->{list_table}
        . "` WHERE `ID`='"
        . $self->stash->{index}
        . "'")->hash;

    my $a;
    foreach my $k (sort keys %$hash) {
      $a .= $hash->{$k}
        if (defined $hash->{$k}
        and $k ne 'cck'
        and $k ne "objectname"
        and $k ne 'created_at'
        and $k ne 'updated_at');
    }
    my $cck = $self->sysuser->def_cck_access($a);

    $self->update_hash(
      $self->stash->{list_table},
      {cck => $cck},
      "`ID`='" . $self->stash->{index} . "'"
    );

    if ($params{continue}) {
      return $self->edit;
    }

    if ($params{restore}) {
      $self->stash->{tree_reload} = 1;
      $self->save_logs(
        name => 'Восстановление записи в таблице '
          . $self->stash->{list_table},
        comment => "Восстановлена запись в таблице ["
          . $self->stash->{index}
          . "]. Таблица "
          . $self->stash->{list_table} . ". "
          . $self->msg_no_wrap
      );
      return $self->info;
    }

    if (
      $self->stash->{objecttype}
      && ( $self->stash->{objecttype} eq "modul"
        or $self->stash->{objecttype} eq "table")
      && $self->stash->{group} == 1
      )
    {
      $self->stash->{group} = 3;
      return $self->edit;
    }

    if ($params{continue}) {
      $self->admin_msg_success("Данные сохранены");
      return $self->edit;
    }
    elsif ($self->stash->{group} >= $#{$self->app->program->{groupname}} + 1) {
      return $self->info;
    }

    $self->stash->{group}++;

  }

  return $self->edit;

}

sub info {
  my $self   = shift;
  my %params = @_;

  my $table = $self->stash->{list_table};

  if ($self->send_params->{flag_add}) {
    $self->def_context_menu(lkey => 'add_info');
  }
  else {
    $self->def_context_menu(lkey => 'print_info');
  }
  $self->_def_objectname_list;

  $self->define_anket_form(access => 'r', table => $table);
}

sub edit {
  my $self   = shift;
  my %params = @_;

  $self->def_context_menu(lkey => 'edit_info');

  if ($self->stash->{group} == 3) {
    $self->_def_objectname_list;
  }
  else {
    $self->getArraySQL(
      from  => $self->stash->{list_table},
      where => "`ID`='" . $self->stash->{index} . "'",
      stash => 'anketa'
    );
    $self->stash->{objecttype} = $self->stash->{anketa}->{objecttype};
  }

  if (
    $self->stash->{objecttype}
    && ( $self->stash->{objecttype} eq "modul"
      or $self->stash->{objecttype} eq "table")
    && $self->stash->{group} == 2
    )
  {
    $self->stash->{group} = 3;

    $self->_def_objectname_list;
  }

  $self->define_anket_form(access => 'w');
}

sub list_container {
  my $self   = shift;
  my %params = @_;

  $self->delete_list_items if $self->stash->{delete};

  $self->stash->{enter} = 1 if ($params{enter});

  $self->def_context_menu(lkey => 'table_list');

  $self->stash->{win_name} = "Список правил";

  $self->stash->{listfield_groups_buttons} = {delete => "удалить"};

  return $self->list_items(%params, container => 1);
}

sub list_items {
  my $self   = shift;
  my %params = @_;

  my $list_table = $self->stash->{list_table};
  $self->render_not_found unless $list_table;

  $params{table} = $list_table;

  #$params{lkey} = $self->stash->{lkey};

  $self->define_table_list(%params);
}

sub _def_objectname_list {
  my $self = shift;
  my $vals = {};


  my $item = $self->getArraySQL(
    select => "`objecttype`,`modul`",
    from   => 'sys_access',
    where  => $self->stash->{index}
  );
  $self->stash->{objecttype} = $item->{objecttype};

  if ($item->{objecttype} eq 'table') {
    foreach ($self->dbi->getTablesSQL()) {
      my $fchars = substr($_, 0, 4);
      next if ($fchars eq 'keys' or $fchars eq 'sys_');
      $vals->{$_} = $_;    # if (($_ !~ m/^keys_/) );
    }

  }
  elsif ($item->{objecttype} eq 'modul') {
    if (
      my $pr = $self->getHashSQL(
        select => "`ID`,`name`",
        from   => 'sys_program',
        where  => "`ID`>0"
      )
      )
    {
      $vals->{$_->{ID}} = $_->{name} foreach (@$pr);
    }

  }
  elsif ($item->{objecttype} eq 'lkey'
    or $item->{objecttype} eq 'button'
    or $item->{objecttype} eq 'menu')
  {
    my $keys_table = $self->getArraySQL(
      select => "`keys_table`",
      from   => 'sys_program',
      where  => $item->{modul}
    );
    $keys_table ||= {};
    $keys_table->{keys_table} ||= 'keys_global';

    if (
      my $keys = $self->getHashSQL(
        select => "`ID`,`name`,`lkey`",
        from   => $keys_table->{keys_table},
        where =>
          "`object`='$$item{objecttype}' AND `settings` NOT LIKE '%sys=1%'",
        sys => 1
      )
      )
    {
      $vals->{$_->{lkey}} = $_->{name} . ' (' . $_->{lkey} . ')'
        foreach (@$keys);
    }
  }

  my $objectnameKey = $self->lkey(name => 'objectname', controller => 'access');
  $objectnameKey->{list} = $vals;
  $self->_def_list_labels($objectnameKey);
}


1;

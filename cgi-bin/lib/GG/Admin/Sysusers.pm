package GG::Admin::Sysusers;

use utf8;

use Mojo::Base 'GG::Admin::AdminController';

sub _init {
  my $self = shift;

  $self->def_program('sysusers');

  $self->get_keys(
    type       => ['lkey', 'button'],
    controller => $self->app->program->{key_razdel}
  );

  my $config = {controller_name => $self->app->program->{name},};

  $self->stash->{list_table} = 'sys_users';

  $self->stash($_, $config->{$_}) foreach (keys %$config);

  $self->stash->{index} ||= $self->send_params->{'index'};
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

  $self->def_access_where(base => 'sys_users', show_empty => 0);

  given ($do) {

    when ('list_container') { $self->list_container; }

    default {
      $self->default_actions($do);
    }
  }
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
  my $table      = $self->stash->{list_table};

  $self->param_default('replaceme' => '');

  my $where = $self->dbi->where_multiselect('id_group_user', $index);

  $items = $self->getHashSQL(
    select => "`ID`,`name`",
    from   => $table,
    where  => "$where " . $self->stash->{access_where},
    sys    => 1
  ) || [];

  foreach my $i (0 .. $#$items) {
    $items->[$i]->{icon}      = 'user';
    $items->[$i]->{replaceme} = $controller . '_' . $table . $items->[$i]->{ID};
    $items->[$i]->{param_default} = "&replaceme=" . $items->[$i]->{replaceme};
  }

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

  delete $self->send_params->{password_digest}
		unless $self->send_params->{password_digest};

  if ($self->save_info(%params, table => $self->stash->{list_table})) {

  # Добавляем текущего пользователя в список
    my $index = $self->stash->{index};

    $self->send_params({});

    my @users_list = split('=', $self->send_params->{users_list});
    push @users_list, $index unless (grep(/^$index$/, @users_list));
    $self->send_params->{users_list} = join('=', sort @users_list);

    $self->save_info(table => $self->stash->{list_table});

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
  $self->define_anket_form(access => 'r', table => $table);
}

sub edit {
  my $self   = shift;
  my %params = @_;

  $self->def_context_menu(lkey => 'edit_info');

  if ($self->stash->{index}) {
    $self->lkey(name => 'password_digest')->{name} = 'Новый пароль';
    $self->lkey(name => 'password_digest')->{settings}->{'required'} = 0;

  }
  else {
    $self->lkey(name => 'password_digest')->{settings}->{'required'} = 1;
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
  $params{where} = $self->stash->{access_where};

  $self->define_table_list(%params);
}

1;

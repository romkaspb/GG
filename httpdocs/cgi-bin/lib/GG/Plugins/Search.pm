package GG::Plugins::Search;

use utf8;
use Mojo::Base 'Mojolicious::Plugin';
use Encode;

our $VERSION = '1';

sub _config{
	my $self = shift;

	my $hash_table = {
		'texts_main_ru' => {
				searchfields 	=> [qw(name text)],
				primary_key 	=> [qw(ID)],
				controller 		=> 'text',
				route 			=> 'text',
				linktmlp 		=> '',
				mapfields 		=> {},
				where 			=> " `viewtext`=1 ",
			},
		'texts_news_ru' => {
				searchfields 	=> [qw(name text)],
				primary_key 	=> [qw(ID)],
				controller 		=> 'text',
				route 			=> 'news_item',
				linktmlp 		=> '',
				mapfields 		=> {
					alias 	=> 'list_item_alias',
				},
				where 			=> " `viewtext`=1 ",
			},
		'texts_events_ru' => {
				searchfields 	=> [qw(name text)],
				primary_key 	=> [qw(ID)],
				controller 		=> 'text',
				route 			=> 'events_item',
				linktmlp 		=> '',
				mapfields 		=> {
					alias 	=> 'list_item_alias',
				},
				where 			=> " `viewtext`=1 ",
			},
		'data_catalog_items' => {
				searchfields 	=> [qw(name article text)],
				primary_key 	=> [qw(sync variantcode)],
				controller 		=> 'catalog',
				route 			=> '',
				linktmlp 		=> '/catalog/item/%s~sync%_%s~variantcode%',
				where 			=> " `active`=1 ",
			},
	};

	return $hash_table;
}

sub register {
	my ($self, $app, $conf) = @_;


	$app->routes->route("search/result")->to( seo_title_sitename => 1, lang => 'ru', cb => sub{
		my $self   = shift;
		my %params = @_;

		$self->metaHeader({
			title	=> 'Поиск',
		});

		$params{page} = $self->stash('page') || 1;

		my $ksearch = $self->param('qsearch');

		$params{qsearch} = $ksearch;

		my $sch = 0;
		my (%result_search, @result_search_index);
		my ($search_str, $search_base);

		my $hash_table = _config($self);

		$ksearch =~ s/["']+//g;

		foreach my $table (keys %$hash_table) {
			$hash_table->{$table}->{primary_key} ||= [qw(ID)];

			my ($keyFieldSelect) = _buildKeyFieldsSelect( $hash_table->{$table}->{primary_key} );

			my $search = $ksearch;
			   $search =~ s/,/ /g;

			my (@search_str) = ();

			#$self->get_keys( type => ['lkey'], controller => $hash_table->{$table}->{controller} );

			my $dbi = $self->app->dbi;
			foreach my $k (split(/ /, $search)) {
				foreach my $f (@{ $hash_table->{$table}->{searchfields} } ){
					next unless (length($k) > 1);

					push(@search_str, "`$f` LIKE '%$k%'");
				}
			}
			$search_str = " ( ".join(" OR ", @search_str)." ) ";

			$search_str .= $hash_table->{$table}->{where} if $hash_table->{$table}->{where};

			if($search_str){
				for my $row  ($self->app->dbi->query("SELECT $keyFieldSelect FROM `$table` WHERE $search_str")->hashes){

					$result_search_index[$sch] = {
						table 		=> $table,
						primary_key	=> _buildKeyFieldsValue($hash_table->{$table}->{primary_key}, $row),
						controller  => $hash_table->{$table}->{controller},
					};

					$sch++;
				}
			}
		}

		#my $result_search_index = join("\n", @result_search_index);

		$params{count} = 0;
		$params{total_pages} = 0;

		if ($sch && $ksearch) {

			my $sth_insert = $self->app->dbh->prepare("REPLACE INTO `dtbl_search_results` (`idx`,`qsearch`,`table`,`controller`,`tdate`,`primary_key`) values (?, ?, ?, ?, NOW(), ?)");
			foreach my $i (0..$#result_search_index){
				$sth_insert->execute($i + 1, $ksearch, $result_search_index[$i]->{table}, $result_search_index[$i]->{controller}, $result_search_index[$i]->{primary_key} );
			}
			$sth_insert->finish();

			# $self->app->dbh->do("INSERT INTO `dtbl_search_results` (`qsearch`,`tdate`,`res_search_indx`) values (\"$ksearch\", NOW(), \"$result_search_index\")");
			# $params{index} = $self->app->dbh->{'mysql_insertid'};

			# $self->app->dbh->do("DELETE FROM `dtbl_search_results` WHERE TO_DAYS(NOW()) - TO_DAYS(`tdate`) > 1");
			# $params{found} = 1;
		}
		print_search_result($self, %params);

	})->name('search');

}

sub _buildKeyFieldsSelect{
	my $keyField = shift || [qw(ID)];

	my $keyFieldSelect = join(",", map{ "`$_`" } @$keyField );
	return $keyFieldSelect;
}


sub _buildKeyFieldsValue{
	my $keyField = shift || [qw(ID)];
	my $row = shift;

	return join('_', @$row{ @$keyField } );

}

sub print_search_result{
	my $self = shift;
	my %params = (
		limit 	=> 0,
		qsearch => '',
		index 	=> 0,
		@_
	);

	my $qsearch = $params{qsearch};

	my $search_items = $self->dbi->query("SELECT * FROM `dtbl_search_results` WHERE `qsearch`='$qsearch' ORDER BY `idx`")->hashes || [];

	my $hash_table = _config($self);

	my $result_items = [];

	foreach my $row (@$search_items){
		my $table = $row->{table};

		my @primaryVals = split('_', $row->{primary_key});
		my $whereIndex = '';
		foreach my $i (0..$#primaryVals){
			$whereIndex .= " AND `".$hash_table->{$table}->{primary_key}->[$i]."`='$primaryVals[$i]' ";
		}

		if (my $node = $self->app->dbi->query("SELECT * FROM `$table` WHERE 1 $whereIndex ")->hash) {

			if(my $mapfields = $hash_table->{$table}->{mapfields}){
				$node->{ $mapfields->{$_} } = $node->{ $_ } foreach keys %$mapfields;
			}

			if( $node->{text} ) {
				$node->{text} =~ s/<.*?>//gi;

				my $cutSize = 300;
				if($node->{text} =~ /([\s\S]*?)$qsearch([\s\S]*)/){
					my $pref = $1;
					my $post = $2;

					if( length($pref) > $cutSize ){
						$pref = substr( $pref, length($pref) - $cutSize);

						if ( $pref =~ m/ / ) {
							while ( substr( $pref, 0, 1 ) ne ' ' ){
								$pref = substr( $pref, 1);
							}
						}
					}

					if( length($post) > $cutSize ){
						$post = substr( $post, 0, $cutSize - 1 );

						if ( $post =~ m/ / ) {
							while ( substr( $post, length($post) - 1, 1 ) ne ' ' ) {
								$post = substr( $post, 0, length($post) - 1 );
							}
						}
					}

					$node->{text} = "...".$pref." <b style='color:black;'>".$qsearch."</b> ".$post."...";
				}
				else {
					$node->{text} = $self->cut(string => $node->{text}, size => 1000);
				}
			}
			my $vals = {
				%$node,
				name	=> $node->{name},
				index	=> $row->{idx},
				text	=> $node->{text},
				table 	=> $table,
			};

			if($hash_table->{$table}->{route}){
				$vals->{'link'} = $self->url_for($hash_table->{$table}->{route}, %$node);
			}
			elsif(my $linktmlp = $hash_table->{$table}->{linktmlp}){
				while ($linktmlp =~ m/\%([\d\w~]+)\%/ig) {
					my $item = $1;
					my ($type, $val) = split("~", $item);


					if($type =~ /list/){
						$node->{$val} = $self->VALUES( name => $val, value => $node->{$val} ) || '';
					}
					$val = $node->{$val} || "";

					$linktmlp =~ s/\%([\d\w~]+)\%/$val/;
				}
				$vals->{'link'} = $linktmlp;
			}

			push @$result_items, $vals;
		}
	}


	$self->render(
		%params,
		items		=> $result_items,
		template	=> "Search/list"
	);
}


1;
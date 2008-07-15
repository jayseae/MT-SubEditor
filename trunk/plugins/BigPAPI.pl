
# BigPAPI.pl
# BigPAPI plugin for Movable Type
# by Kevin Shay
# http://www.staggernation.com/mtplugins/BigPAPI/
# last modified 8/22/05

use strict;
package MT::Plugin::BigPAPI;

use vars qw( $VERSION );
$VERSION = '1.03';

require MT::Plugin;
require MT;
my $plugin = MT::Plugin->new({
	name => "BigPAPI",
	description => 'Enable other plugins to enhance and modify the MT interface.',
	doc_link => 'http://www.staggernation.com/mtplugins/BigPAPI/',
	author_name => 'Kevin Shay',
	author_link => 'http://www.staggernation.com/',
	version => $VERSION
});
MT->add_plugin($plugin);

require MT::App;
	# store pointer to the original subroutine
my $mt_build_page = \&MT::App::build_page;
	# install our new subroutines
{
	local $SIG{__WARN__} = sub {  }; 
	*MT::App::build_page = \&_build_page;
	*MT::App::load_tmpl = \&_load_tmpl;
}

sub _build_page {
	my ($app, $file, $param) = @_;
	my $tmpl = $file;
	$tmpl =~ s/\.tmpl$//;
	run_callbacks("bigpapi::param::$tmpl", $app, $param);
	run_callbacks("bigpapi::param", $app, $param);
	return &{$mt_build_page}($app, $file, $param);
}

sub _load_tmpl {
# mostly copied from MT::App::load_tmpl()
	my $app = shift;
	my($file, @p) = @_;
	my $cfg = $app->can('config') ? $app->config : $app->{cfg};
	my $path = $cfg->TemplatePath;
	require HTML::Template;
	my $tmpl;
	my $err;
	my @paths;
	if ($app->{plugin_template_path}) {
		if (File::Spec->file_name_is_absolute($app->{plugin_template_path})) {
			push @paths, $app->{plugin_template_path}
				if -d $app->{plugin_template_path};
		} else {
			my $dir = File::Spec->catdir($app->app_dir,
										 $app->{plugin_template_path}); 
			if (-d $dir) {
				push @paths, $dir;
			} else {
				$dir = File::Spec->catdir($app->mt_dir,
										  $app->{plugin_template_path});
				push @paths, $dir if -d $dir;
			}
		}
	}
	if (my $alt_path = $cfg->AltTemplatePath) {
		my $dir = File::Spec->catdir($path, $alt_path);
		if (-d $dir) {			  # AltTemplatePath is relative
			push @paths, File::Spec->catdir($dir, $app->{template_dir})
				if $app->{template_dir};
			push @paths, $dir;
		} elsif (-d $alt_path) {	# AltTemplatePath is absolute
			push @paths, File::Spec->catdir($alt_path,
											$app->{template_dir})
				if $app->{template_dir};
			push @paths, $alt_path;
		}
	}
	push @paths, File::Spec->catdir($path, $app->{template_dir})
		if $app->{template_dir};
	push @paths, $path;
	my $cache_dir;
	if ($app->can('config')) {
		if (!$app->config('NoLocking')) {
			$cache_dir = File::Spec->catdir($path, 'cache');
			undef $cache_dir if (!-d $cache_dir) || (!-w $cache_dir);
		}
	}
	my $type = {'SCALAR' => 'scalarref', 'ARRAY' => 'arrayref'}->{ref $file}
		|| 'filename';
	
	my $orig_type = $type;
	my $template_text;
	if ($type eq 'filename') {
		my $filename = find_file(\@paths, $file);
		eval {
			local($/, *FH) ;
			open(FH, $filename) || die $!;
			$template_text = \<FH>;
		};
		$err = $@;
		return $app->error(
			$app->translate("Loading template '[_1]' failed: [_2]", 
				$filename, $err)) if $@;
		$file =~ s/\.tmpl$//;
	   	run_callbacks("bigpapi::template::${file}::top", $app, $template_text);
	   	$type = 'scalarref';
	} else {
		$template_text = $file;
	}
	$tmpl = HTML::Template->new(
		type => $type, source => $template_text,
		path => \@paths,
		search_path_on_include => 1,
		die_on_bad_params => 0, global_vars => 1,
		loop_context_vars => 1,
        $cache_dir ? (file_cache_dir => $cache_dir, file_cache => 1,
                      file_cache_dir_mode => 0777) : (),
		filepath => '', # to avoid an uninitialized value warning
		filter => sub {
			if ($orig_type eq 'filename') {
				run_callbacks("bigpapi::template::$file", $app, $_[0]);
			}
			run_callbacks("bigpapi::template", $app, $_[0]);
			$_[0];
		}, @p);

	## We do this in load_tmpl because show_error and login don't call
	## build_page; so we need to set these variables here.
	if (my $author = $app->{author}) {
		$tmpl->param(author_id => $author->id);
		$tmpl->param(author_name => $author->name);
	}
	
	my $spath;
	if ($app->can('static_path')) {
		$spath = $app->static_path;
	} else {
		$spath = $app->{cfg}->StaticWebPath || $app->mt_path;
		$spath .= '/' unless $spath =~ m!/$!;
	}
	$tmpl->param(static_uri => $spath);
	my $app_uri = $app->can('uri') ? $app->uri : $app->app_uri;
	$tmpl->param(script_url => $app_uri);
	$tmpl->param(mt_url => $app->mt_uri);
	if ($app->can('path')) {
		$tmpl->param(script_path => $app->path);
	} else {
		$tmpl->param(script_path => $app->app_path);
	}
	$tmpl->param(script_full_url => $app->base . $app_uri);	
	$tmpl->param(mt_version => MT->can('version_id')
		? MT->version_id : MT->VERSION);

	$tmpl->param(language_tag => $app->current_language);
	if ($app->can('charset')) {
		$tmpl->param(language_encoding => $app->charset);
	} else {
		my $enc = $app->{cfg}->PublishCharset ||
				  $app->language_handle->encoding;
		$tmpl->param(language_encoding => $enc);
		$app->{charset} = $enc;
	}

	$tmpl;
}

sub find_file {
	my ($paths, $file) = @_;
	return File::Spec->canonpath($file) if -e $file;
	foreach my $p (@$paths) {
		my $filepath = File::Spec->canonpath(File::Spec->catfile($p, $file));
	return File::Spec->canonpath($filepath) if -e $filepath;
  }
}

sub run_callbacks {
# run a callback and all its version-specific variations
	my ($name, $app, $param) = @_;
	my $ver = MT->version_number();
	my @run = ($name, "${name}::$ver");
	my ($maj, $min) = split(/\./, $ver);
	while ($min =~ m/\d$/) {
		push (@run, "${name}::$maj.${min}x");
		$min =~ s/\d$//;
	}
	push (@run, "${name}::$maj.x");
	my $str = '';
	for my $run (@run) {
		MT->run_callbacks($run, $app, $param);
	}
}

1;

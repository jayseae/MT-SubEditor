# ===========================================================================
# A Movable Type plugin to increase blog administrator capabilities.
# Copyright 2005 Everitz Consulting <everitz.com>.
#
# This program is free software:  You may redistribute it and/or modify it
# it under the terms of the Artistic License version 2 as published by the
# Open Source Initiative.
#
# This program is distributed in the hope that it will be useful but does
# NOT INCLUDE ANY WARRANTY; Without even the implied warranty of FITNESS
# FOR A PARTICULAR PURPOSE.
#
# You should have received a copy of the Artistic License with this program.
# If not, see <http://www.opensource.org/licenses/artistic-license-2.0.php>.
# ===========================================================================
package MT::Plugin::SubEditor;

use base qw(MT::Plugin);
use strict;

use MT;

# version
use vars qw($VERSION);
$VERSION = '0.1.1';

my $about = {
  name => 'MT-SubEditor',
  description => 'Increase blog administrator capabilities.',
  author_name => 'Everitz Consulting',
  author_link => 'http://everitz.com/',
  version => $VERSION,
};
my $subeditor = MT::Plugin::SubEditor->new($about);
MT->add_plugin($subeditor);

# callback methods

MT->add_callback('bigpapi::template::edit_permissions', 9, $subeditor, \&restrict_profile);

sub restrict_profile {
  my ($cb, $app, $template) = @_;
  my $old = qq{<fieldset>};
  $old = quotemeta($old);
  my $new = <<"HTML1";
<TMPL_IF NAME=TOPLEVEL_EDIT_ACCESS>
<fieldset>
HTML1
  my $count = 0;
  $$template =~ s/($old)/if (++$count == 2) { $new } else { $1 }/gex;
  $old = qq{</fieldset>};
  $old = quotemeta($old);
  $new = <<"HTML2";
</fieldset>
</TMPL_IF>
HTML2
  my $count = 0;
  $$template =~ s/($old)/if (++$count == 2) { $new } else { $1 }/gex;
}

# override methods

{
  local $SIG{__WARN__} = sub {  }; 
  *MT::Author::can_administer = \&subeditor_administer;
}

sub subeditor_administer {
  my $app = MT->instance;
  require MT::Permission;
  my @perms = MT::Permission->load({ author_id => $app->user->id });
  return grep {$_->can_administer_blog} @perms;
}

1;
entry [% entryname %]
kernel [% kernel.name %] [% kernel.args %]
bootstrap [% bootstrap.name %] [% bootstrap.args %]
sigma0 [% rootpager.name %]
roottask [% roottask.name %] [% roottask.args %]
module l4re
[% FOREACH m IN extra_modules %]
module[% IF m.defined('opts') %][% "[" %][% m.opts %][% "]" %][% END %] [% m.name %] [% m.is_rw ? ":rw" : "" %]
[%- END %]

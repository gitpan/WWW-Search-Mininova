use 5.008008;
use ExtUtils::MakeMaker;

WriteMakefile(
    NAME              => 'WWW::Search::Mininova',
    VERSION_FROM      => 'lib/WWW/Search/Mininova.pm',
    PREREQ_PM         => {
    	URI => 1.35,
    	'LWP::UserAgent' => 2.036,
    	'HTML::TokeParser::Simple' => 3.15,
    	'HTML::Entities'	=> 1.35,
    }, 
    ($] >= 5.005 ? 
      (ABSTRACT_FROM  => 'lib/WWW/Search/Mininova.pm', 
       AUTHOR         => 'Zoffix Znet <cpan@zoffix.com>') : ()),
);

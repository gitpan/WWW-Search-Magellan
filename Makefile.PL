use ExtUtils::MakeMaker;

WriteMakefile(
              'NAME' => 'WWW::Search::Magellan',
              'VERSION_FROM' => 'Magellan.pm',
              'PREREQ_PM' => {
                              'HTML::Form' => 0,
                              'HTML::TreeBuilder' => 0,
                              'WWW::Search' => 2,
                             },
             );

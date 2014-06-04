#! /usr/bin/perl -sW

# Introduction
#----------------
# In this script, we are going to read the build file (a log of the source
# package building given in parameter), then we will check each possible error
# (not exhaustively) detected by lintian (a tool that checks if the package is
# conform with Debian policy) and fix the package building configuration files
# accordingly.

# Setting up the script
#--------------

# We make the perl interpreter strict to ensure we avoid making silly mistakes.
use strict;

# We configure the `-h` switch to have a little help if using the script
# directly, without calling `build_deb.sh`.
if(our$h) {
    print "correct_lintian source_build_log\n\nDescritpion:\n\tCorrects the debian folder built by dh_make using the .build\n\tfile generated by 'debuild -S' command.\n\nOptions:\n\n";
    exit 0;
}

# A little info to show things are getting started.
print "Starting configuration files edition due to lintian messages.\n";

# We get the first parameter on the command line, which should be the path to
# the build log of the source package built with `debuild -S`
my$buildfilename = shift;

# Opening files
#---------------

# First of all, we must open this build log and get the warnings and errors
# lintian detected. This part of the log will now be found in `$lintianLog`
open BUILDLOG, $buildfilename;
$/ = undef;
my$log = <BUILDLOG>;

$log =~ m/Now running lintian\.\.\.\n(.*)\nFinished running lintian/s;
my$lintianLog = $1;

# Now, we open the files we are going to edit and make a copy of them in memory

# Opening debian/control
open CONTROL, "debian/control" or die($!);
my$control = <CONTROL>;
close CONTROL;
# Opening debian/copyright
open COPYRIGHT, "debian/copyright" or die($!);
my$copyright = <COPYRIGHT>;
close COPYRIGHT;

# We also open a log file, if specified in the environment variable `LOGFILE`.
# In this file, we are going to write down every change that was made, so that
# the user can keep track of what this script has done. A timestamp is written
# at the beginning of the file, along with a little explanation of what this
# file is.
my$do_log = open LOG, ">", "$ENV{LOGFILE}";
if($do_log) {
    my$date = scalar localtime(time);
    print LOG "correct_lintian.pl log file.\nThis log lists edits made by the\
 script and warnings/errors that happened during debian package building. \
You may want to correct them and launch a new build.\n\nTimestamp: $date\n\n";
}

# File edition
#-------------

# Here, we will add the description of each package to the debian/control file.
# Those description will be seen by the end-user (the one using your package)
# when installing it with a graphical package manager, or using the command
# `dpkg -I` on your package.
my$binpackdesc = $ENV{BINPACKAGEDESCFILE};
my$libpackdesc = $ENV{LIBPACKAGEDESCFILE};
if ( open DESC, $binpackdesc ) {
    my$desc = <DESC>;
    $desc =~ s/\n/\n /gs;
    my$name = $ENV{BINPACKAGENAME};
    $control =~ s/(Package: $name[\s]+Architecture: .*?[\s]+Depends:.*?[\s]\
+Description:) <.*?>[\s]+ <.*?>/$1 $desc\n/s;
    close DESC;
}
if ( open DESC, $libpackdesc ) {
    my$desc = <DESC>;
    my$name = $ENV{LIBPACKAGENAME};
    my@descriptions = split /\n\n/, $desc;
    $descriptions[0] =~ s/\n/\n /gs;
    $descriptions[1] =~ s/\n/\n /gs;
    $control =~ s/(Package: $name[\s]+Section: libs[\s]+Architecture:.*?[\s]+\
Depends:.*?[\s]+Description:) <.*?>[\s]+ <.*?>/$1 $descriptions[0]\n/s;
    $control =~ s/(Package: $name-dev[\s]+Section:.*?[\s]+Architecture:.*?[\s]+\
Depends:.*?[\s]+Description:) <.*?>[\s]+ <.*?>/$1 $descriptions[1]\n/s;
    close DESC;
}
$control =~ s/\n{2,}/\n\n/sg;

# Here, we will edit copyright informations, like developers' names and
# contacts, or the project's homepage.
my$url = $ENV{HOMEPAGE};
my$devs = $ENV{DEVS};
$devs =~ s/>\s+?([^L])/>\n           $1/gs;
$devs = $devs."\n";
$copyright =~ s#(Source:) <url://example.com>#$1 $url#;
$copyright =~ s/(Copyright:) <.+?> <.+?>\n\s+? <.+?> <.+?>\n/$1 $devs/;

# Lintian corrections
#----------------------
# In this part, we are going to read _lintian_'s output and correct the
# mistake we can correct.

# Getting the version of _debhelper_ right
if ($lintianLog =~ /package-needs-versioned-debhelper-build-depends (.*?)[\s]/){
    my$dh_version = $1;
    $control =~ s/debhelper (\(.*?\))/debhelper \(>= $dh_version\)/;
    print LOG "build depends debhelper version changed from $1 to \
(>= $dh_version)\n" if $do_log;
}
# Getting _standards_ version right
if ($lintianLog =~ /out-of-date-standards-version \d\.\d\.\d \(current is (\d\.\d\.\d)\)/){
    my$std_version = $1;
    $control =~ s/Standards-Version: (\d\.\d\.\d)/Standards-Version: \
$std_version/;
    print LOG "standards version changed from $1 to $std_version\n" if $do_log;
}
if ($lintianLog =~ /ancient-standards-version \d\.\d\.\d \(current is (\d\.\d\.\d)\)/){
    my$std_version = $1;
    $control =~ s/Standards-Version: (\d\.\d\.\d)/Standards-Version: \
$std_version/;
    print LOG "standards version changed from $1 to $std_version\n" if $do_log;
}
# Adding missing generated dependencies
if ( $lintianLog =~ /debhelper-but-no-misc-depends/ ) {
    $control =~ s/(Package: (.*?-dev)[\s]+Section:.*?[\s]+Architecture:.*?[\s]+Depends:.*?)([\s]+Desc)/$1, \${misc:Depends}$3/s;
    print LOG "added missing dependencies for $2 package\n" if $do_log;
}
# Adding the project's homepage if given in the environment variable `HOMEPAGE`
if ( $lintianLog =~ /bad-homepage/ ) {
    if ( $ENV{HOMEPAGE} ne "" ) {
	$control =~ s/(Homepage: )<.*?>/$1$ENV{HOMEPAGE}/g;
	print LOG "updated homepage to $ENV{HOMEPAGE}\n" if $do_log;
    }
    else {
	print LOG "missing homepage in configuration file\n" if $do_log;
    }
}
# Throw a warning if some binaries do not have a man page
if ( $lintianLog =~ /binary-without-manpage/ ) {
    print LOG "WARNING: Each binary in /usr/bin, /usr/sbin, /bin, /sbin or\n
\t/usr/games should have a manual page.If the man pages are provided by\n
\tanother package on which this package depends, we may not be able to\n
\tdetermine that man pages are available. In this case, ignore this warning\n" if $do_log;
}


# Saving our edits
#-----------------
# Now, we are going to save our changes in the files we previously read.

# Writing in debian/control
open CONTROL, ">", "debian/control" or die($!);
print CONTROL $control;
# Writing in debian/copyright
open COPYRIGHT, ">", "debian/copyright" or die($!);
print COPYRIGHT $copyright;

# Closing files
#--------------
# Now we close all the files that were previously opened and not closed.
close CONTROL;
close COPYRIGHT;
close BUILDLOG;
close LOG if $do_log;

# And a little message to let the user know that the script is done and where
# to find the log if there is one.
print "Configuration files edited !\n";
print "You can find what has been changed in $ENV{LOGFILE}\n" if $do_log;

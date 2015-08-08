
package xAP::Util;

use POSIX;
use Time::HiRes qw/gettimeofday/;

#use Time::localtime;
use Time::Local;

use constant DBG_FATAL => 0;
use constant DBG_ERROR => 1;
use constant DBG_WARNING => 2;
use constant DBG_INFO => 3;
use constant DBG_DEBUG => 4;

our $log_level = DBG_INFO;
our %log_codes = (
         0 => "FATAL",
         1 => "ERROR",
         2 => "WARN",
         3 => "INFO",
         4 => "DEBUG"
);

sub _log {
   my ($level, $msg) = @_;
   if ($level <= $log_level) {
      $msg =~ s/[\r\n]+$//g;
      
      my $code = $log_codes{$level};
      my ($seconds, $microseconds) = gettimeofday();
      my $time = strftime( "%x %H:%M:%S", localtime( $seconds ) );
      my $message = sprintf( "%s [%s] %s", $time,  $code, $msg);
      $message .= "\n";
      print $message;      

   }   
}

sub debug {
   _log( DBG_DEBUG, @_);
}

sub info {
   _log( DBG_INFO, @_);
}

sub warn {
   _log( DBG_WARNING, @_);
}

sub error {
   _log( DBG_ERROR, @_);
}

sub fatal {
   _log( DBG_FATAL, @_);
}

sub getDateTimeString {
   my $tm = localtime(time);
   my $seconds = $tm->sec;
   my $minutes = $tm->min;
   my $hours = $tm->hour;
   my $dayofmonth = $tm->mday;
   my $month = $tm->mon + 1;
   my $year = 1900 + $tm->year;
   return sprintf("%04d%02d%02d%02d%02d%02d", $year, $month, $dayofmonth, $hours, $minutes, $seconds);
}

sub getDurationString {
   my ($duration) = @_;
   my $diffepoch = $duration;
   my $diffhrs = $diffepoch / 3600;
   my $diffmins = ($diffepoch % 3600) / 60;
   my $diffsecs = ($diffepoch % 3600) % 60;
   return sprintf("%02d:%02d:%02d",$diffhrs, $diffmins, $diffsecs);
}

sub getRingCount{
   my ($duration) = @_;
   my $rings = $duration / 5; # assume 5 secs per ring.
   my ($ringcount, $ringremainder) = split(/\./, $rings);
   return $ringcount + 1;
}

sub getDuration {
   my ($startdttm, $enddttm) = @_;
   my ($startyr, $startmon, $startday, $starthrs, $startmins, $startsecs) = $startdttm =~ /^(\d\d\d\d)(\d\d)(\d\d)(\d\d)(\d\d)(\d\d)/;
   my ($endyr, $endmon, $endday, $endhrs, $endmins, $endsecs) = $enddttm =~ /^(\d\d\d\d)(\d\d)(\d\d)(\d\d)(\d\d)(\d\d)/;
   my $startepoch = timelocal($startsecs, $startmins, $starthrs, $startday, $startmon-1, $startyr-1900);
   my $endepoch = timelocal($endsecs, $endmins, $endhrs, $endday, $endmon-1, $endyr-1900);
   my $diffepoch = $endepoch - $startepoch;
   return $diffepoch;
}

1


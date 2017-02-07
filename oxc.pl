#!/usr/bin/perl -w

use strict;

#use lib './lib', './lib/site';

#use bytes;
use POSIX; # qw(:sys_wait_h);
use Socket;
use Getopt::Long;
use Time::HiRes qw(gettimeofday);
#use constant 1.01;

my ($config_path, $lib_path, $app_path);
our $bsc;
our $log_level;
our %conf;
our $monitor_hash;
our $xap_hbeat_interval;
our ($sensor_read_interval, $sensor_report_interval);
our $enable_xap_control;
our %devices;
our $temp_scale;
our $ow_method;
our $startscan = 1;
our $version = 0.7;
our @OWFS_hubs = ("/");
our $solar_mw2 = 0.0079; #683 Lux = 1 Wm2 as well http://bccp.berkeley.edu/o/Academy/workshop08/08%20PDFs/Inv_Square_Law.pdf

BEGIN {
   GetOptions("config:s"=>\$config_path,
           "lib:s"=>\$lib_path,
           "path:s"=>\$app_path
          );
   if ($app_path) {
      $config_path = "$app_path/oxc.conf" unless $config_path;
      $lib_path = "$app_path/lib" unless $lib_path;
   } else {
      $config_path = "./oxc.conf" unless $config_path;
      $lib_path = "./lib" unless $lib_path;
   }
   unshift @INC, $lib_path;
   unshift @INC, "$lib_path/site";

   require xAP::Comm;
   require xAP::BSC_Item;
   require Config::IniFiles;
   require xAP::Util;
}

$| = 1;

$ENV{PATH}  = '/bin:/usr/bin';
$ENV{SHELL} = '/bin/sh' if exists $ENV{SHELL};
delete @ENV{qw(IFS CDPATH ENV BASH_ENV)};


&init();


# send xAP monitor data

my $sensor_last_read_time = gettimeofday;
my $xap_heartbeat_last_sent_time = gettimeofday;

my $xap_timeout = .1; #0.05;
my $xap_loop_duration = .5;
our $reload = undef;
my $pid = undef;

# initialize by reading all sensors
&readAllSensors();

# main "work" loop
while( 1 )
{
	if (1==1)
	{
		# listen for xAP data; maintain loop as lots of xAP traffic may exist
        	my $elapsed_listen = 0;
		my $starttime = gettimeofday();
        	while (($elapsed_listen <= $xap_loop_duration) && !(defined($reload))) {
        		&xAP::Comm::check_for_data($xap_timeout);
        		$elapsed_listen = gettimeofday() - $starttime;
        	}

#		if ((gettimeofday - $sensor_last_read_time >  $sensor_read_interval) ) 
#        	{
	 		&readSensors();
#			$sensor_last_read_time = gettimeofday;
#        	}
	}

	# send xAP heartbeats if time to do so
	if (gettimeofday - $xap_heartbeat_last_sent_time >= $xap_hbeat_interval)
	{
         	&xAP::Comm::send_xap_heartbeat('alive');
		$xap_heartbeat_last_sent_time = gettimeofday;
	}


}

&xAP::Util::info( "xAP server exiting" );

close( LOG );
exit();


sub init
{
	tie %conf, 'Config::IniFiles', (-file => "$config_path");

	$ow_method = 'digitemp'; # default method is digitemp
	$ow_method = 'owfs' if ($conf{general}{method} =~ /owfs/i);
	my $root = $conf{owfs}{mount_point};
	die "OWFS: $root does not exist! Please recheck your mount path" if ((!(-e $root)) and ($ow_method eq 'owfs'));

	# setup logging
	my $log_file = $conf{general}{log_file};
	$log_file = '/tmp/oxc.log' unless $log_file;
	$log_level = $conf{general}{log_level}; # 0-NONE, 1-ERR, 2-WARN, 3-INFO, 4-DBG
	$log_level = 3 unless $log_level;
        $xAP::Util::log_level = $log_level;

	open( LOG, ">>$log_file" ) or die( "Can't open log file: $!" );
	open( STDOUT, ">&LOG" ) || die( "Can't dup stdout: $!" );
	select( STDOUT ); $| = 1;
	open( STDERR, ">&LOG" ) || die( "Can't dup stderr: $!" );
	select( STDERR ); $| = 1;
	select( LOG ); $| = 1;

	&xAP::Util::info( "xAP oxc server v$version starting" );
	&OWFS_findhubs if (($conf{owfs}{hubs}) and ($ow_method = 'owfs'));

        # read all of the sensor data from the ini file
        for my $key (keys %conf) {
           my ($sensorname) = $key =~ /^sensor.(\S+)/;
           next unless $sensorname;
           my $serial = $conf{$key}{serial};
           $serial =~ s/\s+$//; # remove trailing spaces
           if ($serial) {
 		&xAP::Util::info("Reading configuration of serial: $serial for $sensorname");
	  	my $device = new OW_Device($serial);
	   	$device->name($sensorname);
		&xAP::Util::debug("DB: Sensor is: $sensorname,$serial,$root,$ow_method");
		my $sensor_path;
		$sensor_path = $device->set_path($serial,$root) if ($ow_method eq 'owfs');
		if (!$sensor_path) {
			&xAP::Util::warn("OWFS Cannot find path to sensor $sensorname ($serial). Removing from sensor list");
			next;
		}
           	$devices{$serial} = $device;
                my $delta_report_primary = 1;
		if ($conf{$key}{delta_report_humid}) {
			$device->delta_report('primary', $conf{$key}{delta_report_humid});
			if ($conf{$key}{data_report_temp}) {
				$device->delta_report('secondary', $conf{$key}{delta_report_temp});
			}
		} elsif ($conf{$key}{delta_report_temp}) {
			$device->delta_report('primary', $conf{$key}{delta_report_temp});
		} elsif ($conf{$key}{delta_report}) {
			$device->delta_report('primary', $conf{$key}{delta_report});
		} elsif ($conf{$key}{delta_report2}) {
			$device->delta_report('secondary', $conf{$key}{delta_report2});
		}
                my $read_timeout = $conf{$key}{read_timeout};
                $read_timeout = $conf{digitemp}{read_timeout} unless $read_timeout;
                if ($read_timeout) {
                    $read_timeout = 1000 * $read_timeout; # convert to milliseconds
                } else {
                    $read_timeout = 1000;
                }
                $device->read_timeout($read_timeout);

           } else {
		&xAP::Util::warn( "No address specified for $key");
	   }
	}
	$sensor_read_interval = $conf{general}{sensor_read_interval};
	$sensor_read_interval = 15.0 unless $sensor_read_interval;
	$sensor_read_interval = 10 if $sensor_read_interval < 10;

	$sensor_report_interval = $conf{general}{sensor_report_interval};
	$sensor_report_interval = 300.0 unless $sensor_report_interval;
	$sensor_report_interval = 2 * $sensor_read_interval 
		if $sensor_report_interval < 2 * $sensor_read_interval;

	# init xAP
	my $xap_vendor_name = 'liming';
	my $xap_device_name = 'oxc';
	my $xap_instance_name = $conf{xap}{instance_name};
	$xap_instance_name = 'instance1' unless $xap_instance_name;
	my $xap_base_uid = $conf{xap}{base_uid};
	if ($xap_base_uid)
	{
		$xap_base_uid = "FF$xap_base_uid";
	}
	else
	{
		$xap_base_uid = 'FFEA03';
	}
	$xap_hbeat_interval = $conf{xap}{hbeat_interval};
	$xap_hbeat_interval = 60 unless $xap_hbeat_interval && $xap_hbeat_interval >= 60;
	my $xap_nohub = $conf{xap}{nohub};
	$xap_nohub = 0 unless $xap_nohub;
        &xAP::Util::debug("Initializing xAP communications");

	&xAP::Comm::initialize($xap_vendor_name, $xap_device_name, $xap_instance_name, 
                    $xap_base_uid, $xap_hbeat_interval/60, $xap_nohub, $log_level);
	$bsc = new xAP::BSC_Item($xap_instance_name, &xAP::Comm::get_xap_source_info($xap_instance_name) . ":>", '*');
	$bsc->is_local(1);
	$bsc->setcallback('cmd',\&cmdCallback);

	$temp_scale = 'F'; # default to Farenheit
	$temp_scale = 'C' if ($conf{general}{temp_scale} =~ /c/i);

	if ($conf{owfs}{hubs}) {
	  my $hubnames = join ", ",@OWFS_hubs;
          &xAP::Util::info("OWFS Search hubs are: $hubnames");
	}
	my $solar_type = "lux";
	$solar_type = $conf{general}{solar} if (defined $conf{general}{solar});
        &xAP::Util::info("Initialization complete. Method is $ow_method, Scale is $temp_scale, solar is $solar_type");

}


sub AUTOLOAD
{
	our $AUTOLOAD;
	return undef; 
}

sub readAllSensors {

	if ($ow_method eq 'owfs' ) {
	   &readOWFS();
	} else {
	   &readDigitemp();
	}
	$startscan = 0;
}


sub readSensors {

	for my $serialnum (sort(keys(%devices))) {
		my $device = $devices{$serialnum};
		if (!($device->next_read) || (gettimeofday() > $device->next_read)) {
		   	if ($ow_method eq 'owfs' ) {
	   		   &readOWFS($serialnum);
		   	} else {
	   		   &readDigitemp($device->aux_id);
	           	}
			$device->next_read(gettimeofday() + $sensor_read_interval);
			last;
		}
	}
	

}

sub readDigitemp {
	
	my ($sensorid) = @_;
	my $program = $conf{digitemp}{program_path};
        if (!(-e $program)) {
		&xAP::Util::error("Digitemp program: $program does not exist! Please recheck your config path");
		return;
	}
        my $digitempconf = $conf{digitemp}{config_path};
        if (!(-e $digitempconf)) {
		&xAP::Util::error("Digitemp config file: $digitempconf does not exist! Please recheck your config path");
		return;
	}
 	my ($device,$data);
        my $read_timeout = 1000; # 1sec
        my $options = "-c $digitempconf -q"; 
        if (defined($sensorid)) {
		$device = &get_device_by_id($sensorid);
                my $name = $sensorid;
                if ($device) {
                   $read_timeout = $device->read_timeout;
                   $name = $device->name;
                }
		$options .= " -r $read_timeout -t $sensorid";
		&xAP::Util::debug("Digitemp reading data for sensor: $name; timeout: $read_timeout");
	} else {
		$options .= " -a -r $read_timeout";
		&xAP::Util::debug("Digitemp reading data for all sensors");
	}
	# build up format strings
        my $extra_options = $conf{digitemp}{extra_options};
        $extra_options = " $extra_options" if $extra_options; # prepend a space
	my $temp_fmt = "%s %R"; # output sensor and serial #s
	my $humid_fmt = $temp_fmt . " H%h";
	$temp_fmt .= " T%.1$temp_scale";
	$humid_fmt .= " T%.1$temp_scale";

	$options .= " -o \"$temp_fmt\" -H \"$humid_fmt\"";
	$options .= $extra_options if $extra_options;

	my ($readme, $writeme);
	my $success = 0;
	pipe $readme, $writeme;
	if ($pid = fork) {
		# parent
		$SIG{CHLD} = sub { 1 while (waitpid(-1, WNOHANG)) > 0 };
		close $writeme;
	} else {
		die "cannot fork: $!" unless defined $pid;
		# child
		open(STDOUT, ">&=", $writeme) or die "Couldn't redirect STDOUT: $!";
		close $readme;
		exec("$program $options") or die "Coudn't run $program : $!\n";
	}
	while (<$readme>) {
		my $line = $_;
		$line =~ s/\r\n//g;
		my ($sensorident,$serialnum,$value1,$value2) = $line =~ /^(\d+)\s+(\S+)\s+(\S+)\s*(\S*)/;
		my $type1 = 'unknown';
		my $type2 = 'unknown';
                if (defined($sensorident) and $serialnum and $value1) {
			my ($value1_scale, $value1_val) = $value1 =~ /^(\D)(\S+)/;
			if ($value1_scale eq 'T') {
				$type1 = 'temp';
			} elsif ($value1_scale eq 'H') {
				$type1 = 'humid';
			} elsif ($value1_scale eq 'C') {
				$type1 = 'counter';
			} elsif ($value1_scale eq 'A') {
				$type1 = 'analog';
			}
			$data->{val1} = $value1_val;
			if ($value2) {		
				my ($value2_scale, $value2_val) = $value2 =~ /^(\D)(\S+)/;
				if ($value2_scale eq 'T') {
					$type2 = 'temp';
				} elsif ($value2_scale eq 'H') {
					$type2 = 'humid';
				} elsif ($value2_scale eq 'C') {
					$type2 = 'counter';
				}
				$data->{val2} = $value2_val;
			}
                	$device = $devices{$serialnum};
                	if ($device) {
			    $data->{state} = 'on';
			    $device->{type} = $type1;
			    $device->{type2} = $type2;
                	    $device->aux_id($sensorident);
                            $device->update($data);
	        	}
			$success = 1; 
                }
	}
	close ($readme);
        if (!($success)) {
		if (defined $sensorid) {
       			$device = &get_device_by_id($sensorid);
			&xAP::Util::warn("Digitemp: no data available for sensor: " . $device->name);
		} else {
       			&xAP::Util::warn("Digitemp: no data available");
		}
		if ($device) {
		       $data->{state} = 'off';
		       $device->update($data);
		}
	}

}

sub readOWFS {
	
	my ($sensorid) = @_;
	my @read_sensors;
	my ($type1,$type2);
	my ($value1,$value2);
	my $precision = $conf{owfs}{precision};

 	my ($device,$data);
        if (defined($sensorid)) {
		$device = &get_device_by_id($sensorid);
                my $name = $sensorid;
		my $id=$sensorid;
                if ($device) {
                   $name = $device->name;
		   $id = $device->{Id};
                }
		push (@read_sensors,$id);
		&xAP::Util::debug("OWFS reading data for sensor: $name; id=$id;");
	} else {
	      #add all sensors
	      for my $serialnum (sort(keys(%devices))) {
		push (@read_sensors,$serialnum);
		}
		&xAP::Util::debug("OWFS reading data for all sensors");
	}
	for my $sensor (@read_sensors) {
          $device = $devices{$sensor};
           if ($device) {

	   my $owfs_file = $device->get_path;
	   &xAP::Util::debug("Checking file $owfs_file...");

	   $type1 = "unknown";
	   $type2 = "unknown";
	   $value1 = ();
	   $value2 = ();
	   my $key = "sensor." . $device->name;
	   if (( -e "$owfs_file/S3-R1-A/illuminance" ) and ((defined $conf{$key}{type}) and (lc $conf{$key}{type} eq "solar"))) {
           &xAP::Util::debug("Checking file $owfs_file solar...");
	      open (DATA, "$owfs_file/S3-R1-A/illuminance");
           &xAP::Util::debug("Checking file $owfs_file solar...");
	      $value1 = <DATA>;
	      close (DATA);
	      if ($value1) {
	         $value1 =~ s/^\s+//; #remove white space
	         #$value1 = sprintf("%.${precision}f",$value1) if $precision; #add decimal precision
	         $type1 = "solar";
	         $value1 = $value1 * $solar_mw2 if ($conf{general}{solar} =~ /mw2/i);
	         $value1 = sprintf("%.${precision}f",$value1) if $precision; #add decimal precision
	         $data->{val1} = $value1;
              }
	   } elsif ( -e "$owfs_file/temperature" ) {
           &xAP::Util::debug("Checking file $owfs_file temp...");
	      open (DATA, "$owfs_file/temperature");
           &xAP::Util::debug("Checking file $owfs_file temp...");
	      $value1 = <DATA>;
	      close (DATA);
	      if ($value1) {
	         $value1 =~ s/^\s+//; #remove white space
	         $value1 = sprintf("%.${precision}f",$value1) if $precision; #add decimal precision
	         $type1 = "temp";
	         $data->{val1} = $value1;
              }
	   }
	   if (( -e "$owfs_file/humidity" ) and ($type1 ne "solar")) {
           &xAP::Util::debug("Checking file $owfs_file humid...");
	      open (DATA, "$owfs_file/humidity");
           &xAP::Util::debug("Checking file $owfs_file humid...");
	      my $value = <DATA>;
	      close (DATA);
	      if ($value) {
	         $value =~ s/^\s+//; #remove white space
	         $value = sprintf("%.${precision}f",$value) if $precision; #add decimal precision
		 if ($value1) {
	            $value2 = $value if $value;
	            $type2 = "humid" if $value;
	            $data->{val2} = $value2;
	         } else {
	            $value1 = $value if $value;
	            $type1 = "humid" if $value;
	            $data->{val1} = $value1;
	         }
	      }
            }
	   $value1 = "unknown" if !$value1;
           &xAP::Util::info("Sensor unknown for file $owfs_file.") if ($type1 eq "unknown");
	   my $msg1 = "Initial Scan: $owfs_file is a $type1" if ($startscan);
	   $msg1 .= " ($type2)" if (($type2 ne "unknown") and $startscan);
	   $msg1 .= " sensor with a value of $value1" if $startscan;
	   $msg1 .= " ($value2)" if ($value2 and $startscan);
	   &xAP::Util::info($msg1) if $startscan;
	   my $msg2 = "$owfs_file is a $type1";
	   $msg2 .= "/$type2" if ($value2);
           $msg2 .= " sensor with a value of $value1";
	   $msg2 .= "/$value2" if ($value2);
	   &xAP::Util::debug($msg2);
	   $value2 = "unknown" if !$value2;
 
	      if ($type1 ne "unknown") {
		    $data->{state} = 'on';
		    $device->{type} = $type1;
		    $device->{type2} = $type2;
                   # $device->aux_id($sensor); #doesn't matter, as this is a digitemp artifact
		    my $subaddress = &xAP::Comm::get_xap_subaddress_uid('oxc',$device->{Id});
		    $device->aux_id(hex($subaddress));
                    $device->update($data);
              } else {
      		    $data->{state} = 'off';
		    $device->update($data);
	      }

	   } else {
		if (defined $sensorid) {
 		   $device = &get_device_by_id($sensorid);
		   &xAP::Util::info("owfs: no data available for sensor: " . $device->name);
		} else {
       		   &xAP::Util::info("owfs: no data available");
	        }
	   }
      } 
  }

sub get_device_by_id {
	my ($id) = @_;
	if (defined($id)) {
		for my $serialnum (keys %devices) {
			my $device = $devices{$serialnum};
	                return $device if defined($device->aux_id) && $device->aux_id eq $id;
		}
	}
}

sub OWFS_findhubs {
        my $hubs = $conf{owfs}{hubs};

	my $root = $conf{owfs}{mount_point};
	$root =~ s/\/$//;
	for my $hub (split /,/,$hubs) {
		$hub =~ s/^\///;
		$hub =~ s/\/$//;
		$hub = "/" . $hub . "/";
		if (-e $root . $hub) {
		&xAP::Util::info("OWFS: Hub $root$hub added to search path.");
		  push (@OWFS_hubs,$hub);
		} else {
		&xAP::Util::error("OWFS: Hub $root$hub does not exist! Please recheck your hubs");
		}
	}
}

package OW_Device;

use Time::HiRes qw(gettimeofday);
use xAP::Util;

sub new {
	my ($class, $id) = @_;
	my $self = {};
	bless $self, $class;

	if (defined $id) {
		$self->{Id} = $id;
	}
	return $self;
}

sub name {
	my ($self, $name) = @_;
	$self->{Name} = $name if $name;
	if ($self->{Name}) {
		return $self->{Name};
	} else {
		return $self->{Id};
	};
}

sub set_path {
	my ($self, $sensor, $root) = @_;
        if (!(-e $root)) {
		&xAP::Util::error("OWFS: $root does not exist! Please recheck your mount path");
		return;
	}
	# Here's where hub searches could go.
	# build @subroots "/" + other hubs...
	# read the file for temp information. owfs format is slightly different than serial #s
	# ie 103A8CE400080002 = 10.3A8CE400080000

	&xAP::Util::debug("Testing OWFS for $sensor");
	my $sensor_owfs_name = substr($sensor,0,2) . "." . substr($sensor,2,10) . "00";

	foreach my $hub (@OWFS_hubs) {
	  my $hub_filename = $root . $hub;
	  &xAP::Util::debug("Testing OWFS: Looking in hub: $hub_filename");
	  my @file_list = glob($hub_filename . "*");

	  foreach my $filename (@file_list) {
	    if ($filename =~ /$sensor_owfs_name/) {
	      $self->{Path} = $hub_filename . $sensor_owfs_name;
	      last;
	    }
	  }

	  if ($self->{Path}) {
		&xAP::Util::debug("OWFS Path for $sensor is $self->{Path}");
		return $self->{Path};
	  }
        }
	&xAP::Util::debug("Cannot find OWFS Path for $sensor!");
	return;
}

sub get_path {
        my ($self, $sensor) = @_;
        return $self->{Path}
}



sub aux_id {
        my ($self, $aux_id) = @_;
        $self->{AuxId} = $aux_id if defined $aux_id;
        return $self->{AuxId}
}

sub next_read {
	my ($self, $next_read) = @_;
	$self->{NextRead} = $next_read if $next_read;
	return $self->{NextRead};
}


sub next_send {
	my ($self, $next_send) = @_;
	$self->{NextSend} = $next_send if $next_send;
	return $self->{NextSend};
}

sub read_timeout {
        my ($self, $read_timeout) = @_;
        $self->{ReadTimeout} = $read_timeout if $read_timeout;
        return $self->{ReadTimeout};
}

sub delta_report {
	my ($self, $type, $amount) = @_;
        if ($type) {
		$$self{"report_$type"} = $amount if $amount;
                my $ret = $$self{"report_$type"};
		# default to primary if secondary is undefined
		if ($type eq 'secondary' and !($ret)) {
			$ret = $$self{"report_primary"};
		}
                $ret = 1 unless $ret;
		return $ret;
        } 
}

sub update {
	my ($self, $data) = @_;
	my $delta_primary = 0;
	my $delta_secondary = 0;
	if ($data->{state} eq 'on') {
		if ($data->{val1}) {
			$delta_primary = $data->{val1} - $self->{val1} if $self->{val1};
			$self->{val1} = $data->{val1};
		}
		if ($data->{val2}) {
			$delta_secondary = $data->{val2} - $self->{val2} if $self->{val2};
		}
		my $dbg_msg = "Value update in " . $self->name . ":";
		$dbg_msg .= " val1=" . $data->{val1} . "," if $data->{val1};
		$dbg_msg .= " val2=" . $data->{val2} if $data->{val2};
		&xAP::Util::debug($dbg_msg);
	}

&xAP::Util::debug("update0");
	if (!($self->next_send) || (gettimeofday() > $self->next_send) 
		|| ($delta_primary > $self->delta_report('primary') 
                or $delta_secondary > $self->delta_report('secondary')))  {
&xAP::Util::debug("update1");
		my %bsc_data;
		$bsc_data{mode} = 'input';
		$bsc_data{state} = $data->{state};
		my $subaddress = $self->name;
		if ($data->{state} eq 'on') {
			if ($data->{val1}) {
&xAP::Util::debug("update2");
				my $subuid = sprintf("%X",$self->aux_id + 1); # add 1 to the Id since Id can be 0
	        	        $subuid = "0$subuid" if (length($subuid) == 1);
				$bsc_data{id} = $subuid;
				if ($self->{type} eq 'humid') {
					$bsc_data{level} = $data->{val1} . "/100";
					delete $bsc_data{text} if exists($bsc_data{text});
				} elsif ($self->{type} eq 'temp') {
					$bsc_data{text} = $data->{val1} . "$temp_scale";
					delete $bsc_data{level} if exists($bsc_data{level});
				} elsif ($self->{type} eq 'solar') {
		                        $bsc_data{level} = $data->{val1};
                                        delete $bsc_data{text} if exists($bsc_data{text});
				}
&xAP::Util::debug("update3");
				if ($delta_primary > $self->delta_report('primary')) {
					$bsc->send_event($self->{type} . ".$subaddress",%bsc_data);
				} else {	
					$bsc->send_info($self->{type} . ".$subaddress",%bsc_data);
				}
			} 
			if ($data->{val2}) {
&xAP::Util::debug("update4");
				my $subuid = sprintf("%X",$self->aux_id + 128);
        		        $subuid = "0$subuid" if (length($subuid) == 1);
				$bsc_data{id} = $subuid;
				if ($self->{type2} eq 'humid') {
					$bsc_data{level} = $data->{val2} . "/100";
					delete $bsc_data{text} if exists($bsc_data{text});
				} elsif ($self->{type2} eq 'temp') {
					$bsc_data{text} = $data->{val2} . "$temp_scale";
					delete $bsc_data{level} if exists($bsc_data{level});
				} 
				if ($delta_secondary > $self->delta_report('secondary')) {
					$bsc->send_event($self->{type2} . ".$subaddress",%bsc_data);
				} else {	
					$bsc->send_info($self->{type2} . ".$subaddress",%bsc_data);
				}
			}
			$self->next_send(gettimeofday() + $sensor_report_interval); 
		} else {
&xAP::Util::debug("update5");
			my $subuid = sprintf("%X",$self->aux_id + 1); # add 1 to the Id since Id can be 0
       		        $subuid = "0$subuid" if (length($subuid) == 1);
			$bsc_data{id} = $subuid;
			$bsc->send_info($self->{type} . ".$subaddress",%bsc_data);
			$self->next_send(gettimeofday() + $sensor_report_interval); 
			if ($self->{type2} and $self->{type2} ne 'unknown') {
&xAP::Util::debug("update6");
				$subuid = sprintf("%X",$self->aux_id + 128); # add 1 to the Id since Id can be 0
       			        $subuid = "0$subuid" if (length($subuid) == 1);
				$bsc_data{id} = $subuid;
				$bsc->send_info($self->{type2} . ".$subaddress",%bsc_data);
			}
&xAP::Util::debug("update7");
		}
&xAP::Util::debug("update8");
	} 
&xAP::Util::debug("update9");
}

1;

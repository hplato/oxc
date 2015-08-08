package xAP::Comm;

=begin comment
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

File:
	Comm.pm

Description:
	xAP support for sending xAP messages (generic and heartbeats)
	
Author:
	Gregg Liming
	gregg@limings.net

License:
	This free software is licensed under the terms of the BSD license.

Usage:

	To be completed.

Special Thanks to: 
	Bruce Winter - Misterhouse (misterhouse.sf.net)
		

@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
=cut

use IO::Socket::INET;

use strict;

my ($xap_send, %xap_uids, $default_base_uid, $xap_real_device_name, %xap_virtual_devices, $xap_hbeat_interval, @registered_xap_items, $xap_vendor_info, $xap_device_info, $log_level);

sub register_xap_item {
   my ($xap_item) = @_;
   push @registered_xap_items, $xap_item;
}

sub initialize {
    my ($p_xap_vendor_info, $p_xap_device_info, $xap_instance_name, $base_uid, $hbeat_interval, $nohub, $l_level) = @_;

    $log_level = $l_level if defined $l_level;
    $log_level = 1 if !$log_level;

    $xap_vendor_info = $p_xap_vendor_info;
    $xap_device_info = $p_xap_device_info;

    # init the hbeat intervals and counters
    $xap_hbeat_interval = $hbeat_interval if $hbeat_interval;
    $xap_hbeat_interval = 1 unless $xap_hbeat_interval;

    $default_base_uid = $base_uid;

    my $port = 3639;

    # open the sending port
    $xap_send = &open_port($port, 'send', 0);
    if ($xap_send) {
       print "INFO (xAP::Comm): Created xAP send socket on port $port\n" if $log_level > 2;
    } else {
       print "ERR (xAP::Comm): Unable to create xAP send socket on port $port\n";
    }
    $xap_real_device_name = $xap_instance_name;
    &init_xap_virtual_device($xap_real_device_name, $nohub);

}

sub init_xap_virtual_device {
   my ($virtual_device_name, $nohub) = @_;

   if (!(exists($xap_virtual_devices{$virtual_device_name}))) {
      # grab a base UID so that it is reserved
      my $virtual_base_uid = &get_xap_base_uid($virtual_device_name);

      # Find and use the first open port
      my $port;
      my $xap_socket;

      # if no hub exists, then bind directly to the xap port if possible
      if ($nohub) {
         $port = 3639;
         $xap_socket = &open_port($port, 'listen', 0);
         if ($xap_socket) {
            print "INFO (xAP::Comm): Created direct xAP listen socket (no other xAP app may listen on this system!) on " .
               "port $port\n" if $log_level > 2;
         } else {
            print "WARN (xAP::Comm): Unable to create direct xAP listen socket on port $port! Reverting to hub mode\n" if $log_level > 1;
         }
      }

      # if nohub was 0 or the primary xAP port wasn't available, then attempt an ephemeral port
      if (!($xap_socket)) {
         for my $p (49152 .. 65535) {
            $port = $p;
            $xap_socket = &open_port($port, 'listen', 1);
            last if $xap_socket;
         }
         if ($xap_socket) {
            print "INFO (xAP::Comm): Created xAP listen socket on port $port\n" if $log_level > 2;
         } else {
            print "WARN (xAP::Comm): Unable to create any xAP listen socket; this application cannot listen to xAP messages\n" if $log_level > 1;
         }
      }
      if ($xap_socket) {
         $xap_virtual_devices{$virtual_device_name}{socket} = $xap_socket;
         $xap_virtual_devices{$virtual_device_name}{port} = $port;
      }

      # now that a listen port exists, advertise it w/ the first hbeat msg
      if ($xap_send) {
         &send_xap_heartbeat('alive', $virtual_device_name);
      }
   }

}

sub open_port {
    my ($port, $send_listen, $local) = @_;

    my $sock;
    if ($send_listen eq 'send') {
        my $dest_address;
#       $dest_address = inet_ntoa(INADDR_BROADCAST);
        $dest_address = '255.255.255.255';
        $dest_address = 'localhost' if $local;
        $sock = new IO::Socket::INET->new(PeerPort => $port, Proto => 'udp',
                                          PeerAddr => $dest_address, Broadcast => 1);
    }
    else {
        my $listen_address;
        $listen_address = '0.0.0.0';
        $listen_address = 'localhost' if $local;
        $sock = new IO::Socket::INET->new(LocalPort => $port, Proto => 'udp',
                                          LocalAddr => $listen_address, Broadcast => 1);
    }
    unless ($sock) {
        return 0;
    }

    return $sock;
}

                                  # Parse incoming xAP records
sub parse_data {
    my ($data) = @_;
    my ($data_type, %d);
    for my $r (split /[\r\n]/, $data) {
        next if $r =~ /^[\{\} ]*$/;
                                  # Store xap-header, xap-heartbeat, and other data
        if (my ($key, $value) = $r =~ /(.+?)=(.*)/) {
            $key   = lc $key;
            $value = lc $value if ($data_type =~ /^xap/ || $data_type =~ /^xpl/); # Do not lc real data;
            $d{$data_type}{$key} = $value;
        }
                                  # data_type (e.g. xap-header, xap-heartbeat, source.instance
        else {
            $data_type = lc $r;
        }
    }
    return \%d;
}

sub socket_has_data {
   my ($sock, $timeout) = @_;
   $timeout = 0 unless $timeout;
   my $rbit = '';
   vec($rbit, fileno( $sock ), 1) = 1;
   my ($nfound) = select($rbit, undef, undef, $timeout);
   return $nfound;
}

sub check_for_data {
    my ($timeout) = @_;
    for my $virtual_device_name (keys %{xap_virtual_devices}) {
       my $xap_socket = $xap_virtual_devices{$virtual_device_name}{socket};
       if ($xap_socket) {
         if (&socket_has_data($xap_socket, $timeout)) {
             my $xap_data;
             my $from_saddr = recv($xap_socket, $xap_data, 1500, 0);
             if ($xap_data) {
	        &_process_incoming_xap_data($xap_data, $virtual_device_name);
             }
          }
       }
    }
}

sub _process_incoming_xap_data {
    my ($data, $device_name) = @_;

    my $xap_data = &parse_data($data);

    my ($protocol, $source, $class, $target);
    if ($$xap_data{'xap-header'} or $$xap_data{'xap-hbeat'}) {
            $protocol = 'xAP';
            $source   = $$xap_data{'xap-header'}{source};
            $class    = $$xap_data{'xap-header'}{class};
	    $target   = $$xap_data{'xap-header'}{target};
            $source   = $$xap_data{'xap-hbeat'}{source} unless $source;
            $class    = $$xap_data{'xap-hbeat'}{class}  unless $class;
	    $target   = $$xap_data{'xap-hbeat'}{target} unless $target;
    }
    # set target as a wildcard if unspecified
    $target = '*' if !($target);

    print "DBG (xAP::Comm): source=$source class=$class target=$target data=$data" if $log_level > 4;
    return unless $source;

    # continue processing if not the source (e.g., heat-beats)
    if ($source ne &get_xap_source_info()) {
                                  # Set states in matching xAP objects
       foreach my $o (@registered_xap_items) {
          # don't continue processing object if it's not bound to the device
          next unless $o->device_name() eq $device_name;

          print "DBG (xAP::Comm): s=$source os=$$o{source} c=$class oc=$$o{class}\n" if $log_level > 4;
          my $regex_ref_source = &wildcard_2_regex($$o{source});
          my $regex_ref_target = &wildcard_2_regex($$o{target_address});
          if (!($o->is_local())) {
             next unless $source  =~ /$regex_ref_source/i;
          } else {
             next unless $source =~ /$regex_ref_target/i;
          }

          # is current xap object a virtual device?
          my $objectIsVirtual = 0;
          # if so, is the source also from a virtual device?
          my $senderIsVirtual = 0;
          for my $virtual_device_name (keys %{xap_virtual_devices}) {
             if ($virtual_device_name eq $o->device_name()) {
                $objectIsVirtual = 1;
             }
             if (($source =~ /$virtual_device_name/) and ($virtual_device_name ne $xap_real_device_name)) {
                $senderIsVirtual = 1;
             }
          }
          # don't continue if the sender and object are both virtual xap devices
          next if ($objectIsVirtual) and ($senderIsVirtual);
          # handle target wildcarding if it applies
          if ($$o{target_address}) {
             my $regex_source = &wildcard_2_regex($source);
             my $regex_target = &wildcard_2_regex($target);

             if (!($o->is_local())) {
                next unless ($target =~ $regex_ref_target) 
                         or ($$o{target_address} =~ $regex_target);
             } else {
                next unless ($source =~ $regex_ref_target) 
                         or ($$o{target_address} =~ $regex_source);
             }
          }
          # check/handle hbeats
          for my $section (keys %{$xap_data}) {
	     if (lc $class eq 'xap-hbeat') {
	        if (lc $class eq 'xap-hbeat.alive') {
	           $o->_handle_alive_app();
		} else {
		   $o->_handle_dead_app();
	        }
	     }
	  }
         my $regex_class = &wildcard_2_regex($$o{class});
          next unless lc $class   =~ /$regex_class/i;
 
                                  # Find and set the state variable
          my $state_value;
          $$o{changed} = '';
          for my $section (keys %{$xap_data}) {
             $$o{sections}{$section} = 'received' unless $$o{sections}{$section};
             for my $key (keys %{$$xap_data{$section}}) {
                my $value = $$xap_data{$section}{$key};
	        # does a tied value convertor exist for this key and object?
                $$o{$section}{$key} = $value;
                # Monitor what changed (real data, not hbeat).
                $$o{changed} .= "$section : $key = $value | "
                    unless $section eq 'xap-header'; # or ($section eq 'xap-hbeat' and !($$o{class} =~ /^xap-hbeat/i));
#                       print "state check key=$section : $key  value=$value\n";
                if ($$o{state_monitor} and "$section : $key" eq $$o{state_monitor} and defined $value) {
                   print "DBG (xAP::Comm): setting state to $value\n" if $log_level > 4;
                   $state_value = $value;
                }
             }
          }
          $state_value = $$o{changed} unless defined $state_value;
          if ($o->allow_empty_state() || (defined $state_value and $state_value ne '')) {
             print "DBG (xAP::Comm): Setting xAP object set_now() to: $state_value\n" if $log_level > 4;
             $o -> set_now($state_value, 'xAP') ;
          }
       }
    }
}

sub get_xap_uid {
   my ($device_type, $subaddress_name) = @_;
   my $uid = &get_xap_base_uid($device_type) . &get_xap_subaddress_uid($device_type, $subaddress_name);
   return $uid;
}

sub get_xap_subaddress_uid {
   my ($p_type_name, $subaddress_name, $requested_uid) = @_;
   my $subaddress_uid = "00";
   if ($subaddress_name) {
      if (exists($xap_uids{$p_type_name}) && exists($xap_uids{$p_type_name}{'sub-fwd-map'}{$subaddress_name})) {
         $subaddress_uid = $xap_uids{$p_type_name}{'sub-fwd-map'}{$subaddress_name};
      } else {
         # did we get a $requested_uid?
         if ($requested_uid && (length($requested_uid) == 2)) { # not a very robust validation
            # try to honor the request
            if (!(exists($xap_uids{$p_type_name}{'sub-rvs-map'}{$requested_uid}))) {
               $subaddress_uid = $requested_uid;
            }
         } 
         if (!($requested_uid) || $subaddress_uid eq '00') {
            my $last_xap_subaddress_uid = $xap_uids{$p_type_name}{'last_sub_uid'};
            $last_xap_subaddress_uid = 0 unless $last_xap_subaddress_uid;
            $last_xap_subaddress_uid++;
            # store it
            $xap_uids{$p_type_name}{'last_sub_uid'} = $last_xap_subaddress_uid;
            #convert to hex
            $subaddress_uid = sprintf("%X", $last_xap_subaddress_uid);
            if (length($subaddress_uid) % 2) {
               $subaddress_uid = "0$subaddress_uid"; # pad w/ a 0 if number of chars is odd
            }
         }
         #and, store it in the hash
         $xap_uids{$p_type_name}{'sub-fwd-map'}{$subaddress_name} = $subaddress_uid;
         # as well as the reverse map
         $xap_uids{$p_type_name}{'sub-rvs-map'}{$subaddress_uid} = $subaddress_name;
      }
   }
   return $subaddress_uid; 
}

sub get_xap_subaddress_devname {
   my ($p_type_name, $p_subaddress_uid) = @_;
   my $devname = '';
   if (exists($xap_uids{$p_type_name}{'sub-rvs-map'}{$p_subaddress_uid})) {
      $devname = $xap_uids{$p_type_name}{'sub-rvs-map'}{$p_subaddress_uid};
   }
   return $devname;
}

sub get_xap_base_uid {
   my ($p_type_name) = @_;
   if (!(defined($p_type_name)) || ($p_type_name eq $xap_real_device_name)) {
      $p_type_name = $xap_real_device_name;
      if (exists($xap_uids{$p_type_name}) && exists($xap_uids{$p_type_name}{'base'})) {
         return $xap_uids{$p_type_name}{'base'};
      } else {
         # allow an override via the xap_uid
         my $uid = $default_base_uid;
         # all uids must start with FF
         if (defined($uid) and ($uid =~ /^FF/)) {
            if (length($uid) > 6) {
               # get the first 6 digits
               $uid = substr($uid,0,6);
            } elsif (length($uid) == 6) {
               # do nothing
            } else {
            # set to something likely not conflict; FF123400 is too common
	       $uid = 'FFE800'
            }
         } else {
            $uid = 'FFE800';
         }
         # store it
         $xap_uids{$p_type_name}{'base'} = $uid;
	 # convert and save it
         $xap_uids{'last_base_uid'} = hex($uid);
	 return $uid;
      }
   } else {
      if (exists($xap_uids{$p_type_name})) {
         return $xap_uids{$p_type_name}{'base'};
      } else {
	 # get the last base uid and convert hex string to number
         my $uid = &get_xap_base_uid($xap_real_device_name); # make sure it's initialized
         $uid = $xap_uids{'last_base_uid'};
         my $uid_num = $uid;
	 # increment number and convert back to hex string
	 $uid_num = $uid_num + 1;
         $uid = sprintf("%X", $uid_num);
         $xap_uids{'last_base_uid'} = $uid_num;
         if (length($uid) % 2) {
            $uid = "0$uid"; # pad w/ a 0 if an odd number of chars
         }
         $xap_uids{$p_type_name}{'base'} = $uid;
	 return $uid;
      }
   }
}

sub get_xap_source_info {
   my ($instance) = @_;
   $instance = $xap_real_device_name if !($instance);
   $instance =~ tr/ /_/;
   return $xap_vendor_info . '.' . $xap_device_info . '.' . $instance;
}

sub wildcard_2_regex {
   my ($expr) = @_;
   return unless $expr;
   # convert all periods
   $expr =~ s/\./(\\\.)/g;
   # convert all asterisks
   $expr =~ s/\*/(\.\*)/g;
   # treat all :> as asterisks
   $expr =~ s/:>/(\.\*)/g;
   # convert all greater than symbols
   $expr =~ s/>/(\.\*)/g;

   return $expr;
}

sub sendXap {
      my ($target, $class_name, @data) = @_;
      my ($headerVars,@data2);
      $headerVars->{'class'} = $class_name;
      $headerVars->{'target'} = $target if defined $target;
      push @data2, $headerVars;
      while (@data) {
         my $section = shift @data;
         push @data2, $section, shift @data;
      }
      &sendXapWithHeaderVars(@data2);    
}

sub sendXapWithHeaderVars {
    if (defined($xap_send)) {
       my (@data) = @_;
       my ($parms, $msg, $headerVarsPtr, %headerVars);
   
       $headerVarsPtr = shift @data;
       %headerVars = %$headerVarsPtr;
       $msg  = "xap-header\n{\n";
       $msg .= "v=12\n";
       $msg .= "hop=1\n";
       if (exists($headerVars{'uid'})) {
          $msg .= "uid=" . $headerVars{'uid'} . "\n";
       } else {
          $msg .= "uid=" . &get_xap_uid() . "\n";
       }
       $msg .= "class=" . $headerVars{'class'} . "\n";
       if (exists($headerVars{'source'})) {
          $msg .= "source=" . $headerVars{'source'} . "\n";
       } else {
          $msg .= "source=" . &get_xap_source_info() . "\n";
       }
       if (exists($headerVars{'target'}) && ($headerVars{'target'} ne '*')) {
          $msg .= "target=" . $headerVars{'target'} . "\n";
       }
       $msg .= "pid=$$\n}\n";
       while (@data) {
          my $section = shift @data;
          $msg .= "$section\n{\n";
          my $ptr = shift @data;
          my %parms = %$ptr;
          for my $key (sort keys %parms) {
             $msg .= "$key=$parms{$key}\n";
          }
          $msg .= "}\n";
       }
       print "DBG (xAP::Comm): xap msg: $msg\n" if $log_level > 4;
       if ($xap_send) {
       #   print $xap_send $msg;
          $xap_send->send($msg);
       } else {
          print "WARN (xAP::Comm): xAP socket is not available for sending!\n" if $log_level > 1;
       }
   } else {
      print "WARN (xAP::Comm): xAP is disabled and you are trying to send xAP data!!\n" if $log_level > 1;
   }
}

sub send_xap_heartbeat {
      my ($hbeat_type, $base_ref) = @_;
      if ($xap_send) {
         
         if ($base_ref) {
            my $port = $xap_virtual_devices{$base_ref}{port};

            my $xap_hbeat_interval_in_secs = $xap_hbeat_interval * 60;
            my $xap_version = '12';
            my $msg = "xap-hbeat\n{\nv=$xap_version\nhop=1\n";
            $msg .= "uid=" . &get_xap_base_uid($base_ref) . "00" . "\n";
            $msg .= "class=xap-hbeat.$hbeat_type\n";
            $msg .= "source=" . &get_xap_source_info($base_ref) . "\n";
            $msg .= "interval=$xap_hbeat_interval_in_secs\nport=$port\npid=$$\n}\n";
    #        print $xap_send $msg;
            $xap_send->send($msg);
            print "DBG (xAP::Comm): xap heartbeat: $msg.\n" if $log_level > 4;
         } else {
            for my $virtual_device_name (keys %{xap_virtual_devices}) {
               my $port = $xap_virtual_devices{$virtual_device_name}{port};
               my $base_ref = $virtual_device_name;
               $base_ref = "core" if !($base_ref);
               $hbeat_type = 'alive' if !($hbeat_type);

               my $xap_hbeat_interval_in_secs = $xap_hbeat_interval * 60;
               my $xap_version = '12';
               my $msg = "xap-hbeat\n{\nv=$xap_version\nhop=1\n";
               $msg .= "uid=" . &get_xap_base_uid($base_ref) . "00" . "\n";
               $msg .= "class=xap-hbeat.$hbeat_type\n";
               $msg .= "source=" . &get_xap_source_info($base_ref) . "\n";
               $msg .= "interval=$xap_hbeat_interval_in_secs\nport=$port\npid=$$\n}\n";
               #print $xap_send $msg;
               $xap_send->send($msg);
               print "DBG (xAP::Comm): xap heartbeat: $msg.\n" if $log_level > 4;

            }
         }
   }
}

1


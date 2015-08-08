package xAP::BSC_Item;

=begin comment
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

File:
	BSC.pm

Description:
	xAP support for Basic Status and Control schema
	
Author:
	Gregg Liming
	gregg@limings.net

License:
	This free software is licensed under the terms of the GNU public license.

Usage:

	Example initialization:



Special Thanks to: 
	Bruce Winter - MH
		

@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
=cut

use xAP::Comm;
use xAP::xAP_Item;

use constant INPUT => 'input';
use constant OUTPUT => 'output';


#Initialize class
sub new 
{
   my ($class, $p_family_name, $p_source_name, $p_target_name) = @_;
   my $self={};
   bless $self, $class;

   $$self{m_xap} = new xAP::xAP_Item($p_family_name, $p_source_name);
   $$self{m_xap}->target_address($p_target_name) if $p_target_name;
   $$self{m_xap}->class_name('xAPBSC.*');
   $$self{_family_name} = $p_family_name;
   $self->_initialize();

   $$self{m_xap}->tie_items($self);
	
   return $self;
}

sub _initialize
{
   my ($self) = @_;
   $$self{m_registered_objects} = ();
   $$self{pending_device_state_mode} = ();
   $$self{pending_device_state} = ();
   $$self{device_state} = ();
}

sub is_local
{
   my ($self, $p_is_local) = @_;
   $$self{m_xap}->is_local($p_is_local) if defined $p_is_local;
   return $$self{m_xap}->is_local();
}

sub set_now 
{
   my ($self, $p_state, $p_setby) = @_;
   my $state = $p_state;
   # don't do anything if setby an inherited object
   if (($p_setby != $self)) {
      if ($p_setby eq $$self{m_xap} ) {
         $$self{device_target} = $$self{m_xap}{target_address};
         my ($xap_subaddress) = $$self{m_xap}{target_address} =~ /.+\:(.+)/;
         $$self{device_subaddress_target} = $xap_subaddress;

         if ($self->is_local()) {
         # then we're interested in cmd and query messages sent to us 
            if (lc $$self{m_xap}{'xap-header'}{class}  eq 'xapbsc.cmd') {
               # handle command
               $state = $self->cmd_callback($p_setby);
            } elsif (lc $$self{m_xap}{'xap-header'}{class} eq 'xapbsc.query') {
               # handle query
               $state = $self->query_callback($$p_setby{'xap-header'}{target}, $$p_setby{'xap-header'}{source});
            }
         } else {
            # is remote and therefore care about state updates from others
            if (lc $$self{m_xap}{'xap-header'}{class} eq 'xapbsc.event') {
               # handle event
               $state = $self->event_callback($p_setby);
            } elsif (lc $$self{m_xap}{'xap-header'}{class} eq 'xapbsc.info') {
               # handle info
               $state = $self->info_callback($p_setby);
            }
         }
      } else {
         print "Unable to process $state\n";
      }
   }

   return;
}

sub setcallback {
        my ($self, $event, $function) = @_;

        if (defined($function) && ref($function) eq 'CODE') {
                $self->{_EVENTCB}{$event} = $function;
        }
}

sub eventcallback {
        my ($self, $event, %data) = @_;

        my $callback;

        return if (!$event);

        if (defined($self->{_EVENTCB}{$event})) {
                $callback = $self->{_EVENTCB}{$event};
        } elsif (defined($self->{_EVENTCB}{DEFAULT})) {
                $callback = $self->{_EVENTCB}{DEFAULT};
        } else {
                return;
        }

        return &{$callback}(%data);
}

sub cmd_callback {
   my ($self, $p_xap) = @_;
  for my $section_name (keys %{$p_xap}) {      
      next unless ($section_name =~ /^(output)\.state\.\d+/);
      my %data = ();
      print "Process section:$section_name\n";
      my ($id,$state,$level,$text);
      for my $field_name (keys %{$$p_xap{$section_name}}) {
         my $value = $$p_xap{$section_name}{$field_name};
         if (lc $field_name eq 'id') {
            $data{id} = $value;
         } elsif (lc $field_name eq 'state') {
            $data{state} = $value;
         } elsif (lc $field_name eq 'level') {
            $data{level} = $value;
         } elsif (lc $field_name eq 'text') {
            $data{text} = $value;
         } elsif (lc $field_name eq 'displaytext') {
            $data{displaytext} = $value;
         }
      }
      if (($data{id}) and ($data{state})) {
         $data{mode} = 'output'; # cmds can only affect an 'output'
         $data{source} = $$p_xap{'xap-header'}{source};
         $self->eventcallback('cmd', %data);
#         $self->set_device($id, '', $mode, $state, $level, $text);
      }
   }
   return 'cmd';
}

sub query_callback {
   my ($self, $p_target, $p_source) = @_;
   return 'query';
}

sub event_callback {
   my ($self, $p_xap) = @_;
   for my $section_name (keys %{$p_xap}) {      
      next unless ($section_name =~ /^(input|output)\.state\.\d*/);
      print "BSC_Item->event_callback: Process section:$section_name\n";
      for my $field_name (keys %{$p_xap{$section_name}}) {
         my ($id,$state,$level,$text);
         if (lc $field_name eq 'id') {
            $id = $$p_xap{$section_name}{$field_name};
         } elsif (lc $field_name eq 'state') {
            $state = $$p_xap{$section_name}{$field_name};
         }
      }
   }
   return 'event';
}

sub info_callback {
   my ($self, $p_xap) = @_;
   return 'info';
}

sub send_query {
   my ($self, $target);
   $target = '*' unless $target; # this is probably a bad idea since wildcarding should only be done to endpoints
   my ($headerVars, @data2);
   $headerVars->{'class'} = 'xAPBSC.query';
   $haaderVars->{'target'} = $target;
   $headerVars->{'source'} = &xAP::get_xap_source_info($$self{_family_name});
   $headerVars->{'uid'} = &xAP::get_xap_uid($$self{_family_name}, '00');
   push @data2, $headerVars;
   push @data2, 'request', ''; # hmmm, this could blow-up maybe? really only want a blank request block

   &xAP::sendXapWithHeaderVars(@data2);    

}

sub send_info {
   my ($self, $subaddress_name, %data) = @_;

   my ($subaddress) = $subaddress_name =~ /^\$*:(.*)/;
   my ($headerVars, @data2);
   $headerVars->{'class'} = 'xAPBSC.info';
   $headerVars->{'source'} = &xAP::Comm::get_xap_source_info($$self{_family_name}) . ":" . $subaddress_name;
   $headerVars->{'uid'} = &xAP::Comm::get_xap_base_uid($$self{_family_name}) 
                  . &xAP::Comm::get_xap_subaddress_uid($$self{_family_name}, $subaddress_name, $data{id});;
   push @data2, $headerVars;

   my $bsc_block;
   if ($data{state}) {
      $bsc_block->{'State'} = $data{state};
   } else {
      $bsc_block->{'State'} = '?';
   }
   $bsc_block->{'Level'} = $data{level} if $data{level};
   $bsc_block->{'Text'} = $data{text} if $data{text};
   my $block_name = "$data{mode}.state";
   push @data2, $block_name, $bsc_block;
 
   &xAP::Comm::sendXapWithHeaderVars(@data2);    
   
}

sub send_event {
   my ($self, $subaddress_name, %data) = @_;

   my ($subaddress) = $subaddress_name =~ /^\$*:(.*)/;
   my ($headerVars, @data2);
   $headerVars->{'class'} = 'xAPBSC.event';
   $headerVars->{'source'} = &xAP::Comm::get_xap_source_info($$self{_family_name}) . ":" . $subaddress_name;
   $headerVars->{'uid'} = &xAP::Comm::get_xap_base_uid($$self{_family_name}) 
                  . &xAP::Comm::get_xap_subaddress_uid($$self{_family_name}, $subaddress_name, $data{id});;
   push @data2, $headerVars;

   my $bsc_block;
   if ($data{state}) {
      $bsc_block->{'State'} = $data{state};
   } else {
      $bsc_block->{'State'} = '?';
   }
   $bsc_block->{'Level'} = $data{level} if $data{level};
   $bsc_block->{'Text'} = $data{text} if $data{text};
   my $block_name = "$data{mode}.state";
   push @data2, $block_name, $bsc_block;
 
   &xAP::Comm::sendXapWithHeaderVars(@data2);    
   
}

1;

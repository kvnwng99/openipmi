#!/usr/bin/perl

# test_atca
#
# A sample file that tests some parts of ATCA
#
# Author: MontaVista Software, Inc.
#         Corey Minyard <minyard@mvista.com>
#         source@mvista.com
#
# Copyright 2004 MontaVista Software Inc.
#
#  This program is free software; you can redistribute it and/or
#  modify it under the terms of the GNU Lesser General Public License
#  as published by the Free Software Foundation; either version 2 of
#  the License, or (at your option) any later version.
#
#
#  THIS SOFTWARE IS PROVIDED ``AS IS'' AND ANY EXPRESS OR IMPLIED
#  WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF
#  MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.
#  IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY DIRECT, INDIRECT,
#  INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING,
#  BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS
#  OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
#  ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR
#  TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE
#  USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
#
#  You should have received a copy of the GNU Lesser General Public
#  License along with this program; if not, write to the Free
#  Software Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
#

use OpenIPMI;

$debug = 0;

$errcount = 0;

sub parent_entity_id {
    my $entity_id = shift;

    return (($entity_id == 0xa0) # front board
	    || ($entity_id == 0xc0) # RTM
	    || ($entity_id == 0xf1) # filtration unit
	    || ($entity_id == 0xf2) # shelf FRU
	    || ($entity_id == 0x0a) # Power filtration
	    || ($entity_id == 0x1e)); # Fan tray
}

{
    package EntityLister;
    sub new {
	my $a = {};
	$a->{indent} = "    ";
	return bless \$a;
    }

    sub entity_iter_entities_cb {
	my $self = shift;
	my $parent = shift;
	my $child = shift;
	my $oldindent;

	print $$self->{indent}, $child->get_name(), "\n";

	if ($child->is_parent()) {
	    $oldindent = $$self->{indent};
	    $$self->{indent} = $oldindent . "  ";
	    $child->iterate_children($self);
	    $$self->{indent} = $oldindent;
	}
    }


    # Used to hunt for the proper parent.
    package ParentEntityIDFinder;
    sub new {
	my $a = {};
	$a->{entity_id} = -1;
	$a->{in_chassis} = 0;
	return bless \$a;
    }

    sub entity_iter_entities_cb {
	my $self = shift;
	my $child = shift;
	my $parent = shift;

	if ($main::debug) {
	    print "Parent of " . $child->get_name() . " is "
		. $parent->get_name() . "\n";
	}

	$entity_id = $parent->get_entity_id();

	if ($entity_id == 23) {
	    # Chassis, just mark it as such.
	    $$self->in_chassis = 1;
	} elsif (main::parent_entity_id($entity_id)) {
	    if ($$self->{entity_id} != -1) {
		$main::errcount++;
		print "*** Entity " . $parent->get_name(). " has more than"
		    . " one to-level entity in it's path\n";
	    } else {
		$$self->{entity_id} = $entity_id;
	    }
	}
    }

    package ParentChecker;
    sub new {
	my $a = {};
	$a->{count} = 1;
	return bless \$a;
    }

    sub entity_iter_entities_cb {
	my $self = shift;
	my $child = shift;
	my $parent = shift;

	my $entity_id;
	my $entity_instance;
	my $device_channel;
	my $device_address;

	$entity_id = $parent->get_entity_id();
	$entity_instance = $parent->get_entity_instance();

	if ($$self->{count} != 1) {
	    $main::errcount++;
	    print "*** Entity " . $child->get_name() . " has more than one"
		. " parent\n";
	}
	$$self->{count}--;

	if ($child->get_entity_device_channel()
	    != $parent->get_entity_device_channel())
	{
	    $main::errcount++;
	    print "*** Entity parent " . $parent->get_name() . " does not have"
		. " the same device channel as child " . $child->get_name()
		. "\n";
	}

	if ($child->get_entity_device_address()
	    != $parent->get_entity_device_address())
	{
	    $main::errcount++;
	    print "*** Entity parent " . $parent->get_name() . " does not have"
		. " the same device address as child " . $child->get_name()
		. "\n";
	}
    }


    package Handlers;

    sub new {
	my $a = shift;
	my $b = \$a;
	return bless $b;
    }

    sub entity_update_cb {
	my $self = shift;
	my $op = shift;
	my $domain = shift;
	my $entity = shift;

	my $entity_id;
	my $entity_instance;
	my $device_channel;
	my $device_address;

	if ($main::debug) {
	    print $op, " entity ", $entity->get_name(), "\n";
	}
	if ($op eq "added") {
	    $entity_id = $entity->get_entity_id();
	    $entity_instance = $entity->get_entity_instance();
	    $device_channel = $entity->get_entity_device_channel();
	    $device_address = $entity->get_entity_device_address();

	    if (($entity_id == 23) && ($entity_instance == 1)) {
		# The shelf entity, the only thing that is system-relative

	    } elsif (main::parent_entity_id($entity_id)) {
		# These are the top-level entities of the system.
		# They should be the parents of the things that are
		# on them, but we check that elsewhere.  They must
		# be device-relative.  These are children of the
		# chassis entity, but OpenIPMI does that, there should
		# not be an association record for that.
		if ($entity_instance < 0x60) {
		    $main::errcount++;
		    print "*** Entity " . $entity->get_name() . " is not"
			. " device relative\n";
		}
	    } elsif ($entity_id == 0xf0) {
		# Ignore the shelf manager.
	    } else {
		# These are the child entities that should be device-relative
		# and contained in the proper parent entity.
		if ($entity_instance < 0x60) {
		    $main::errcount++;
		    print "*** Entity " . $entity->get_name() . " is not"
			. " device relative\n";
		}

		if (!$entity->is_child()) {
		    $main::errcount++;
		    print "*** Entity " . $entity->get_name() . " is not a"
			. " child\n";
		} else {
		    my $checker = ParentChecker::new();
		    $entity->iterate_parents($checker);

		    $checker = ParentEntityIDFinder::new();
		    $entity->iterate_parents($checker);

		    if ($$checker->{entity_id} == -1) {
			$main::errcount++;
			print "*** Entity " . $entity->get_name() . " does not"
			    . " have a valid parent entity\n";
		    }
		}
	    }
	}
    }

    sub conn_change_cb {
	my $self = shift;
	my $domain = shift;
	my $err = shift;
	my $conn_num = shift;
	my $port_num = shift;
	my $still_connected = shift;
	my $rv;
	my $i;

	if ($$self eq "hello") {
	    $i = new("goodbye");

	    $rv = $domain->add_entity_update_handler($i);
	    if ($rv) {
		print "Unable to add entity updated handler: $rv\n";
	    }
	}
    }

    sub domain_iter_entity_cb {
	my $self = shift;
	my $domain = shift;
	my $entity = shift;
	my $iterobj;

	# Start from the top entities
	if (!$entity->is_child()) {
	    print "  ", $entity->get_name(), "\n";
	    $iterobj = EntityLister::new();
	    $entity->iterate_children($iterobj);
	}
    }

    sub domain_up_cb {
	my $self = shift;
	my $domain = shift;
	my $rv;
	my $event;

	if ($main::debug) {
	    print "Domain fully up\n";
	}

	print "Entity tree is:\n";
	$domain->iterate_entities($self);

	$domain->close($main::h);
    }

    sub domain_close_done_cb {
	my $self = shift;

	$$self = "done";
    }

    sub log {
	my $self = shift;
	my $level = shift;
	my $log = shift;

	if ((!$main::debug) &&
	    (($level eq "INFO")
	     || ($level eq "EINF")
	     || ($level eq "WARN")))
	{
	    # Ignore informational stuff and warnings.
	    return;
	}

	print $level, ": ", $log, "\n";
    }
}

$Handlers::stop_count = 0;

OpenIPMI::enable_debug_malloc();
$rv = OpenIPMI::init();
if ($rv != 0) {
    print "init failed";
    exit 1;
}

$h = Handlers::new("hello");

OpenIPMI::set_log_handler($h);

@args = @ARGV;
unshift @args, "-noall", "-oeminit", "-noseteventrcvr", "-sdrs", "-ipmbscan";

$a = OpenIPMI::open_domain("test", \@args, $h, $h);
if (! $a) {
    print "open failed\n";
    exit 1;
}

while ($$h ne "done") {
    OpenIPMI::wait_io(1000);
}

OpenIPMI::shutdown_everything();
if ($main::errcount == 0) {
    print "Test completed successfully\n";
    exit 0;
} else {
    print "Errors running test\n";
    exit 1;
}

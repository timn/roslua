
----------------------------------------------------------------------------
--  subscriber.lua - subscriber implementation test
--
--  Created: Mon Jul 27 15:37:01 2010 (at Intel Research, Pittsburgh)
--  Copyright  2010  Tim Niemueller [www.niemueller.de]
--
----------------------------------------------------------------------------

-- Licensed under BSD license

require("roslua")

-- the following require is only for test program to ensure that we wait for
-- the rosout publisher, do not do this in "normal" programs!
require("roslua.logging.rosout")

roslua.init_node{master_uri=os.getenv("ROS_MASTER_URI"),
		 node_name="/logtest"}

roslua.logging.rosout.pub_rosout:wait_for_subscriber()

printf("This is a %s test", "printf")
print_debug("Printing DEBUG")
print_info("Printing INFO")
print_warn("Printing WARN")
print_error("Printing ERROR")
print_fatal("Printing FATAL")

/* !setmode.
!arm.

+!setmode
   <- 
      .set_mode("AUTO.TAKEOFF");
      .wait(1000);
      .print("Set mode to AUTO.TAKEOFF.").

+!arm
   <- 
      .arming(true);
      .wait(1000);
      .print("Armed the drone."). */

!start.
+!start <-
    // 1. Clear 
    .mission_clear;
    .wait(1500);
    
    .mission_push(0, [
      [0, 22, 1, 1, 0, 0, 0, 0, 47.3977419, 8.5455938, 7],
      [0, 16, 0, 1, 0, 0, 0, 0, 47.3977569, 8.5456338, 7]
      ]);
    .wait(500);
   


    .set_mode("AUTO.MISSION");
    .wait(1000);
    .arming(true).


/* !pub_waypoints.
+!pub_waypoints : true
   <- .setpoint_local([0.0,0.0,'map'],[[10.0, 5.0, 8.0], [0.0, 0.0, 0.0, 1.0]]);
      //.wait(500);
      !pub_waypoints.

!mode.
+!mode : true
   <- .set_mode("OFFBOARD").

!arm.
+!arm : true
   <- .arming(true). */
 

    
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
    .time(_, M, S, MS);
    .print("Starting clearing mission at: ", M, ":", S, ":", MS);
    .mission_clear;
    .time(_, M1, S1, MS1);
    .print("Finishing clearing mission at: ", M1, ":", S1, ":", MS1);
    .wait(1500);
    .time(_, M2, S2, MS2);
    .print("Starting mission push at: ", M2, ":", S2, ":", MS2);
    .mission_push([0], [
      [0, 22, true, true, 0, 0, 0, 0, 47.3977419, 8.5455938, 7],
      [0, 16, false, true, 0, 0, 0, 0, 47.3977569, 8.5456338, 7],
      [0, 16, false, true, 0, 0, 0, 0, 47.3977919, 8.5456438, 7],
      [0, 16, false, true, 0, 0, 0, 0, 47.3977869, 8.5456538, 7],
      [0, 16, false, true, 0, 0, 0, 0, 47.3978959, 8.5456638, 7]
      ]);
    .time(_, M3, S3, MS3);
    .print("Finishing mission push at: ", M3, ":", S3, ":", MS3);
    .wait(500);
    .time(_, M4, S4, MS4);
    .print("Starting set mode at: ", M4, ":", S4, ":", MS4);
    .set_mode("AUTO.MISSION");
    .time(_, M5, S5, MS5);
    .print("Finishing set mode at: ", M5, ":", S5, ":", MS5);
    .wait(1000);
    .time(_, M6, S6, MS6);
    .print("Starting arming at: ", M6, ":", S6, ":", MS6);
    .arming(true);
    .time(_, M7, S7, MS7);
    .print("Finishing arming at: ", M7, ":", S7, ":", MS7).


/* !pub_waypoints.
+!pub_waypoints : true
   <- .setpoint_local([[0,0], 'map'],[[10.0, 5.0, 8.0], [0.0, 0.0, 0.0, 1.0]]);
      
      .wait(100);
      !pub_waypoints.

!mode.
+!mode : true
   <- .set_mode("OFFBOARD").

!arm.
+!arm : true
   <- .arming(true).  */

+battery(percentage(P))
   <- 
      .nano_time(T);
      if (P < 0.60) {
         .nano_time(T1);
         .print("Total Time after agent percepted: ", T1 - T);
         .print("Battery level getting low: ", P);
         .nano_time(T2);
         .set_mode("AUTO.LAND");
         .nano_time(T3);
         .print("Total time to enter AUTO.LAND mode: ", T3 - T2);
         .print("Entered AUTO.LAND mode");
         }
      
      .wait(5000).
 

    
-- Grabbing a drop: a small additive sparkle that reads as "that was yours"
-- without competing with anything happening in the fight.
--
-- Uses the same white star off game/particles.tga that the explosion throws as
-- sparks, at a fraction of the speed.

FXParm ("num_parts", 9);
FXParm ("blend_mode", "ADDITIVE");
FXParm ("bitmap", "game/particles.tga");
FXParm ("bitmap_rect", 138, 74, 44, 44);

FXParm ("age_to_die", 0.3, 0.55);
FXParm ("area_radius", 0, 8);
FXParm ("area_angle_spread", 360);

FXParm ("move_angle_spread", 360);
FXParm ("move_speed", 60, 150);
FXParm ("mass", 4);

FXParm ("alpha", 0.7, 0.95);
FXParm ("scale_graph", 0, 0.10);
FXParm ("scale_graph", 0.3, 0.26);
FXParm ("scale_graph", 1, 0.04);
FXParm ("alpha_graph", 0, 1);
FXParm ("alpha_graph", 0.5, 1);
FXParm ("alpha_graph", 1, 0);

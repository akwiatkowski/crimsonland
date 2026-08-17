-- Blood spray where a bullet connects. Spawned with rot = the bullet's own
-- heading, so the spray carries on the way the shot was going.
--
-- Sprite is the 30x30 splat at (65,1) of game/particles.tga -- the 256x256
-- sheet the original's C++ side drew its blood, fire and smoke from. The pak
-- ships no blood effect file because none existed: the effects in fxs/ are the
-- handful the UI scripts needed, and everything in the playfield was drawn
-- from C++.

FXParm ("num_parts", 6);
FXParm ("bitmap", "game/particles.tga");
FXParm ("bitmap_rect", 65, 1, 30, 30);

FXParm ("age_to_die", 0.22, 0.45);
FXParm ("area_radius", 0, 4);

-- a forward cone, not a ring: this is spatter off an impact
FXParm ("move_angle", 0);
FXParm ("move_angle_spread", 75);
FXParm ("move_speed", 110, 280);
-- drops slow fast; blood does not sail across the field
FXParm ("mass", 3);

FXParm ("angle_spread", 360);
FXParm ("rot_angle_rps", -240, 240);

FXParm ("alpha", 0.8, 1.0);
FXParm ("scale_graph", 0, 0.30);
FXParm ("scale_graph", 1, 0.14);
FXParm ("alpha_graph", 0, 1);
FXParm ("alpha_graph", 0.55, 1);
FXParm ("alpha_graph", 1, 0);

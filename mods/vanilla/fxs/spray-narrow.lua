-- A tight, fast spray that carries: what comes out of a body when the thing
-- that hit it went through rather than into.
--
-- Two weapons want this and they want it for opposite reasons. The blade gun
-- cuts, so the spray follows the edge in a narrow fan. The gauss family
-- punches through, so the spray keeps going -- which is the whole reason the
-- gauss guns do not also get the blade's slice: giving them the same signature
-- would spend the blade gun's only distinguishing trait on a weapon that has
-- one already.
--
-- Against blood.lua: half the cone (34 degrees against 75), faster, and it
-- travels further before the drag takes it. Same sheet, same splat.

FXParm ("num_parts", 7);
FXParm ("bitmap", "game/particles.tga");
FXParm ("bitmap_rect", 65, 1, 30, 30);

FXParm ("age_to_die", 0.3, 0.55);
FXParm ("area_radius", 0, 3);

FXParm ("move_angle", 0);
FXParm ("move_angle_spread", 34);
FXParm ("move_speed", 300, 620);
-- lighter drag than blood.lua's 3: this is the spray that reaches the ground
-- well behind whatever it came out of
FXParm ("mass", 1.6);

FXParm ("angle_spread", 360);
FXParm ("rot_angle_rps", -240, 240);

FXParm ("alpha", 0.8, 1.0);
FXParm ("scale_graph", 0, 0.26);
FXParm ("scale_graph", 1, 0.12);
FXParm ("alpha_graph", 0, 1);
FXParm ("alpha_graph", 0.6, 1);
FXParm ("alpha_graph", 1, 0);

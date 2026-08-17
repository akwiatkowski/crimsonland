-- Rocket-class detonation, in four layers. The caller scales the whole thing,
-- so one file covers both a rocket (radius 80) and a creature bursting (60).
--
-- All four sprites come off game/particles.tga, and the order below is the
-- order they read in: a hot core that flashes and dies, the painted fireball
-- over it, sparks thrown clear, and smoke left behind after everything else
-- has gone out.

-- 1. the flash: one additive glow, brightest at the first frame
FXParm ("num_parts", 1);
FXParm ("blend_mode", "ADDITIVE");
FXParm ("bitmap", "game/particles.tga");
FXParm ("bitmap_rect", 195, 3, 58, 58);

FXParm ("age_to_die", 0.22, 0.28);
FXParm ("alpha", 0.9, 1.0);
FXParm ("scale_graph", 0, 0.6);
FXParm ("scale_graph", 0.3, 2.4);
FXParm ("scale_graph", 1, 3.0);
FXParm ("alpha_graph", 0, 1);
FXParm ("alpha_graph", 0.25, 0.9);
FXParm ("alpha_graph", 1, 0);


PartFXAddNew ();

-- 2. the fireball proper: the painted one, tumbling slowly outward
PartFXParm ("num_parts", 5);
PartFXParm ("blend_mode", "ADDITIVE");
PartFXParm ("bitmap", "game/particles.tga");
PartFXParm ("bitmap_rect", 68, 65, 55, 62);

PartFXParm ("age_to_die", 0.3, 0.5);
PartFXParm ("area_radius", 0, 16);
PartFXParm ("area_angle_spread", 360);

PartFXParm ("move_angle_spread", 360);
PartFXParm ("move_speed", 40, 130);
PartFXParm ("mass", 3);

PartFXParm ("angle_spread", 360);
PartFXParm ("rot_angle_rps", -80, 80);

PartFXParm ("alpha", 0.8, 1.0);
PartFXParm ("scale_graph", 0, 0.5);
PartFXParm ("scale_graph", 0.4, 1.1);
PartFXParm ("scale_graph", 1, 0.6);
PartFXParm ("alpha_graph", 0, 1);
PartFXParm ("alpha_graph", 0.5, 0.9);
PartFXParm ("alpha_graph", 1, 0);


PartFXAddNew ();

-- 3. sparks: fast, thin, outrunning the fireball
PartFXParm ("num_parts", 14);
PartFXParm ("blend_mode", "ADDITIVE");
PartFXParm ("bitmap", "game/particles.tga");
PartFXParm ("bitmap_rect", 138, 74, 44, 44);

PartFXParm ("age_to_die", 0.25, 0.6);
PartFXParm ("move_angle_spread", 360);
PartFXParm ("move_speed", 220, 560);
PartFXParm ("mass", 2);

PartFXParm ("alpha", 0.7, 1.0);
PartFXParm ("scale_graph", 0, 0.30);
PartFXParm ("scale_graph", 1, 0.05);
PartFXParm ("alpha_graph", 0, 1);
PartFXParm ("alpha_graph", 0.6, 0.8);
PartFXParm ("alpha_graph", 1, 0);


PartFXAddNew ();

-- 4. smoke: normal blend, drifting, still there when the fire is out
PartFXParm ("num_parts", 7);
PartFXParm ("bitmap", "game/particles.tga");
PartFXParm ("bitmap_rect", 198, 66, 52, 60);

PartFXParm ("age_to_die", 0.8, 1.6);
PartFXParm ("age", 0, 0);
PartFXParm ("area_radius", 0, 18);
PartFXParm ("area_angle_spread", 360);

PartFXParm ("move_angle_spread", 360);
PartFXParm ("move_speed", 15, 60);
PartFXParm ("mass", 3);

PartFXParm ("angle_spread", 360);
PartFXParm ("rot_angle_rps", -40, 40);

-- dark and thin: this is soot over a battlefield, not a smoke machine
PartFXParm ("alpha", 0.18, 0.32);
PartFXParm ("scale_graph", 0, 0.4);
PartFXParm ("scale_graph", 1, 1.3);
PartFXParm ("alpha_graph", 0, 0);
PartFXParm ("alpha_graph", 0.15, 1);
PartFXParm ("alpha_graph", 1, 0);

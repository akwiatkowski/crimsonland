-- The ice letting go: what comes off a creature when the freeze runs out or
-- when it dies still encased.
--
-- The pak ships four fragment sprites (game/ice-fragment-0001..0004.png) and
-- one emitter can only name one bitmap, so this is four emitters of one part
-- each -- all four shapes fly, and a thaw across a full field stays cheap.
-- The shard is ~30px inside its 64px frame, hence the small scales.
--
-- Caller scales the whole thing by the creature, so a maggot sheds less ice
-- than a boss.

FXParm ("num_parts", 1);
FXParm ("bitmap", "game/ice-fragment-0001.png");

FXParm ("age_to_die", 0.4, 0.7);
FXParm ("area_radius", 0, 10);
FXParm ("area_angle_spread", 360);

FXParm ("move_angle_spread", 360);
FXParm ("move_speed", 60, 190);
-- ice skitters further than blood does before it stops
FXParm ("mass", 2);

FXParm ("angle_spread", 360);
FXParm ("rot_angle_rps", -260, 260);

FXParm ("alpha", 0.85, 1.0);
FXParm ("scale_graph", 0, 0.55);
FXParm ("scale_graph", 1, 0.35);
FXParm ("alpha_graph", 0, 1);
FXParm ("alpha_graph", 0.6, 1);
FXParm ("alpha_graph", 1, 0);


PartFXAddNew ();

PartFXParm ("num_parts", 1);
PartFXParm ("bitmap", "game/ice-fragment-0002.png");

PartFXParm ("age_to_die", 0.4, 0.7);
PartFXParm ("area_radius", 0, 10);
PartFXParm ("area_angle_spread", 360);

PartFXParm ("move_angle_spread", 360);
PartFXParm ("move_speed", 60, 190);
PartFXParm ("mass", 2);

PartFXParm ("angle_spread", 360);
PartFXParm ("rot_angle_rps", -260, 260);

PartFXParm ("alpha", 0.85, 1.0);
PartFXParm ("scale_graph", 0, 0.5);
PartFXParm ("scale_graph", 1, 0.3);
PartFXParm ("alpha_graph", 0, 1);
PartFXParm ("alpha_graph", 0.6, 1);
PartFXParm ("alpha_graph", 1, 0);


PartFXAddNew ();

PartFXParm ("num_parts", 1);
PartFXParm ("bitmap", "game/ice-fragment-0003.png");

PartFXParm ("age_to_die", 0.35, 0.65);
PartFXParm ("area_radius", 0, 10);
PartFXParm ("area_angle_spread", 360);

PartFXParm ("move_angle_spread", 360);
PartFXParm ("move_speed", 70, 210);
PartFXParm ("mass", 2);

PartFXParm ("angle_spread", 360);
PartFXParm ("rot_angle_rps", -300, 300);

PartFXParm ("alpha", 0.85, 1.0);
PartFXParm ("scale_graph", 0, 0.45);
PartFXParm ("scale_graph", 1, 0.28);
PartFXParm ("alpha_graph", 0, 1);
PartFXParm ("alpha_graph", 0.6, 1);
PartFXParm ("alpha_graph", 1, 0);


PartFXAddNew ();

-- the last one is the small chip: faster, shorter-lived, gone first
PartFXParm ("num_parts", 1);
PartFXParm ("bitmap", "game/ice-fragment-0004.png");

PartFXParm ("age_to_die", 0.3, 0.55);
PartFXParm ("area_radius", 0, 12);
PartFXParm ("area_angle_spread", 360);

PartFXParm ("move_angle_spread", 360);
PartFXParm ("move_speed", 90, 250);
PartFXParm ("mass", 2);

PartFXParm ("angle_spread", 360);
PartFXParm ("rot_angle_rps", -320, 320);

PartFXParm ("alpha", 0.8, 1.0);
PartFXParm ("scale_graph", 0, 0.34);
PartFXParm ("scale_graph", 1, 0.2);
PartFXParm ("alpha_graph", 0, 1);
PartFXParm ("alpha_graph", 0.55, 1);
PartFXParm ("alpha_graph", 1, 0);

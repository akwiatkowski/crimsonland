-- The gush when something dies: a full ring rather than a cone, thrown wider
-- and lasting longer than the per-hit spray in blood.lua. Scaled by the caller
-- to the size of whatever just came apart.
--
-- Two emitters: chunky splats, plus a fine mist that hangs a moment after the
-- heavy stuff has landed.

FXParm ("num_parts", 12);
FXParm ("bitmap", "game/particles.tga");
FXParm ("bitmap_rect", 65, 1, 30, 30);

FXParm ("age_to_die", 0.35, 0.7);
FXParm ("area_radius", 0, 6);
FXParm ("area_angle_spread", 360);

FXParm ("move_angle_spread", 360);
FXParm ("move_speed", 90, 320);
FXParm ("mass", 2.5);

FXParm ("angle_spread", 360);
FXParm ("rot_angle_rps", -300, 300);

FXParm ("alpha", 0.85, 1.0);
FXParm ("scale_graph", 0, 0.42);
FXParm ("scale_graph", 1, 0.20);
FXParm ("alpha_graph", 0, 1);
FXParm ("alpha_graph", 0.6, 1);
FXParm ("alpha_graph", 1, 0);


PartFXAddNew ();

-- the mist: smaller, slower, outlives the splats. A different splat shape from
-- the one above, and checked to be one of the red ones -- the sheet's top-left
-- corner holds a near-white sprite among the blood, which drew as pale bubbles.
PartFXParm ("num_parts", 8);
PartFXParm ("bitmap", "game/particles.tga");
PartFXParm ("bitmap_rect", 97, 1, 27, 31);

PartFXParm ("age_to_die", 0.5, 0.95);
PartFXParm ("area_radius", 0, 12);
PartFXParm ("area_angle_spread", 360);

PartFXParm ("move_angle_spread", 360);
PartFXParm ("move_speed", 20, 70);
PartFXParm ("mass", 4);

PartFXParm ("angle_spread", 360);
PartFXParm ("rot_angle_rps", -90, 90);

PartFXParm ("alpha", 0.35, 0.55);
PartFXParm ("scale_graph", 0, 0.16);
PartFXParm ("scale_graph", 1, 0.34);
PartFXParm ("alpha_graph", 0, 1);
PartFXParm ("alpha_graph", 0.35, 0.8);
PartFXParm ("alpha_graph", 1, 0);

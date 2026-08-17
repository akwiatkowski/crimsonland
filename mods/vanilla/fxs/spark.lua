-- The energy signature on an impact: a few bright sparks thrown off where a
-- bolt connects, over the blood the hit already draws.
--
-- One file for four families -- plasma, ion, pulse and flame -- because the
-- shape of the thing is the same and only the colour differs, and the colour
-- comes from the caller (particles.impact passes it as a spawn tint). That is
-- what the DSL's `color` addition is for.
--
-- Additive and short: this is light off a discharge, not a substance. It must
-- not outlive the blood, or an energy weapon would leave more mess than a
-- shotgun while doing the same damage.

FXParm ("num_parts", 5);
FXParm ("blend_mode", "ADDITIVE");
FXParm ("bitmap", "game/particles.tga");
-- the small round glow on the sheet, the same one the bolts are drawn with
FXParm ("bitmap_rect", 138, 74, 44, 44);

FXParm ("age_to_die", 0.12, 0.3);
FXParm ("area_radius", 0, 5);
FXParm ("area_angle_spread", 360);

-- thrown back along the way the shot came, in a wide fan
FXParm ("move_angle", 180);
FXParm ("move_angle_spread", 150);
FXParm ("move_speed", 120, 400);
FXParm ("mass", 4);

FXParm ("alpha", 0.8, 1.0);
FXParm ("scale_graph", 0, 0.22);
FXParm ("scale_graph", 1, 0.04);
FXParm ("alpha_graph", 0, 1);
FXParm ("alpha_graph", 0.5, 0.9);
FXParm ("alpha_graph", 1, 0);

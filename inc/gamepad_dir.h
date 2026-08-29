#ifndef GAMEPAD_DIR_H
#define GAMEPAD_DIR_H

#include <cmath>

// Returns 0..7 clockwise from North, or -1 inside the radial deadzone.
// SDL axes use +x = right and +y = down; adding half a wedge makes each
// direction's 45-degree interval centred rather than cardinal-biased.
static inline int gamepad_dir8_from_axes(int ax, int ay, int outer)
{
    const long long magnitude_squared =
        (long long)ax * ax + (long long)ay * ay;
    const long long outer_squared = (long long)outer * outer;
    if (magnitude_squared <= outer_squared)
        return -1;

    double deg = atan2((double)ax, (double)-ay) * 180.0 / M_PI;
    if (deg < 0)
        deg += 360.0;
    return ((int)((deg + 22.5) / 45.0)) & 7;
}

#endif

#include "inc/gamepad_dir.h"

#include <cassert>
#include <cmath>
#include <iostream>

int main()
{
    const int outer = 16000;
    assert(gamepad_dir8_from_axes(0, -30000, outer) == 0);
    assert(gamepad_dir8_from_axes(30000, 0, outer) == 2);
    assert(gamepad_dir8_from_axes(0, 30000, outer) == 4);
    assert(gamepad_dir8_from_axes(-30000, 0, outer) == 6);
    assert(gamepad_dir8_from_axes(20000, 20000, outer) == 3);
    assert(gamepad_dir8_from_axes(-20000, -20000, outer) == 7);
    assert(gamepad_dir8_from_axes(0, 0, outer) == -1);

    const double radians = 23.0 * M_PI / 180.0;
    assert(gamepad_dir8_from_axes(
        (int)(30000.0 * std::sin(radians)),
        (int)(-30000.0 * std::cos(radians)), outer) == 1);

    std::cout << "ok\n";
    return 0;
}

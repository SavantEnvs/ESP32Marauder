// PlatformIO's Unity runner supplies empty setUp/tearDown for test files that
// do not define them; Unity 2.6.0 itself does not, so provide weak defaults.
__attribute__((weak)) void setUp(void) {}
__attribute__((weak)) void tearDown(void) {}

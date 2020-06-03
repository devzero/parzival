const Builder = @import("std").build.Builder;

pub fn build(b: *Builder) void {
    const mode = b.standardReleaseOptions();
    const lib = b.addStaticLibrary("parzival", "src/parzival.zig");
    lib.setBuildMode(mode);
    lib.install();

    var parzival_tests = b.addTest("src/parzival.zig");
    parzival_tests.setBuildMode(mode);

    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&parzival_tests.step);
}

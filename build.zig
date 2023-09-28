const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const xev = b.dependency("libxev", .{ .target = target, .optimize = optimize });

    const exe = b.addExecutable(.{
        .name = "pomelo",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });
    exe.linkLibC();
    exe.addModule("xev", xev.module("xev"));

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const unit_tests = b.addTest(.{
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });
    unit_tests.linkLibC();
    unit_tests.addModule("xev", xev.module("xev"));

    const run_unit_tests = b.addRunArtifact(unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);

    const cov = std.build.Step.Run.create(b, "Test coverage");
    cov.addArgs(&[_][]const u8{ "kcov", "--include-path", ".", "kcov-output" });
    cov.addArtifactArg(unit_tests);
    b.step("cov", "Run tests and report coverage (requires kcov)").dependOn(&cov.step);
}

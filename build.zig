const std = @import("std");

// Although this function looks imperative, note that its job is to
// declaratively construct a build graph that will be executed by an external
// runner.
pub fn build(b: *std.Build) !void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard optimization options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall. Here we do not
    // set a preferred release mode, allowing the user to decide how to optimize.
    const optimize = b.standardOptimizeOption(.{});

    const sha1 = b.addStaticLibrary(.{
        .name = "sha1",
        .target = target,
        .optimize = optimize,
    });
    sha1.force_pic = true;
    sha1.addIncludePath(.{ .path = "deps/libzmq/external/sha1" });
    sha1.addCSourceFiles(&.{
        "deps/libzmq/external/sha1/sha1.c",
    }, &.{});
    sha1.linkLibC();

    const unity = b.addStaticLibrary(.{
        .name = "unity",
        .target = target,
        .optimize = optimize,
    });
    unity.force_pic = true;
    unity.addIncludePath(.{ .path = "deps/libzmq/external/unity" });
    unity.addCSourceFiles(&.{
        "deps/libzmq/external/unity/unity.c",
    }, &.{});
    unity.linkLibC();

    const zmq = b.addStaticLibrary(.{
        .name = "zmq",
        .target = target,
        .optimize = optimize,
    });
    zmq.force_pic = true;
    zmq.addIncludePath(.{ .path = "deps/libzmq/include" });
    zmq.addIncludePath(.{ .path = "deps/libzmq/src" });

    var sources = std.ArrayList([]const u8).init(b.allocator);
    {
        const prefix = "./deps/libzmq/src";
        var dir = try std.fs.cwd().openIterableDir(prefix, .{ .access_sub_paths = true });
        var walker = try dir.walk(b.allocator);
        defer walker.deinit();

        const allowed_exts = [_][]const u8{ ".c", ".cpp", ".cxx", ".c++", ".cc" };
        while (try walker.next()) |entry| {
            const ext = std.fs.path.extension(entry.basename);
            const include_file = for (allowed_exts) |e| {
                if (std.mem.eql(u8, ext, e))
                    break true;
            } else false;

            if (include_file) {
                const path = try std.fmt.allocPrint(b.allocator, "{s}/{s}", .{ prefix, entry.path });
                try sources.append(path);
            }
        }
    }
    zmq.addCSourceFiles(sources.items, &.{});
    zmq.linkLibC();
    zmq.linkLibCpp();
    zmq.linkLibrary(sha1);
    zmq.linkLibrary(unity);

    const exe = b.addExecutable(.{
        .name = "eden-pin",
        // In this case the main source file is merely a path, however, in more
        // complicated build scripts, this could be a generated file.
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    exe.linkLibC();
    exe.linkSystemLibrary("asound");
    exe.linkLibrary(zmq);

    // This declares intent for the executable to be installed into the
    // standard location when the user invokes the "install" step (the default
    // step when running `zig build`).
    b.installArtifact(exe);

    // This *creates* a Run step in the build graph, to be executed when another
    // step is evaluated that depends on it. The next line below will establish
    // such a dependency.
    const run_cmd = b.addRunArtifact(exe);

    // By making the run step depend on the install step, it will be run from the
    // installation directory rather than directly from within the cache directory.
    // This is not necessary, however, if the application depends on other installed
    // files, this ensures they will be present and in the expected location.
    run_cmd.step.dependOn(b.getInstallStep());

    // This allows the user to pass arguments to the application in the build
    // command itself, like this: `zig build run -- arg1 arg2 etc`
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    // This creates a build step. It will be visible in the `zig build --help` menu,
    // and can be selected like this: `zig build run`
    // This will evaluate the `run` step rather than the default, which is "install".
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    // Creates a step for unit testing. This only builds the test executable
    // but does not run it.
    const unit_tests = b.addTest(.{
        .root_source_file = .{ .path = "src/asound.zig" },
        .target = target,
        .optimize = optimize,
    });
    unit_tests.linkLibC();
    unit_tests.linkSystemLibrary("asound");
    unit_tests.linkSystemLibrary("zmq");

    const run_unit_tests = b.addRunArtifact(unit_tests);

    // Similar to creating the run step earlier, this exposes a `test` step to
    // the `zig build --help` menu, providing a way for the user to request
    // running the unit tests.
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);
}

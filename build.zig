const std = @import("std");

// Although this function looks imperative, note that its job is to
// declaratively construct a build graph that will be executed by an external
// runner.
pub fn build(b: *std.Build) void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard optimization options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall. Here we do not
    // set a preferred release mode, allowing the user to decide how to optimize.
    const optimize = b.standardOptimizeOption(.{});

    const zmq = b.addStaticLibrary(.{
        .name = "zmq",
        .target = target,
        .optimize = optimize,
    });
    zmq.linkLibC();
    zmq.linkLibCpp();
    zmq.force_pic = true;
    zmq.addIncludePath(.{ .path = "deps/libzmq/include" });
    zmq.addIncludePath(.{ .path = "deps/libzmq/src" });
    zmq.addCSourceFiles(&.{
        "deps/libzmq/src/address.cpp",
        "deps/libzmq/src/channel.cpp",
        "deps/libzmq/src/client.cpp",
        "deps/libzmq/src/clock.cpp",
        "deps/libzmq/src/ctx.cpp",
        "deps/libzmq/src/curve_client.cpp",
        "deps/libzmq/src/curve_mechanism_base.cpp",
        "deps/libzmq/src/curve_server.cpp",
        "deps/libzmq/src/dealer.cpp",
        "deps/libzmq/src/devpoll.cpp",
        "deps/libzmq/src/dgram.cpp",
        "deps/libzmq/src/dish.cpp",
        "deps/libzmq/src/dist.cpp",
        "deps/libzmq/src/endpoint.cpp",
        "deps/libzmq/src/epoll.cpp",
        "deps/libzmq/src/err.cpp",
        "deps/libzmq/src/fq.cpp",
        "deps/libzmq/src/gather.cpp",
        "deps/libzmq/src/gssapi_mechanism_base.cpp",
        "deps/libzmq/src/gssapi_client.cpp",
        "deps/libzmq/src/gssapi_server.cpp",
        "deps/libzmq/src/io_object.cpp",
        "deps/libzmq/src/io_thread.cpp",
        "deps/libzmq/src/ip.cpp",
        "deps/libzmq/src/ip_resolver.cpp",
        "deps/libzmq/src/ipc_address.cpp",
        "deps/libzmq/src/ipc_connecter.cpp",
        "deps/libzmq/src/ipc_listener.cpp",
        "deps/libzmq/src/kqueue.cpp",
        "deps/libzmq/src/lb.cpp",
        "deps/libzmq/src/mailbox.cpp",
        "deps/libzmq/src/mailbox_safe.cpp",
        "deps/libzmq/src/mechanism.cpp",
        "deps/libzmq/src/mechanism_base.cpp",
        "deps/libzmq/src/metadata.cpp",
        "deps/libzmq/src/msg.cpp",
        "deps/libzmq/src/mtrie.cpp",
        "deps/libzmq/src/norm_engine.cpp",
        "deps/libzmq/src/null_mechanism.cpp",
        "deps/libzmq/src/object.cpp",
        "deps/libzmq/src/options.cpp",
        "deps/libzmq/src/own.cpp",
        "deps/libzmq/src/pair.cpp",
        "deps/libzmq/src/peer.cpp",
        "deps/libzmq/src/pgm_receiver.cpp",
        "deps/libzmq/src/pgm_sender.cpp",
        "deps/libzmq/src/pgm_socket.cpp",
        "deps/libzmq/src/pipe.cpp",
        "deps/libzmq/src/plain_client.cpp",
        "deps/libzmq/src/plain_server.cpp",
        "deps/libzmq/src/poll.cpp",
        "deps/libzmq/src/poller_base.cpp",
        "deps/libzmq/src/polling_util.cpp",
        "deps/libzmq/src/pollset.cpp",
        "deps/libzmq/src/precompiled.cpp",
        "deps/libzmq/src/proxy.cpp",
        "deps/libzmq/src/pub.cpp",
        "deps/libzmq/src/pull.cpp",
        "deps/libzmq/src/push.cpp",
        "deps/libzmq/src/radio.cpp",
        "deps/libzmq/src/radix_tree.cpp",
        "deps/libzmq/src/random.cpp",
        "deps/libzmq/src/raw_decoder.cpp",
        "deps/libzmq/src/raw_encoder.cpp",
        "deps/libzmq/src/raw_engine.cpp",
        "deps/libzmq/src/reaper.cpp",
        "deps/libzmq/src/rep.cpp",
        "deps/libzmq/src/req.cpp",
        "deps/libzmq/src/router.cpp",
        "deps/libzmq/src/scatter.cpp",
        "deps/libzmq/src/select.cpp",
        "deps/libzmq/src/server.cpp",
        "deps/libzmq/src/session_base.cpp",
        "deps/libzmq/src/signaler.cpp",
        "deps/libzmq/src/socket_base.cpp",
        "deps/libzmq/src/socks.cpp",
        "deps/libzmq/src/socks_connecter.cpp",
        "deps/libzmq/src/stream.cpp",
        "deps/libzmq/src/stream_connecter_base.cpp",
        "deps/libzmq/src/stream_listener_base.cpp",
        "deps/libzmq/src/stream_engine_base.cpp",
        "deps/libzmq/src/sub.cpp",
        "deps/libzmq/src/tcp.cpp",
        "deps/libzmq/src/tcp_address.cpp",
        "deps/libzmq/src/tcp_connecter.cpp",
        "deps/libzmq/src/tcp_listener.cpp",
        "deps/libzmq/src/thread.cpp",
        "deps/libzmq/src/timers.cpp",
        "deps/libzmq/src/tipc_address.cpp",
        "deps/libzmq/src/tipc_connecter.cpp",
        "deps/libzmq/src/tipc_listener.cpp",
        "deps/libzmq/src/trie.cpp",
        "deps/libzmq/src/udp_address.cpp",
        "deps/libzmq/src/udp_engine.cpp",
        "deps/libzmq/src/v1_decoder.cpp",
        "deps/libzmq/src/v2_decoder.cpp",
        "deps/libzmq/src/v1_encoder.cpp",
        "deps/libzmq/src/v2_encoder.cpp",
        "deps/libzmq/src/v3_1_encoder.cpp",
        "deps/libzmq/src/vmci.cpp",
        "deps/libzmq/src/vmci_address.cpp",
        "deps/libzmq/src/vmci_connecter.cpp",
        "deps/libzmq/src/vmci_listener.cpp",
        "deps/libzmq/src/xpub.cpp",
        "deps/libzmq/src/xsub.cpp",
        "deps/libzmq/src/zmq.cpp",
        "deps/libzmq/src/zmq_utils.cpp",
        "deps/libzmq/src/decoder_allocators.cpp",
        "deps/libzmq/src/socket_poller.cpp",
        "deps/libzmq/src/zap_client.cpp",
        "deps/libzmq/src/zmtp_engine.cpp",
    }, &.{
        "-std=c++17",
        "-pedantic",
        "-Wall",
        "-W",
        "-Wno-missing-field-initializers",
    });

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
